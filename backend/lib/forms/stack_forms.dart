import 'package:gisila/gisila.dart';

class CreateStackForm extends Form {
  final projectId = IntField(name: 'projectId', required: true);
  final name = StringField(name: 'name', required: true, maxLength: 80);
  final description = StringField(name: 'description');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[projectId, name, description];
}

class UpdateStackForm extends Form {
  final name = StringField(name: 'name', maxLength: 80);
  final description = StringField(name: 'description');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[name, description];
}
