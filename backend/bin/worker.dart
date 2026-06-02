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

  // Provision the Postfix + Dovecot + OpenDKIM mail stack on boot so it is
  // always available without a catalog install. Runs in the background so it
  // never delays the job loop; failures are logged and retried on the next sync.
  unawaited(() async {
    try {
      await mailWorker.onMailJob({'action': 'sync'});
      logger.i('gisila-worker: mail stack provisioned');
    } catch (e, st) {
      logger.w('gisila-worker: mail bootstrap failed (will retry on next sync)',
          error: e, stackTrace: st);
    }
  }());

  await queue.run();
}
