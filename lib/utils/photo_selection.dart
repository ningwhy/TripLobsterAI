import '../models/photo_entry.dart';

/// 切换单个照片的选中态，返回**新集合**（不修改入参）。
///
/// 两次切换同一个 id 会回到原集合（幂等）；Set 天然去重，重复 id 不会累加。
Set<String> toggle(Set<String> selected, String id) {
  final Set<String> next = Set<String>.from(selected);
  final bool added = next.add(id);
  if (!added) {
    next.remove(id);
  }
  return next;
}

/// 按真实拍摄时间的「年月日」分组，日期降序。
///
/// * 日期键只取 [PhotoEntry.createdAt] 的年月日，绝不按臆测的行程地点分组。
/// * 同一天内保持输入顺序（不臆造排序）。
/// * 重复的 assetId 只保留第一次出现，避免同一张照片被渲染两次。
/// * 空输入返回空 Map（UI 据此显示「没有照片」空态）。
Map<DateTime, List<PhotoEntry>> groupByDay(List<PhotoEntry> entries) {
  final Map<DateTime, List<PhotoEntry>> buckets = <DateTime, List<PhotoEntry>>{};
  final Set<String> seen = <String>{};
  for (final PhotoEntry entry in entries) {
    if (!seen.add(entry.assetId)) {
      continue;
    }
    final DateTime key = entry.dayKey;
    buckets.putIfAbsent(key, () => <PhotoEntry>[]).add(entry);
  }
  final List<DateTime> days = buckets.keys.toList()
    ..sort((DateTime a, DateTime b) => b.compareTo(a));
  return <DateTime, List<PhotoEntry>>{
    for (final DateTime day in days)
      day: List<PhotoEntry>.unmodifiable(buckets[day]!),
  };
}

/// 已选计数的诚实文案：0（或异常负值）明确说「未选择照片」。
String countLabel(int n) => n <= 0 ? '未选择照片' : '已选 $n 张';

/// 归档计数文案，数字来自真实持久化的 id 列表长度。
String archiveLabel(int n) => '已归档 $n 张';

/// 尺寸文案：设备没给宽高时返回空串，UI 不留「未知」占位 chip。
String dimensionLabel(int width, int height) =>
    width > 0 && height > 0 ? '$width×$height' : '';

/// 经纬度文案：只有两个值都真实存在才输出，否则空串。
String locationLabel(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) {
    return '';
  }
  return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// 日期文案 `yyyy-MM-dd`，只由真实 [DateTime] 的年/月/日组成。
String formatDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_twoDigits(d.month)}-${_twoDigits(d.day)}';

/// 日期时间文案 `yyyy-MM-dd HH:mm`，只由真实 [DateTime] 组成。
String formatDateTime(DateTime d) =>
    '${formatDay(d)} ${_twoDigits(d.hour)}:${_twoDigits(d.minute)}';
