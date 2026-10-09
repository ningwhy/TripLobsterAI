import '../models/trip_models.dart';

/// 存量行程日期校正（FX-04）纯函数：零 IO、零 UI 依赖，可单测。
///
/// 背景：FX-01 修复前（旧 `addDays` 在东八区少一天）生成的旧行程，`days[i].date` 已整体错一天。
/// 修复后不会自动更正 → 展示层按 `startDate + (dayNumber-1)` 校正；
/// **用户任一次编辑触发 `updateTrip` 时才写回**。
class DateFix {
  DateFix._();

  /// 是否需要校正：任一天的 date 与"startDate + (dayNumber-1)"不一致即需要。
  static bool needsFix(Trip trip) {
    if (trip.days.isEmpty) return false;
    for (final d in trip.days) {
      if (!_isSameDay(d.date, _expectedDate(trip.startDate, d.dayNumber))) return true;
    }
    return false;
  }

  /// 校正后的天列表（**新列表**，不改原对象；展示层使用，不写库）。
  ///
  /// 只改 date，其余字段（id/dayNumber/locations）保持原引用。
  static List<TripDay> corrected(Trip trip) {
    return trip.days.map((d) {
      final expected = _expectedDate(trip.startDate, d.dayNumber);
      if (_isSameDay(d.date, expected)) return d;
      return TripDay(
        id: d.id,
        date: expected,
        dayNumber: d.dayNumber,
        locations: d.locations,
      );
    }).toList();
  }

  /// 第 N 天应有的日期 = startDate + (N-1) 个**日历日**。
  ///
  /// 修（QA 编译/测试验证发现）：原实现用 `DateTime.utc(...)` 构造基准，
  /// 在东八区下 `DateTime.utc(2026,10,1)` 与本地 `DateTime(2026,10,1)` 是
  /// **两个不同的时刻**（相差 8h），`==` 判定为不等 →
  /// `corrected().first.date == trip.startDate` 恒不成立（PRD FX-04 验收①失败）。
  /// 现改为只做**日历日**推进：用 `DateTime(y, m, d + n)` 由构造函数归一化跨月/跨年，
  /// 既避开 Duration(24h×n) 在夏令时下把 00:00 推偏，也不改变时刻的本地语义。
  static DateTime _expectedDate(DateTime start, int dayNumber) {
    return DateTime(start.year, start.month, start.day + (dayNumber - 1));
  }

  /// 只比较年月日（忽略时分秒与时区）
  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 展示用：把本地 DateTime 按"年月日"归一（供日期条/分组头显示，避免时区抖动）
  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
