/// Standard 5-field cron schedules (`minute hour day-of-month month
/// day-of-week`), evaluated in UTC.
///
/// Supports `*`, numbers, ranges `a-b`, steps `*/n` and `a-b/n`, lists
/// `a,b,c`, month and weekday names (`jan`, `mon`; Sunday is 0 or 7), and
/// the shortcuts `@yearly` / `@annually`, `@monthly`, `@weekly`, `@daily`
/// / `@midnight` and `@hourly`. As in classic cron, when both day fields
/// are restricted a day matches if either does.
class CronSchedule {
  CronSchedule._(this.expression, this._minutes, this._hours, this._days,
      this._months, this._weekdays, this._daysRestricted,
      this._weekdaysRestricted);

  /// Parses [expression]. Throws [FormatException] with a message fit to
  /// show a user, including for schedules that can never fire (`0 0 30 2 *`).
  factory CronSchedule.parse(String expression) {
    final expr = expression.trim().toLowerCase();
    final expanded = _shortcuts[expr] ?? expr;
    if (expanded.startsWith('@')) {
      throw FormatException('Unknown shortcut "$expression".');
    }
    final fields = expanded.split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw FormatException('A schedule has 5 fields (minute hour '
          'day-of-month month day-of-week), "$expression" has '
          '${fields.length}.');
    }
    final schedule = CronSchedule._(
      expression.trim(),
      _field(fields[0], 0, 59, 'minute'),
      _field(fields[1], 0, 23, 'hour'),
      _field(fields[2], 1, 31, 'day of month'),
      _field(fields[3], 1, 12, 'month', names: _monthNames),
      _field(fields[4], 0, 7, 'day of week', names: _dayNames)
          .map((d) => d % 7)
          .toSet(),
      !fields[2].startsWith('*'),
      !fields[4].startsWith('*'),
    );
    if (schedule.next(DateTime.utc(2000)) == null) {
      throw FormatException('"$expression" never runs.');
    }
    return schedule;
  }

  final String expression;
  final Set<int> _minutes;
  final Set<int> _hours;
  final Set<int> _days;
  final Set<int> _months;
  final Set<int> _weekdays; // 0 = Sunday
  final bool _daysRestricted;
  final bool _weekdaysRestricted;

  /// The first time strictly after [after] (in UTC, to the minute) the
  /// schedule fires, or null if there is none within eight years.
  DateTime? next(DateTime after) {
    final start = after.toUtc();
    var t = DateTime.utc(start.year, start.month, start.day, start.hour,
        start.minute + 1);
    final limit = DateTime.utc(start.year + 8, start.month, start.day);
    while (t.isBefore(limit)) {
      if (!_months.contains(t.month)) {
        t = DateTime.utc(t.year, t.month + 1);
        continue;
      }
      if (!_dayMatches(t)) {
        t = DateTime.utc(t.year, t.month, t.day + 1);
        continue;
      }
      if (!_hours.contains(t.hour)) {
        t = DateTime.utc(t.year, t.month, t.day, t.hour + 1);
        continue;
      }
      if (!_minutes.contains(t.minute)) {
        t = DateTime.utc(t.year, t.month, t.day, t.hour, t.minute + 1);
        continue;
      }
      return t;
    }
    return null;
  }

  /// The next [count] times after [after].
  List<DateTime> upcoming(DateTime after, {int count = 5}) {
    final out = <DateTime>[];
    var t = after;
    while (out.length < count) {
      final n = next(t);
      if (n == null) break;
      out.add(n);
      t = n;
    }
    return out;
  }

  bool _dayMatches(DateTime t) {
    final dom = _days.contains(t.day);
    final dow = _weekdays.contains(t.weekday % 7);
    if (_daysRestricted && _weekdaysRestricted) return dom || dow;
    if (_daysRestricted) return dom;
    if (_weekdaysRestricted) return dow;
    return true;
  }

  static const _shortcuts = {
    '@yearly': '0 0 1 1 *',
    '@annually': '0 0 1 1 *',
    '@monthly': '0 0 1 * *',
    '@weekly': '0 0 * * 0',
    '@daily': '0 0 * * *',
    '@midnight': '0 0 * * *',
    '@hourly': '0 * * * *',
  };

  static const _monthNames = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const _dayNames = {
    'sun': 0, 'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6,
  };

  static Set<int> _field(String field, int min, int max, String name,
      {Map<String, int> names = const {}}) {
    int value(String s) {
      final v = names[s] ?? int.tryParse(s);
      if (v == null || v < min || v > max) {
        throw FormatException('Invalid $name "$s" (allowed $min-$max).');
      }
      return v;
    }

    final out = <int>{};
    for (final part in field.split(',')) {
      if (part.isEmpty) throw FormatException('Empty value in the $name field.');
      final slash = part.split('/');
      if (slash.length > 2) throw FormatException('Invalid $name "$part".');
      var step = 1;
      if (slash.length == 2) {
        final s = int.tryParse(slash[1]);
        if (s == null || s < 1) {
          throw FormatException('Invalid step "${slash[1]}" in the $name field.');
        }
        step = s;
      }
      final range = slash[0];
      int lo;
      int hi;
      if (range == '*') {
        lo = min;
        hi = max;
      } else if (range.contains('-')) {
        final ends = range.split('-');
        if (ends.length != 2) throw FormatException('Invalid $name "$part".');
        lo = value(ends[0]);
        hi = value(ends[1]);
        if (lo > hi) {
          throw FormatException('Range "$range" runs backwards in the $name field.');
        }
      } else {
        lo = value(range);
        hi = slash.length == 2 ? max : lo;
      }
      for (var v = lo; v <= hi; v += step) {
        out.add(v);
      }
    }
    return out;
  }
}
