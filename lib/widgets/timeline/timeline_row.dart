import 'package:flutter/material.dart';

import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';

/// 时间线的一行：时间列(48) + 圆点列(26) + 卡片区
///
/// 圆点中心 = 48 + 13 = **61 ≈ 60**，与参考页 `.tl::before{left:60px}` 对齐。
/// 圆点 10×10，白填充 + 2.5px 语义描边。
class TimelineRow extends StatelessWidget {
  /// 左侧时间文本（无时刻留空）
  final String? timeText;

  /// 圆点语义色
  final Color dotColor;

  /// 卡片区
  final Widget child;

  const TimelineRow({
    super.key,
    this.timeText,
    required this.dotColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, right: 7),
            child: Text(
              timeText ?? '',
              textAlign: TextAlign.right,
              style: PreviewText.timeCol,
            ),
          ),
        ),
        SizedBox(
          width: 26,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: PreviewColors.cardBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: dotColor, width: 2.5),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// 圆点语义色：景点蓝 / 出发到家绿 / 酒店橙 / 交通灰蓝
  static Color dotColorOf(Location loc, {required bool isTripStart}) {
    if (isTripStart || loc.type == LocationType.home) return PreviewColors.green;
    switch (loc.type) {
      case LocationType.hotel:
        return PreviewColors.orange;
      case LocationType.transport:
        return const Color(0xFF8FA3AD); // 灰蓝
      case LocationType.attraction:
      case LocationType.restaurant:
      case LocationType.shopping:
      case LocationType.other:
        return PreviewColors.blue;
      case LocationType.home:
        // 上面的早退已覆盖；此处补分支仅为满足枚举穷尽（analyzer 硬性要求）
        return PreviewColors.green;
    }
  }
}

/// 一整天的"天块"：用 Stack 贯通轴线（**不用**每行画一段线）
///
/// 轴线：left 60 / width 2 / top 0 / bottom 16（末项不画到卡片底部以下）。
/// 不用 IntrinsicHeight + Expanded 逐行画线 —— 那样卡片高度变化会触发整块重排。
class TimelineBlock extends StatelessWidget {
  final List<Widget> rows;

  const TimelineBlock({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        const Positioned(
          left: 60,
          top: 0,
          bottom: 16,
          width: 2,
          child: ColoredBox(color: PreviewColors.line2),
        ),
        Column(children: rows),
      ],
    );
  }
}
