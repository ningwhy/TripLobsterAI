import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/utils/date_fix.dart';

void main() {
  Trip mkTrip(List<TripDay> days) => Trip(
        name: 't',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 3),
        days: days,
      );

  TripDay mkDay(int dayNumber, DateTime date, {List<Location>? locations}) => TripDay(
        date: date,
        dayNumber: dayNumber,
        locations: locations ?? const [],
      );

  group('DateFix 存量日期校正（FX-04）', () {
    test('① 正确的行程不需要校正', () {
      final trip = mkTrip([
        mkDay(1, DateTime(2026, 10, 1)),
        mkDay(2, DateTime(2026, 10, 2)),
        mkDay(3, DateTime(2026, 10, 3)),
      ]);
      expect(DateFix.needsFix(trip), isFalse);
      final fixed = DateFix.corrected(trip);
      expect(fixed[0].date, DateTime(2026, 10, 1));
      expect(fixed[2].date, DateTime(2026, 10, 3));
    });

    test('② 整体错一天（旧 addDays 东八区症状）被判定需要校正', () {
      final trip = mkTrip([
        mkDay(1, DateTime(2026, 9, 30)),
        mkDay(2, DateTime(2026, 10, 1)),
        mkDay(3, DateTime(2026, 10, 2)),
      ]);
      expect(DateFix.needsFix(trip), isTrue);
    });

    test('③ 校正后 Day1 == startDate（PRD FX-04 验收①）', () {
      final trip = mkTrip([
        mkDay(1, DateTime(2026, 9, 30)),
        mkDay(2, DateTime(2026, 10, 1)),
      ]);
      final fixed = DateFix.corrected(trip);
      expect(fixed.first.date, trip.startDate);
      expect(fixed[1].date, DateTime(2026, 10, 2));
    });

    test('④ 校正不破坏 dayNumber / locations', () {
      final loc = Location(name: 'A', address: '', type: LocationType.attraction);
      final trip = mkTrip([mkDay(1, DateTime(2026, 9, 30), locations: [loc])]);
      final fixed = DateFix.corrected(trip);
      expect(fixed.single.dayNumber, 1);
      expect(fixed.single.locations.single.name, 'A');
    });

    test('⑤ 按 dayNumber 校正（跳过缺失的天号也能算对）', () {
      final trip = mkTrip([
        mkDay(1, DateTime(2026, 9, 30)),
        mkDay(3, DateTime(2026, 10, 1)), // 原本就错了两天
      ]);
      final fixed = DateFix.corrected(trip);
      expect(fixed[0].date, DateTime(2026, 10, 1));
      expect(fixed[1].date, DateTime(2026, 10, 3));
    });

    test('⑥ 空行程不报错', () {
      final trip = mkTrip([]);
      expect(DateFix.needsFix(trip), isFalse);
      expect(DateFix.corrected(trip), isEmpty);
    });
  });
}
