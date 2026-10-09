import 'package:flutter/material.dart';

/// 天气徽章加载中的**固定尺寸占位**
///
/// 目的：异步天气到达时列表高度不跳动 → 分组偏移表不失效（设计 §9 竞态风险）。
/// 尺寸必须与 [WeatherBadge] 完全一致（高度 22、宽 64），故这里独立定义常量，
/// **不反向 import weather_badge.dart**（避免循环依赖）。
class WeatherBadgePlaceholder extends StatelessWidget {
  const WeatherBadgePlaceholder({super.key});

  /// 与 WeatherBadge.height 保持一致
  static const double height = 22;
  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: height,
      width: width,
      child: Center(
        child: SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.2),
        ),
      ),
    );
  }
}
