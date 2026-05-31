import 'package:gisila/gisila.dart';

String? _strongPassword(String value) {
  if (value.length < 8) {
    return 'Password must be at least 8 characters long.';
  }
  return null;
}

class RegisterForm extends Form {
  final email = EmailField(name: 'email', required: true);
  final password = StringField(
    name: 'password',
    required: true,
    validators: <FieldValidator<String>>[_strongPassword],
  );
  final firstName = StringField(name: 'firstName');
  final lastName = StringField(name: 'lastName');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        email,
        password,
        firstName,
        lastName,
      ];
}

class LoginForm extends Form {
  final email = EmailField(name: 'email', required: true);
  final password = StringField(name: 'password', required: true);

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[email, password];
}

class ChangePasswordForm extends Form {
  final oldPassword = StringField(name: 'oldPassword', required: true);
  final newPassword = StringField(
    name: 'newPassword',
    required: true,
    validators: <FieldValidator<String>>[_strongPassword],
  );

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[oldPassword, newPassword];
}

class UpdateProfileForm extends Form {
  final firstName = StringField(name: 'firstName');
  final lastName = StringField(name: 'lastName');
  final avatarUrl = StringField(name: 'avatarUrl');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[firstName, lastName, avatarUrl];
}
