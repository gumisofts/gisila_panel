import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:gisila_agent/firewall/rules.dart';
import 'package:gisila_agent/runtime/priv.dart';

/// `gisila-agent firewall <status|apply|confirm|rollback>`: host firewall
/// (ufw) management for the panel's Firewall page.
///
/// Every change is reversible by design. `apply` first snapshots ufw's rule
/// files and schedules a rollback of them on a timer that does not depend on
/// the panel (a transient systemd timer, or a detached process). The panel
/// then has to `confirm` the change from a request that came through the new
/// rules; if it can't, because the change cut it off, the timer puts the old
/// rules back. On top of that, [FwGuard] refuses outright the changes that
/// would cut off SSH or the panel for the person making them.
Future<void> runFirewall(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: gisila-agent firewall <status|apply|confirm|rollback> '
        '[options]');
    exitCode = 64;
    return;
  }
  final parser = ArgParser()
    ..addOption('change-id')
    ..addOption('op', allowed: ['add', 'delete', 'enable', 'disable'])
    ..addOption('rule', help: 'JSON rule for add / delete')
    ..addMultiOption('keep-ip', help: 'Address that must stay able to connect')
    ..addMultiOption('protect-port', help: 'Extra port the panel is reached on')
    ..addOption('confirm-within', defaultsTo: '120');
  try {
    await _run(args.first, parser.parse(args.sublist(1)));
  } on FormatException catch (e) {
    throw FirewallError(e.message);
  } on StateError catch (e) {
    throw FirewallError(e.message);
  }
}

/// A refused or failed change, with a message fit for the user.
class FirewallError implements Exception {
  FirewallError(this.message);
  final String message;

  @override
  String toString() => message;
}

Future<void> _run(String sub, ArgResults opts) async {
  final fw = Firewall();
  switch (sub) {
    case 'status':
      stdout.writeln(jsonEncode({'ok': true, ...await fw.status()}));
    case 'apply':
      await fw.apply(
        changeId: _changeId(opts),
        op: opts['op'] as String? ??
            (throw const FormatException('--op is required')),
        rule: opts['rule'] as String?,
        keepIps: [
          for (final s in opts['keep-ip'] as List<String>)
            InternetAddress.tryParse(s) ??
                (throw FormatException('bad --keep-ip $s')),
        ],
        extraPorts: {
          for (final s in opts['protect-port'] as List<String>)
            int.tryParse(s) ?? (throw FormatException('bad --protect-port $s')),
        },
        confirmWithin: int.parse(opts['confirm-within'] as String),
      );
      stdout.writeln(jsonEncode({'ok': true, 'command': 'firewall apply'}));
    case 'confirm':
      final kept = await fw.confirm(_changeId(opts));
      stdout.writeln(jsonEncode({'ok': kept, 'command': 'firewall confirm',
          if (!kept) 'error': 'already rolled back'}));
      if (!kept) exitCode = 3;
    case 'rollback':
      final rolledBack = await fw.rollback(_changeId(opts));
      stdout.writeln(jsonEncode({'ok': true, 'command': 'firewall rollback',
          'rolledBack': rolledBack}));
    default:
      stderr.writeln('Unknown firewall subcommand $sub');
      exitCode = 64;
  }
}

int _changeId(ArgResults opts) {
  final id = int.tryParse(opts['change-id'] as String? ?? '');
  if (id == null || id <= 0) throw const FormatException('--change-id is required');
  return id;
}

class Firewall {
  Firewall({
    this.rulesDir = '/etc/ufw',
    this.stateDir = '/var/lib/gisila/firewall',
  });

  final String rulesDir;
  final String stateDir;

  /// Ports the panel is always reached on: nginx, and Let's Encrypt's
  /// HTTP challenge.
  static const webPorts = {80, 443};

  static const _ruleFiles = ['user.rules', 'user6.rules'];

  Future<bool> _hasUfw() async =>
      (await Process.run('sh', ['-c', 'command -v ufw'])).exitCode == 0;

  Future<bool> _active() async =>
      (await Priv.capture('ufw', ['status'], failOk: true))
          .startsWith('Status: active');

  Future<List<FwRule>> _rules() async => parseUfwRules(
        await Priv.readFile('$rulesDir/user.rules') ?? '',
        await Priv.readFile('$rulesDir/user6.rules') ?? '',
      );

