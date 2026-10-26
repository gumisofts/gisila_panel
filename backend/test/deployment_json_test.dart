import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/deployments_service.dart';
import 'package:test/test.dart';

void main() {
  test('the public deployment JSON leaves out the env snapshot and paths', () {
    final json = DeploymentsService.toPublicJson(
      Deployment(
        id: 4,
        appId: 1,
        sourceType: 'zip',
        artifactPath: '/var/lib/gisila/artifacts/apps/1/${'a' * 32}.zip',
        deployConfig: '{"env":{"DATABASE_PASSWORD":"hunter2"}}',
        createdAt: DateTime.utc(2026, 10, 27),
      ),
      canRollback: true,
    );
    expect(json.toString(), isNot(contains('hunter2')));
    expect(json.toString(), isNot(contains('/var/lib/gisila')));
    expect(json['id'], 4);
    expect(json['canRollback'], isTrue);
  });
}
