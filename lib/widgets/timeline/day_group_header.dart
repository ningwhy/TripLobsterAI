import 'package:flutter/material.dart';

import '../../models/day_weather.dart';
import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';
import 'weather_badge.dart';

/// 分组头（锚点目标，key 挂在这一层）
///
/// 内容：`yyyy-MM-dd 星期X` + 路线摘要（取当日 `transport.scope == intercity` 的 distance，
/// 无跨城段则隐藏里程）+ 右侧天气徽章位。
class DayGroupHeader extends StatelessWidget {
  final TripDay day;
  final DayWeather? weather;
  final bool weatherLoading;

  const DayGroupHeader({
    super.key,
    required this.day,
    this.weather,
    this.weatherLoading = false,
  });

  static const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

  @override
  Widget build(BuildContext context) {
    final d = day.date;
    final dateText =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final route = _routeText(day);

    return Container(
      color: PreviewColors.dateBarBg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Text(
            '$dateText ${_weekdays[d.weekday - 1]}',
            style: PreviewText.groupHeader,
          ),
          // 【TL-10 回归】旧版日期条下有「N个地点」一行，重写时掉了，此处补回。
          // 与跨城里程分开显示：地点数看行程密度，里程看跨城跨度，是两回事。
          if (day.locations.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              '${day.locations.length}个地点',
              style: PreviewText.groupMeta,
            ),
          ],
          if (route != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                route,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PreviewText.groupMeta,
              ),
            ),
          ],
          const Spacer(),
          WeatherBadge(weather: weather, loading: weatherLoading),
        ],
      ),
    );
  }

  /// 路线摘要：当日跨城段的里程（无跨城段 → null，隐藏里程）
  static String? _routeText(TripDay day) {
    double km = 0;
    var found = false;
    for (final l in day.locations) {
      final t = l.transport;
      if (t == null) continue;
      if (t.scope != TransportScope.intercity) continue;
      if (t.distance != null && t.distance! > 0) {
        km += t.distance! / 1000;
        found = true;
      }
    }
    if (!found) return null;
    return '跨城 ${km.toStringAsFixed(0)}km';
  }
}