  Future<Map<String, Object?>> status() async {
    if (!await _hasUfw()) {
      return {
        'available': false,
        'reason': 'ufw is not installed on this server.',
        'sshPorts': Priv.protectedPorts.toList()..sort(),
      };
    }
    final defaults = await Priv.readFile('/etc/default/ufw') ?? '';
    final policy = RegExp(r'^DEFAULT_INPUT_POLICY="?(\w+)"?', multiLine: true)
        .firstMatch(defaults)
        ?.group(1);
    final version =
        RegExp(r'ufw (\S+)').firstMatch(await Priv.capture('ufw', ['version'], failOk: true))?.group(1);
    return {
      'available': true,
      'active': await _active(),
      'version': version,
      'defaultIncoming': switch (policy) {
        'ACCEPT' => 'allow',
        'REJECT' => 'reject',
        'DROP' => 'deny',
        _ => null,
      },
      'sshPorts': Priv.protectedPorts.toList()..sort(),
      'rules': [for (final r in await _rules()) r.toJson()],
    };
  }

  Future<void> apply({
    required int changeId,
    required String op,
    required String? rule,
    required List<InternetAddress> keepIps,
    required Set<int> extraPorts,
    required int confirmWithin,
  }) async {
    if (!await _hasUfw()) throw StateError('ufw is not installed on this server.');
    if (confirmWithin < 30 || confirmWithin > 600) {
      throw const FormatException('--confirm-within must be 30-600 seconds');
    }
    final guard = FwGuard(
      sshPorts: Priv.protectedPorts,
      webPorts: {...webPorts, ...extraPorts},
      keepIps: keepIps,
    );
    final live = await _rules();
    final active = await _active();
    final FwRule? r = switch (op) {
      'add' || 'delete' => FwRule.request(
          jsonDecode(rule ?? (throw const FormatException('--rule is required')))
              as Map<String, Object?>),
      _ => null,
    };
    final problem = switch (op) {
      'add' => guard.checkAdd(r!),
      'delete' => guard.checkDelete(r!, live, active),
      'enable' => guard.checkEnable(live),
      _ => null,
    };
    if (problem != null) throw StateError(problem);

    final commands = switch (op) {
      'add' => [r!.addArgs()],
      'delete' => [r!.deleteArgs()],
      'enable' => [
          // Never turn the firewall on without SSH and the panel let in.
          for (final p in guard.protectedPorts.toList()..sort())
            if (!live.any((l) => !l.blocks && l.from == 'any' && l.coversTcp(p)))
              ['allow', 'proto', 'tcp', 'from', 'any', 'to', 'any', 'port', '$p',
                  'comment', '${FwRule.baseComment}: ${_portName(p, guard)}'],
          ['--force', 'enable'],
        ],
      _ => [
          ['disable'],
        ],
    };

    // A rollback restores the rules from before its change, so a change
    // made while an earlier one is unconfirmed could be undone with it.
    final open = _pendingChanges().where((id) => id != changeId);
    if (open.isNotEmpty) {
      throw StateError('Change ${open.first} is still waiting to be confirmed '
          'or rolled back. Try again in a moment.');
    }
    final dir = await _snapshot(changeId, active);
    await _scheduleRollback(changeId, confirmWithin);
    try {
      for (final c in commands) {
        await Priv.sudo('ufw', c);
      }
    } catch (e) {
      await _restore(dir);
      await _setState(dir, 'rolled_back');
      rethrow;
    }
  }

  String _portName(int p, FwGuard guard) => guard.sshPorts.contains(p)
      ? 'ssh'
      : p == 80
          ? 'http'
          : p == 443
              ? 'https'
              : 'panel';

  /// Keep the change: the panel reached us through the new rules. False when
  /// the rollback already ran.
  Future<bool> confirm(int changeId) async {
    final dir = Directory('$stateDir/changes/$changeId');
    if (!dir.existsSync()) throw StateError('No snapshot for change $changeId');
    final kept = await _locked(dir, () async {
      if (_state(dir) == 'rolled_back') return false;
      await _setState(dir, 'confirmed');
      return true;
    });
    if (await _hasSystemd()) {
      await Priv.sudo('systemctl', ['stop', '${_unit(changeId)}.timer'],
          failOk: true);
    }
    return kept;
  }

