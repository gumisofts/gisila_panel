import 'package:gisila/gisila.dart';

class CreateTeamForm extends Form {
  final name = StringField(name: 'name', required: true, maxLength: 80);
  final slug = StringField(name: 'slug', maxLength: 60);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[name, slug];
}

class InviteMemberForm extends Form {
  final email = EmailField(name: 'email', required: true);
  final role = StringField(name: 'role'); // owner|admin|developer|viewer

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[email, role];
}
