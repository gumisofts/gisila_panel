import 'package:gisila/gisila.dart';

/// `POST /mail/domains` — add a virtual mail domain.
class MailDomainForm extends Form {
  final domain = StringField(name: 'domain', required: true, maxLength: 253);

  @override
  List<FormField<Object?>> collectFields() => [domain];
}

/// `POST /mail/domains/{id}/accounts` — create a mailbox.
class MailAccountForm extends Form {
  final localPart = StringField(name: 'localPart', required: true, maxLength: 64);
  final password = StringField(name: 'password', required: true, maxLength: 256);
  final quotaMb = IntField(name: 'quotaMb');

  @override
  List<FormField<Object?>> collectFields() => [localPart, password, quotaMb];
}

/// `PUT /mail/accounts/{id}/password` — reset a mailbox password.
class MailPasswordForm extends Form {
  final password = StringField(name: 'password', required: true, maxLength: 256);

  @override
  List<FormField<Object?>> collectFields() => [password];
}
