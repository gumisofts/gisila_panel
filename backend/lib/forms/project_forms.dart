import 'package:gisila/gisila.dart';

class CreateProjectForm extends Form {
  final teamId = IntField(name: 'teamId', required: true);
  final name = StringField(name: 'name', required: true, maxLength: 80);
  final description = StringField(name: 'description');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[teamId, name, description];
}

class UpdateProjectForm extends Form {
  final name = StringField(name: 'name', maxLength: 80);
  final description = StringField(name: 'description');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[name, description];
}
