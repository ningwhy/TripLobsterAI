import 'package:flutter/material.dart';

import '../../models/day_weather.dart';
import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';
import 'weather_badge.dart';

/// 分组头（锚点目标，key 挂在这一层）
///
/// 内容：`yyyy-MM-dd 星期X` + 地点数 + 路线摘要（`上一城→当日城 · 130km`，US-1；
/// 同城日/无跨城段隐藏）+ 右侧天气徽章位。
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

  /// 路线摘要：`上一城→当日城 · 130km`（US-1）
  ///
  /// 数据来源（**不新增字段**，全部用服务端已有值）：
  /// - 里程：当日 `transport.scope == intercity` 的 `distance` 之和（沿用旧口径）
  /// - 城市：跨城段的**上一站 `city`** → **到达站 `city`**。
  ///   服务端 `multiCity.js:567-590` 把出发枢纽(`city: fromName`)与到达枢纽
  ///   (`city: city.name`) 拆成**相邻两个 location**，到达枢纽那条挂 `scope:'intercity'`，
  ///   所以"上一条有 city 的 location"就是出发城，无需服务端配合。
  ///
  /// ⛔ 同城日 / 无跨城段 → 返回 null（隐藏）。里程为 0（估算分支无 distance）时
  /// 只显示城市、不显示 `· 0km` —— 那等于承认我们知道距离是 0，而实际是"不知道"。
  static String? _routeText(TripDay day) {
    double km = 0;
    var found = false;
    String? fromCity;
    String? toCity;

    for (final l in day.locations) {
      final t = l.transport;
      if (t == null || t.scope != TransportScope.intercity) continue;
      found = true;
      if (t.distance != null && t.distance! > 0) {
        km += t.distance! / 1000;
      }
      // 到达站 = 本条（跨城段的终点）；出发站 = 前面最近的一条有 city 的 location
      toCity ??= _clean(l.city);
      fromCity ??= _previousCity(day, l);
    }
    if (!found) return null;

    final cities = (fromCity != null && toCity != null && fromCity != toCity)
        ? '$fromCity→$toCity'
        : (toCity ?? fromCity);
    if (cities == null || cities.isEmpty) {
      // 两个城市名都取不到 → 只退回旧口径（有里程才显示）
      return km > 0 ? '跨城 ${km.toStringAsFixed(0)}km' : null;
    }
    return km > 0 ? '$cities · ${km.toStringAsFixed(0)}km' : cities;
  }

  /// 取 [loc] 之前最近的一个有城市名的 location（= 出发城）
  static String? _previousCity(TripDay day, Location loc) {
    for (var i = day.locations.indexOf(loc) - 1; i >= 0; i--) {
      final c = _clean(day.locations[i].city);
      if (c != null) return c;
    }
    return null;
  }

  /// 去掉高德返回的行政区后缀（`北京市` → `北京`），空值归 null
  static String? _clean(String? city) {
    final c = (city ?? '').trim();
    if (c.isEmpty) return null;
    return c.replaceFirst(RegExp(r'(市|地区|自治州)$'), '');
  }
}
