import 'package:gisila/gisila.dart';

/// `PUT /notifications/settings` — update the panel-wide outbound SMTP config.
/// All fields optional (partial update); an empty `smtpPassword` means "leave
/// the stored password alone" (see `NotificationCore.updateSmtpConfig`).
class UpdateSmtpConfigForm extends Form {
  final smtpHost = StringField(name: 'smtpHost', maxLength: 255);
  final smtpPort = IntField(name: 'smtpPort', min: 1, max: 65535);
  final smtpUsername = StringField(name: 'smtpUsername', maxLength: 255);
  final smtpPassword = StringField(name: 'smtpPassword', maxLength: 255, trim: false);
  final smtpSecurity = StringField(name: 'smtpSecurity', maxLength: 16);
  final fromEmail = StringField(name: 'fromEmail', maxLength: 255);
  final fromName = StringField(name: 'fromName', maxLength: 128);
  final emailEnabled = BoolField(name: 'emailEnabled');

  @override
  List<FormField<Object?>> collectFields() => [
        smtpHost,
        smtpPort,
        smtpUsername,
        smtpPassword,
        smtpSecurity,
        fromEmail,
        fromName,
        emailEnabled,
      ];
}

/// `POST /notifications/settings/test` — send a one-off test email.
class SendTestEmailForm extends Form {
  final toEmail = EmailField(name: 'toEmail', required: true);

  @override
  List<FormField<Object?>> collectFields() => [toEmail];
}

/// `POST /notifications/rules` — create an [AlertRule].
class CreateAlertRuleForm extends Form {
  final scope = StringField(name: 'scope', required: true, maxLength: 16);
  final appId = IntField(name: 'appId');
  final postgresInstanceId = IntField(name: 'postgresInstanceId');
  final mongoInstanceId = IntField(name: 'mongoInstanceId');
  final managedServiceId = IntField(name: 'managedServiceId');
  final applicationId = IntField(name: 'applicationId');
  final metric = StringField(name: 'metric', required: true, maxLength: 32);
  final comparison = StringField(name: 'comparison', maxLength: 8);
  final thresholdPercent = IntField(name: 'thresholdPercent', min: 0, max: 100);
  final severity = StringField(name: 'severity', maxLength: 16);
  final cooldownMinutes = IntField(name: 'cooldownMinutes', min: 1, max: 1440);
  final enabled = BoolField(name: 'enabled');
  final notifyEmail = BoolField(name: 'notifyEmail');

  @override
  List<FormField<Object?>> collectFields() => [
        scope,
        appId,
        postgresInstanceId,
        mongoInstanceId,
        managedServiceId,
        applicationId,
        metric,
        comparison,
        thresholdPercent,
        severity,
        cooldownMinutes,
        enabled,
        notifyEmail,
      ];
}

/// `PUT /notifications/rules/{id}` — update an [AlertRule]. Scope/target are
/// immutable after creation (delete + recreate instead of re-pointing a rule
/// at a different app/instance).
class UpdateAlertRuleForm extends Form {
  final metric = StringField(name: 'metric', maxLength: 32);
  final comparison = StringField(name: 'comparison', maxLength: 8);
  final thresholdPercent = IntField(name: 'thresholdPercent', min: 0, max: 100);
  final severity = StringField(name: 'severity', maxLength: 16);
  final cooldownMinutes = IntField(name: 'cooldownMinutes', min: 1, max: 1440);
  final enabled = BoolField(name: 'enabled');
  final notifyEmail = BoolField(name: 'notifyEmail');

  @override
  List<FormField<Object?>> collectFields() => [
        metric,
        comparison,
        thresholdPercent,
        severity,
        cooldownMinutes,
        enabled,
        notifyEmail,
      ];
}