  /// Put back the rules from before the change, unless it was confirmed.
  /// True when the rules were restored (now or by an earlier call).
  Future<bool> rollback(int changeId) async {
    final dir = Directory('$stateDir/changes/$changeId');
    if (!dir.existsSync()) return false;
    return _locked(dir, () async {
      switch (_state(dir)) {
        case 'confirmed':
          return false;
        case 'rolled_back':
          return true;
      }
      await _restore(dir);
      await _setState(dir, 'rolled_back');
      stderr.writeln('[agent] firewall change $changeId rolled back');
      return true;
    });
  }

  Future<Directory> _snapshot(int changeId, bool active) async {
    final dir = Directory('$stateDir/changes/$changeId');
    if (dir.existsSync()) {
      throw StateError('Change $changeId was already applied once.');
    }
    _prune();
    dir.createSync(recursive: true);
    for (final f in _ruleFiles) {
      final text = await Priv.readFile('$rulesDir/$f');
      if (text != null) File('${dir.path}/$f').writeAsStringSync(text);
    }
    File('${dir.path}/active').writeAsStringSync(active ? '1' : '0');
    File('${dir.path}/state').writeAsStringSync('pending');
    return dir;
  }

  Future<void> _restore(Directory dir) async {
    for (final f in _ruleFiles) {
      final saved = File('${dir.path}/$f');
      if (saved.existsSync()) {
        await Priv.writeFile('$rulesDir/$f', saved.readAsStringSync());
      }
    }
    final wasActive = File('${dir.path}/active').readAsStringSync() == '1';
    final isActive = await _active();
    if (wasActive) {
      await Priv.sudo('ufw', isActive ? ['reload'] : ['--force', 'enable']);
    } else if (isActive) {
      await Priv.sudo('ufw', ['disable']);
    }
  }

  String _state(Directory dir) {
    final f = File('${dir.path}/state');
    return f.existsSync() ? f.readAsStringSync().trim() : 'pending';
  }

  Future<void> _setState(Directory dir, String state) async =>
      File('${dir.path}/state').writeAsStringSync(state);

  /// Confirm and rollback race when the deadline is close; a file lock
  /// makes them take turns, so exactly one of them wins.
  Future<T> _locked<T>(Directory dir, Future<T> Function() body) async {
    final lock = File('${dir.path}/lock').openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.blockingExclusive);
      return await body();
    } finally {
      lock.closeSync();
    }
  }

  String _unit(int changeId) => 'gisila-fw-rollback-$changeId';

  /// Run `firewall rollback` for [changeId] in [seconds], outside the
  /// worker: a transient systemd timer where systemd runs (it survives the
  /// worker restarting), or else a detached shell.
  Future<void> _scheduleRollback(int changeId, int seconds) async {
    final self = [
      Platform.resolvedExecutable,
      if (Platform.script.path.endsWith('.dart')) Platform.script.toFilePath(),
    ];
    final cmd = [...self, 'firewall', 'rollback', '--change-id', '$changeId'];
    if (await _hasSystemd()) {
      await Priv.sudo('systemd-run', [
        '--unit=${_unit(changeId)}',
        '--on-active=${seconds}s',
        '--timer-property=AccuracySec=1s',
        '--',
        ...cmd,
      ]);
      return;
    }
    await Process.start(
      'sh',
      ['-c', 'sleep $seconds; exec "\$@"', 'sh', ...cmd],
      mode: ProcessStartMode.detached,
    );
  }

  List<int> _pendingChanges() {
    final changes = Directory('$stateDir/changes');
    if (!changes.existsSync()) return const [];
    return [
      for (final d in changes.listSync().whereType<Directory>())
        if (_state(d) == 'pending') int.tryParse(d.path.split('/').last) ?? 0,
    ];
  }

  Future<bool> _hasSystemd() async =>
      Directory('/run/systemd/system').existsSync() &&
      (await Process.run('sh', ['-c', 'command -v systemd-run'])).exitCode == 0;

  /// Snapshots older than a day are long settled.
  void _prune() {
    final changes = Directory('$stateDir/changes');
    if (!changes.existsSync()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    for (final d in changes.listSync().whereType<Directory>()) {
      try {
        if (d.statSync().modified.isBefore(cutoff)) d.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}
