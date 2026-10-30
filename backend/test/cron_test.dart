import 'package:gisila_panel/utils/cron.dart';
import 'package:test/test.dart';

DateTime _next(String expr, DateTime after) =>
    CronSchedule.parse(expr).next(after)!;

void main() {
  final t0 = DateTime.utc(2026, 10, 30, 13, 47, 22); // a Friday

  test('every minute and steps', () {
    expect(_next('* * * * *', t0), DateTime.utc(2026, 10, 30, 13, 48));
    expect(_next('*/15 * * * *', t0), DateTime.utc(2026, 10, 30, 14, 0));
    expect(_next('5-50/20 * * * *', t0), DateTime.utc(2026, 10, 30, 14, 5));
  });

  test('strictly after the given time', () {
    expect(_next('48 13 * * *', DateTime.utc(2026, 10, 30, 13, 48)),
        DateTime.utc(2026, 10, 31, 13, 48));
  });

  test('daily, lists and ranges roll over days, months and years', () {
    expect(_next('30 2 * * *', t0), DateTime.utc(2026, 10, 31, 2, 30));
    expect(_next('0 9,17 * * *', t0), DateTime.utc(2026, 10, 30, 17, 0));
    expect(_next('0 0 1 * *', t0), DateTime.utc(2026, 11, 1));
    expect(_next('0 0 1 jan *', t0), DateTime.utc(2027, 1, 1));
  });

  test('weekdays, names and Sunday as 0 or 7', () {
    expect(_next('0 9 * * mon-fri', t0), DateTime.utc(2026, 11, 2, 9));
    expect(_next('0 0 * * 0', t0), DateTime.utc(2026, 11, 1));
    expect(_next('0 0 * * 7', t0), DateTime.utc(2026, 11, 1));
    expect(_next('0 0 * * sun', t0), DateTime.utc(2026, 11, 1));
  });

  test('both day fields restricted: either matches', () {
    // The 1st of the month, or any Monday.
    expect(_next('0 0 1 * mon', t0), DateTime.utc(2026, 11, 1));
    expect(_next('0 0 1 * mon', DateTime.utc(2026, 11, 1, 1)),
        DateTime.utc(2026, 11, 2));
  });

  test('leap days', () {
    expect(_next('0 0 29 2 *', t0), DateTime.utc(2028, 2, 29));
  });

  test('shortcuts', () {
    expect(_next('@hourly', t0), DateTime.utc(2026, 10, 30, 14));
    expect(_next('@daily', t0), DateTime.utc(2026, 10, 31));
    expect(_next('@weekly', t0), DateTime.utc(2026, 11, 1));
    expect(_next('@monthly', t0), DateTime.utc(2026, 11, 1));
    expect(_next('@yearly', t0), DateTime.utc(2027, 1, 1));
  });

  test('upcoming lists the next runs', () {
    expect(CronSchedule.parse('0 */6 * * *').upcoming(t0, count: 3), [
      DateTime.utc(2026, 10, 30, 18),
      DateTime.utc(2026, 10, 31, 0),
      DateTime.utc(2026, 10, 31, 6),
    ]);
  });

  test('invalid schedules explain themselves', () {
    for (final bad in [
      '',
      '* * * *',
      '* * * * * *',
      '60 * * * *',
      '* 24 * * *',
      '* * 0 * *',
      '* * * 13 *',
      '* * * * 8',
      '*/0 * * * *',
      '5-1 * * * *',
      'a * * * *',
      '1,,2 * * * *',
      '@reboot',
      '0 0 30 2 *', // never
    ]) {
      expect(() => CronSchedule.parse(bad), throwsFormatException,
          reason: '"$bad"');
    }
  });
}
