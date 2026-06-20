import 'package:gisila/gisila.dart';

class TriggerDeploymentForm extends Form {
  // binary | git | zip
  final sourceType = StringField(name: 'sourceType', required: true);
  final gitCommitSha = StringField(name: 'gitCommitSha');
  // Reference to a previously uploaded artifact (id returned by /uploads).
  final artifactId = StringField(name: 'artifactId');
  // Force a clean rebuild: bypass the agent's dependency/build cache and
  // reinstall everything from scratch. Defaults to false (cached deploy).
  final forceRebuild = BoolField(name: 'forceRebuild');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[sourceType, gitCommitSha, artifactId, forceRebuild];
}
