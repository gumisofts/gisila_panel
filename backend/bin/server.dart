import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/server.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_hotreload/shelf_hotreload.dart';

Future<void> main(List<String> args) async {
  await init();

  // --seed-superuser: create the initial admin account and exit.
  // Called by install.sh right after the migration, before the server starts.
  if (args.contains('--seed-superuser')) {
    await seedSuperuser();
    return;
  }

  final port = int.parse(env.getOrElse('PORT', () => '8000'));
  final isDev = args.contains('--dev') || args.contains('dev');

  if (isDev) {
    _createDevServer(port);
  } else {
    await _createProdServer(port);
  }

  logger.i('gisila-panel: HTTP server listening on :$port'
      '${isDev ? ' (hot-reload)' : ''}');
  logger.i('  docs       → http://localhost:$port/docs');
  logger.i('  admin      → http://localhost:$port/admin');
  logger.i('  openapi    → http://localhost:$port/openapi.json');
}

Future<void> _createProdServer(int port) async {
  // Spawn one isolate per CPU and share the port between them.
  for (var i = 0; i < Platform.numberOfProcessors; i++) {
    await Isolate.spawn(
      debugName: 'gisila-panel-$i',
      (int p) async {
        await init();
        final handler = await application();
        final server = await serve(handler, '0.0.0.0', p, shared: true);
        server.autoCompress = true;
      },
      port,
    );
  }

  final handler = await application();
  final server = await serve(handler, '0.0.0.0', port, shared: true);
  server.autoCompress = true;
}

void _createDevServer(int port) => withHotreload(() async {
      final handler = await application();
      return serve(handler, '0.0.0.0', port, shared: true);
    });
