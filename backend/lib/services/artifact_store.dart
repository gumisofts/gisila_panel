import 'dart:io' hide HttpException;
import 'dart:math';

import 'package:gisila/gisila.dart' show BadRequest, HttpException;
import 'package:gisila_panel/config.dart' show env;

/// Uploaded build artifacts for `binary` and `zip` apps.
///
/// Each upload is stored as `<root>/apps/<appId>/<id>.bin|.zip`, where `id`
/// is 32 random hex characters handed back to the client. A deployment names
/// the upload by that id; the server resolves it to a path, so a client can
/// never point a build at a file of its choosing. The root agent checks the
/// same layout again (`AgentValidators.requireArtifactPath`) before reading.
class ArtifactStore {
  ArtifactStore({String? root, this.maxBytes = defaultMaxBytes, this.keep = 5})
      : root = root ?? defaultRoot;

  /// Matches the panel's request body cap and nginx's `client_max_body_size`.
  static const defaultMaxBytes = 50 * 1024 * 1024;

  /// Must match the agent's default; set GISILA_ARTIFACT_DIR in
  /// /etc/gisila/.env to move it (both services load that file).
  static String get defaultRoot => env.getOrElse(
      'GISILA_ARTIFACT_DIR', () => '/var/lib/gisila/artifacts');

  static final _idRe = RegExp(r'^[0-9a-f]{32}$');

  final String root;
  final int maxBytes;

  /// Uploads kept per app; older ones are deleted when a new one arrives.
  /// Rollbacks use the published releases, not the uploads.
  final int keep;

  static String extensionFor(String sourceType) => switch (sourceType) {
        'binary' => 'bin',
        'zip' => 'zip',
        _ => throw BadRequest(
            'Only binary and zip apps deploy from an upload; this app uses '
            '$sourceType.'),
      };

  /// Streams [body] to disk for [appId] and returns the new upload's id.
  ///
  /// The size cap is counted here rather than trusted from Content-Length,
  /// and the first bytes must look like the declared kind: a ZIP archive, or
  /// an ELF executable or `#!` script for a binary.
  Future<String> save(
    int appId,
    String sourceType,
    Stream<List<int>> body,
  ) async {
    final ext = extensionFor(sourceType);
    final dir = Directory('$root/apps/$appId');
    try {
      await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      throw HttpException(
        503,
        'Artifact storage is not writable (${e.path ?? root}). Create it with '
        '`install -d -o gisila -g gisila -m 0750 $root`.',
        code: 'artifact_storage_unavailable',
      );
    }

    final id = _newId();
    final part = File('${dir.path}/.$id.part');
    final sink = part.openWrite();
    var size = 0;
    final head = <int>[];
    try {
      await for (final chunk in body) {
        size += chunk.length;
        if (size > maxBytes) {
          throw HttpException(
              413, 'Uploads are limited to ${maxBytes ~/ (1024 * 1024)} MB.',
              code: 'payload_too_large');
        }
        if (head.length < 4) head.addAll(chunk.take(4 - head.length));
        sink.add(chunk);
      }
      await sink.close();
      if (size == 0) throw BadRequest('The uploaded file is empty.');
      _checkMagic(sourceType, head);
    } catch (_) {
      await sink.close().catchError((_) {});
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }

    await part.rename('${dir.path}/$id.$ext');
    _prune(dir);
    return id;
  }

  /// Path of [appId]'s upload [id] of kind [sourceType], or null when there
  /// is no such upload (wrong app, wrong kind, pruned, or a malformed id).
  String? resolve(int appId, String id, String sourceType) {
    if (!_idRe.hasMatch(id)) return null;
    final path = '$root/apps/$appId/$id.${extensionFor(sourceType)}';
    return FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.file
        ? path
        : null;
  }

  static void _checkMagic(String sourceType, List<int> head) {
    bool startsWith(List<int> magic) =>
        head.length >= magic.length &&
        Iterable<int>.generate(magic.length).every((i) => head[i] == magic[i]);
    if (sourceType == 'zip') {
      if (!startsWith(const [0x50, 0x4b, 0x03, 0x04])) {
        throw BadRequest('The upload is not a ZIP archive.');
      }
    } else if (!startsWith(const [0x7f, 0x45, 0x4c, 0x46]) &&
        !startsWith(const [0x23, 0x21])) {
      throw BadRequest(
          'The upload is not a Linux executable (ELF binary or #! script).');
    }
  }

  /// Keeps the newest [keep] uploads, and drops partial files left by
  /// uploads that died more than an hour ago.
  void _prune(Directory dir) {
    final all = dir.listSync(followLinks: false).whereType<File>().toList();
    bool isPart(File f) => f.uri.pathSegments.last.startsWith('.');
    final staleBefore = DateTime.now().subtract(const Duration(hours: 1));
    final uploads = all.where((f) => !isPart(f)).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final old in [
      ...uploads.skip(keep),
      ...all.where((f) => isPart(f) && f.statSync().modified.isBefore(staleBefore)),
    ]) {
      try {
        old.deleteSync();
      } on FileSystemException {
        // Gone already, or in use by a build that is reading it.
      }
    }
  }

  static String _newId() {
    final rng = Random.secure();
    return List<String>.generate(
        16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
