/// 滚动锚点纯计算（**零 Flutter 依赖**，便于无工具链时单测）
///
/// 抽出来的原因：widget 文件必然 `import 'package:flutter/material.dart'`，
/// 一旦引入就无法在本项目的纯 Dart 环境下跑单测；把"判定"与"测量"分离后，
/// 判定逻辑（最容易写错的部分）可独立验证。
class DayAnchor {
  DayAnchor._();

  /// 判定当前滚动位置属于第几天。
  ///
  /// [offsets] 为各分组头相对列表内容顶部的偏移（升序）；
  /// [y] 为列表视口顶部对应的内容坐标（`pixels + 判定补偿量`）。
  ///
  /// 规则：取"最后一个 offset <= y"的下标；没有任何 offset <= y 时取 0。
  static int activeIndexFor(List<double> offsets, double y) {
    if (offsets.isEmpty) return 0;
    var idx = 0;
    for (var i = 0; i < offsets.length; i++) {
      if (offsets[i] <= y) idx = i;
    }
    return idx;
  }

  /// 目标滚动位置：偏移减去补偿量，且不为负
  static double targetOffset(double offset, {double epsilon = 4}) {
    final v = offset - epsilon;
    return v < 0 ? 0 : v;
  }

  /// 把"选中格居中"所需的横向滚动位置（>7 天横滚模式用）
  ///
  /// [cellWidth] 单格宽，[viewportWidth] 视口宽，[index] 选中下标，[count] 总格数。
  static double centeredScrollOffset({
    required int index,
    required int count,
    required double cellWidth,
    required double viewportWidth,
    required double maxScroll,
  }) {
    final target = index * cellWidth - (viewportWidth - cellWidth) / 2;
    if (target < 0) return 0;
    if (target > maxScroll) return maxScroll;
    return target;
  }
}
