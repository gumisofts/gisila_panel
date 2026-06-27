#!/usr/bin/env dart
//
// Standalone migration runner.
//
// `infra/install.sh` runs migrations with `dart run gisila_orm:migrate`, which
// needs the Dart SDK. This entry point exists so the same migration logic can
// be compiled to a self-contained native binary (`gisila-migrate`) and shipped
// in the prebuilt release — letting `infra/install-prebuilt.sh` migrate without
// any Dart toolchain. It uses the exact same MigrationManager (and therefore
// the same migration-tracking table) as the package runner, so the two are
// interchangeable.
//
// Usage:
//   gisila-migrate up     --dir <path> --config <yaml>
//   gisila-migrate down   --dir <path> --config <yaml> [--steps N]
//   gisila-migrate status --dir <path> --config <yaml>

import 'dart:io';

import 'package:gisila_orm/gisila.dart';

const _defaultDir = 'lib';
const _defaultConfig = 'database.yaml';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(64);
  }

  final command = args.first;
  final flags = _parseFlags(args.sublist(1));
  final configPath = flags['config'] ?? _defaultConfig;
  final dir = flags['dir'] ?? _defaultDir;
  final steps = int.tryParse(flags['steps'] ?? '1') ?? 1;

  final config = await DatabaseConfig.fromFile(configPath);
  final db = await Database.connect(config);
  final manager = MigrationManager(db);

  try {
    final discovered = await manager.discoverIn(dir);
    switch (command) {
      case 'up':
        final result = await manager.up(discovered);
        if (result.applied.isEmpty) {
          stdout.writeln('Nothing to apply. Database is up to date.');
        } else {
          stdout.writeln(
              'Applied ${result.applied.length} migration(s) in batch ${result.batch}:');
          for (final m in result.applied) {
            stdout.writeln('  - ${m.id}');
          }
        }
        break;

      case 'down':
        final result = await manager.down(discovered: discovered, steps: steps);
        if (result.rolledBack.isEmpty) {
          stdout.writeln('Nothing to roll back.');
        } else {
          stdout
              .writeln('Rolled back ${result.rolledBack.length} migration(s):');
          for (final m in result.rolledBack) {
            stdout.writeln('  - ${m.id}');
          }
        }
        break;

      case 'status':
        final applied = await manager.listApplied();
        final appliedIds = applied.map((a) => a.id).toSet();
        stdout.writeln(
            'Discovered: ${discovered.length}, applied: ${applied.length}');
        for (final m in discovered) {
          final mark = appliedIds.contains(m.id) ? '[x]' : '[ ]';
          stdout.writeln('  $mark ${m.id}');
        }
        break;

      default:
        _usage();
        exit(64);
    }
  } finally {
    await db.close();
  }
}

Map<String, String> _parseFlags(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (a.startsWith('--') && i + 1 < argv.length) {
      out[a.substring(2)] = argv[i + 1];
      i++;
    }
  }
  return out;
}

void _usage() {
  stderr.writeln(
    'gisila-migrate <up|down|status> --dir <path> --config <yaml> [--steps N]',
  );
}
