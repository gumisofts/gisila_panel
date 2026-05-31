import 'package:gisila/gisila.dart';

String? _hostnameValidator(String value) {
  final re = RegExp(r'^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$');
  if (!re.hasMatch(value.toLowerCase())) {
    return 'Not a valid hostname.';
  }
  return null;
}

class AddDomainForm extends Form {
  final hostname = StringField(
    name: 'hostname',
    required: true,
    validators: <FieldValidator<String>>[_hostnameValidator],
  );
  final isPrimary = BoolField(name: 'isPrimary');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[hostname, isPrimary];
}
