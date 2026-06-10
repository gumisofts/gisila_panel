import 'dart:async';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/workers/deployment_worker.dart';
import 'package:gisila_panel/workers/exec_worker.dart';
import 'package:gisila_panel/workers/job_queue.dart';
import 'package:gisila_panel/workers/mail_worker.dart';
import 'package:gisila_panel/workers/metrics_worker.dart';
import 'package:gisila_panel/workers/postgres_worker.dart';
import 'package:gisila_panel/workers/service_worker.dart';

Future<void> main(List<String> args) async {
  await init();
  final database = await Database.connect(databaseConfig);
  final deploymentWorker = DeploymentWorker(database);
  final serviceWorker = ServiceWorker(database);
  final postgresWorker = PostgresWorker(database);
  final execWorker = ExecWorker(database);
  final mailWorker = MailWorker(database);

  final queue = JobQueue();
  queue.on('gisila:queue:deployments', deploymentWorker.onDeployment);
  queue.on('gisila:queue:lifecycle', deploymentWorker.onLifecycle);
  queue.on('gisila:queue:vhosts', deploymentWorker.onVhost);
  queue.on('gisila:queue:ssl', deploymentWorker.onSsl);
  queue.on('gisila:queue:services', serviceWorker.onServiceJob);
  queue.on('gisila:queue:postgres', postgresWorker.onPostgresJob);
  queue.on('gisila:queue:exec', execWorker.onExecJob);
  queue.on('gisila:queue:mail', mailWorker.onMailJob);

  // Self-driven periodic metrics collector (CPU / memory samples per app).
  MetricsCollector(database).start();

  logger.i('gisila-worker: starting');

  // Re-apply the mail config on boot ONLY when the tooling is already installed
  // (e.g. after a reboot). Installation is optional and operator-initiated from
  // the panel's Mail page, so a fresh host is left untouched until then. Runs in
  // the background so it never delays the job loop.
  unawaited(() async {
    try {
      if (await mailWorker.isStackInstalled()) {
        await mailWorker.onMailJob({'action': 'sync'});
        logger.i('gisila-worker: mail stack present — config re-synced');
      } else {
        logger.i('gisila-worker: mail tooling not installed — skipping '
            '(install it from the panel Mail page)');
      }
    } catch (e, st) {
      logger.w('gisila-worker: mail bootstrap check failed', error: e, stackTrace: st);
    }
  }());

  await queue.run();
}
