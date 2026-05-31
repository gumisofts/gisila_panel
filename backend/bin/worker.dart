import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/workers/deployment_worker.dart';
import 'package:gisila_panel/workers/job_queue.dart';
import 'package:gisila_panel/workers/postgres_worker.dart';
import 'package:gisila_panel/workers/service_worker.dart';

Future<void> main(List<String> args) async {
  await init();
  final database = await Database.connect(databaseConfig);
  final deploymentWorker = DeploymentWorker(database);
  final serviceWorker = ServiceWorker(database);
  final postgresWorker = PostgresWorker(database);

  final queue = JobQueue();
  queue.on('gisila:queue:deployments', deploymentWorker.onDeployment);
  queue.on('gisila:queue:lifecycle', deploymentWorker.onLifecycle);
  queue.on('gisila:queue:vhosts', deploymentWorker.onVhost);
  queue.on('gisila:queue:ssl', deploymentWorker.onSsl);
  queue.on('gisila:queue:services', serviceWorker.onServiceJob);
  queue.on('gisila:queue:postgres', postgresWorker.onPostgresJob);

  logger.i('gisila-worker: starting');
  await queue.run();
}
