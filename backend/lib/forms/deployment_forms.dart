import 'package:gisila/gisila.dart';

class TriggerDeploymentForm extends Form {
  // binary | git | zip
  final sourceType = StringField(name: 'sourceType', required: true);
  final gitCommitSha = StringField(name: 'gitCommitSha');
  // Reference to a previously uploaded artifact (id returned by /uploads).
  final artifactId = StringField(name: 'artifactId');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[sourceType, gitCommitSha, artifactId];
}
