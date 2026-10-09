import 'package:flutter/material.dart';

import '../../models/day_weather.dart';
import '../../theme/preview_theme.dart';
import '../timeline/weather_badge_placeholder.dart';

/// 天气徽章：`[emoji] 描述 高°/低° 风向风速`
///
/// 【WX-04】无数据 → **整块隐藏**（不留空白占位）。
/// 加载中 → 显示**固定尺寸占位**（防抖动）。
/// 【A-8】超 16 天窗口 → DayWeather 为 null → 隐藏，不用末日数据充数。
class WeatherBadge extends StatelessWidget {
  final DayWeather? weather;

  /// 是否正在拉取（true 时显示固定尺寸占位）
  final bool loading;

  const WeatherBadge({super.key, required this.weather, this.loading = false});

  static const double height = 22;

  @override
  Widget build(BuildContext context) {
    if (loading && weather == null) return const WeatherBadgePlaceholder();
    final w = weather;
    if (w == null) return const SizedBox.shrink();

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: PreviewColors.weatherBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PreviewColors.weatherBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(w.iconEmoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(w.desc, style: PreviewText.weather),
          const SizedBox(width: 4),
          Text(
            '${w.max.round()}°',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: PreviewColors.tempHigh,
            ),
          ),
          const Text('/', style: PreviewText.weatherWind),
          Text(
            '${w.min.round()}°',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: PreviewColors.tempLow,
            ),
          ),
          if (w.windText != null) ...[
            const SizedBox(width: 4),
            Text(w.windText!, style: PreviewText.weatherWind),
          ],
        ],
      ),
    );
  }
}
