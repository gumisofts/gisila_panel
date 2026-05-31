import 'package:gisila/gisila.dart';

class CreateApiTokenForm extends Form {
  final name = StringField(name: 'name', required: true, maxLength: 80);
  final expiresInDays = IntField(name: 'expiresInDays');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[name, expiresInDays];
}

class AddSshKeyForm extends Form {
  final name = StringField(name: 'name', required: true, maxLength: 80);
  final publicKey = StringField(name: 'publicKey', required: true);
  final algorithm = StringField(name: 'algorithm');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[name, publicKey, algorithm];
}

class GenerateSshKeyForm extends Form {
  final name = StringField(name: 'name', required: true, maxLength: 80);
  final algorithm = StringField(name: 'algorithm', required: true);

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[name, algorithm];
}
