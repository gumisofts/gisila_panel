import 'package:gisila/gisila.dart';

/// `POST /services` — install a new service.
class InstallServiceForm extends Form {
  final serviceType =
      StringField(name: 'serviceType', required: true, maxLength: 64);
  final displayName =
      StringField(name: 'displayName', required: true, maxLength: 128);
  // Arbitrary key→value config object, validated in the service layer.
  final config = JsonField(name: 'config');

  @override
  List<FormField<Object?>> collectFields() =>
      [serviceType, displayName, config];
}

/// `PUT /services/{id}/config` — update service configuration.
class UpdateServiceConfigForm extends Form {
  final config = JsonField(name: 'config', required: true);

  @override
  List<FormField<Object?>> collectFields() => [config];
}
