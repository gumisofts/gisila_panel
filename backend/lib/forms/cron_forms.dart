import 'package:gisila/gisila.dart';

class CreateCronJobForm extends Form {
  final name = StringField(name: 'name', required: true, maxLength: 100);
  // 5-field cron expression or @daily-style shortcut, in UTC.
  final schedule = StringField(name: 'schedule', required: true, maxLength: 100);
  final command = StringField(name: 'command', required: true, maxLength: 4000);
  final timeoutSeconds = IntField(name: 'timeoutSeconds', min: 1, max: 3600);
  final enabled = BoolField(name: 'enabled');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        name,
        schedule,
        command,
        timeoutSeconds,
        enabled,
      ];
}

/// Partial update: only the fields sent are changed.
class UpdateCronJobForm extends Form {
  final name = StringField(name: 'name', maxLength: 100);
  final schedule = StringField(name: 'schedule', maxLength: 100);
  final command = StringField(name: 'command', maxLength: 4000);
  final timeoutSeconds = IntField(name: 'timeoutSeconds', min: 1, max: 3600);
  final enabled = BoolField(name: 'enabled');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        name,
        schedule,
        command,
        timeoutSeconds,
        enabled,
      ];
}
