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
  // Login is a credential check, not a sign-up: accept any string and let
  // authentication fail if the account doesn't exist. Using EmailField here
  // would reject otherwise-valid local accounts such as the default superuser
  // `admin@localhost` (seeded on hosts without a domain), locking them out.
  final email = StringField(name: 'email', required: true);
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

/// Used by superusers to create a new user account.
class CreateUserForm extends Form {
  final email = EmailField(name: 'email', required: true);
  final password = StringField(
    name: 'password',
    required: true,
    validators: <FieldValidator<String>>[_strongPassword],
  );
  final firstName = StringField(name: 'firstName');
  final lastName = StringField(name: 'lastName');
  final isSuperuser = BoolField(name: 'isSuperuser');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        email,
        password,
        firstName,
        lastName,
        isSuperuser,
      ];
}

/// Used by superusers to update another user's account flags.
class UpdateUserForm extends Form {
  final firstName = StringField(name: 'firstName');
  final lastName = StringField(name: 'lastName');
  final isActive = BoolField(name: 'isActive');
  final isSuperuser = BoolField(name: 'isSuperuser');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        firstName,
        lastName,
        isActive,
        isSuperuser,
      ];
}

/// Second step of a login for an account with 2FA.
class MfaLoginForm extends Form {
  final challenge = StringField(name: 'challenge', required: true);
  final code = StringField(name: 'code', required: true);

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[challenge, code];
}

class PasswordConfirmForm extends Form {
  final password = StringField(name: 'password', required: true);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[password];
}

class TotpCodeForm extends Form {
  final code = StringField(name: 'code', required: true);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[code];
}

class TotpDisableForm extends Form {
  final password = StringField(name: 'password', required: true);
  final code = StringField(name: 'code', required: true);

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[password, code];
}
