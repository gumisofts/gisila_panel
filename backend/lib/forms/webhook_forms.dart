import 'package:gisila/gisila.dart';

class StatusTokenForm extends Form {
  final token = StringField(name: 'token', required: true, maxLength: 500);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[token];
}
