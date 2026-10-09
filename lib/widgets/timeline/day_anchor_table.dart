import 'package:flutter/material.dart';

import '../../utils/day_anchor.dart';

/// 分组锚点表：负责"测量 + 缓存偏移 + 程序化滚动抑制"
///
/// 判定逻辑全部委托给纯函数 [DayAnchor.activeIndexFor]（无 Flutter 依赖，可单测）。
///
/// 防抖三要点（PRD §6.1/§6.2）：
/// 1. 滚动回调里**仅在索引变化时** setState（由页面判断）；
/// 2. 点击日期条 → 立即 setState，再 animateTo；
/// 3. 程序化滚动期间置 `isProgrammatic = true`，spy 跳过更新，动画结束复位。
class DayAnchorTable {
  DayAnchorTable({required this.dayCount})
      : keys = List<GlobalKey>.generate(dayCount, (_) => GlobalKey());

  /// 每天一个 GlobalKey（挂在分组头上）
  final List<GlobalKey> keys;

  /// 天数
  final int dayCount;

  /// 各分组头相对"列表内容顶部"的偏移（未测量为 null）
  final List<double?> offsets = <double?>[];

  /// 程序化滚动中（抑制 spy）
  bool isProgrammatic = false;

  bool _dirty = true;

  /// 置脏：内容变化（天气/价格到达改变高度）后调用，下一帧统一重测
  void markDirty() {
    _dirty = true;
  }

  bool get isDirty => _dirty;

  /// 测量：必须在帧后调用（addPostFrameCallback）
  ///
  /// [listTop] 为 ListView 内容顶部在屏幕上的 y。
  void measure(RenderBox listBox, ScrollPosition position) {
    if (offsets.length != dayCount) {
      offsets.clear();
      offsets.addAll(List<double?>.filled(dayCount, null));
    }
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    for (var i = 0; i < dayCount; i++) {
      final ctx = keys[i].currentContext;
      if (ctx == null) continue; // 未布局 → 下一帧再测
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      offsets[i] = box.localToGlobal(Offset.zero).dy - listTop + position.pixels;
    }
    _dirty = false;
  }

  /// 第 i 天的偏移（未测量返回 null）
  double? offsetOf(int i) {
    if (i < 0 || i >= offsets.length) return null;
    return offsets[i];
  }

  /// 当前滚动位置对应的天下标
  int activeIndex(double pixels, {double epsilon = 4}) {
    final known = offsets.whereType<double>().toList();
    if (known.length != dayCount) return 0; // 尚未测全 → 不抢高亮
    return DayAnchor.activeIndexFor(known, pixels + epsilon);
  }

  /// 点选第 i 天时的目标滚动位置（未测量返回 null，由页面下一帧重试）
  double? targetFor(int i, {double epsilon = 4}) {
    final o = offsetOf(i);
    if (o == null) return null;
    return DayAnchor.targetOffset(o, epsilon: epsilon);
  }
}
