import 'package:flutter/material.dart';

import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';
import '../../utils/cost_aggregator.dart';

/// 日期条（常驻）：N ≤ 7 等分；N > 7 横滚（格宽 44dp）+ 选中格自动居中
///
/// 每格 = 序号（20sp）+ 当日费用（9.5sp，**取下限 `≥¥1,300`**；无数据显示 `—`，绝不 `¥0`）。
/// 末日含 `home` 类型 → 🏠。
class DayStrip extends StatelessWidget {
  final List<TripDay> days;
  final int activeIndex;

  /// 每天的费用下限文本（由页面用 CostAggregator 现算后传入，widget 不做业务计算）
  final List<String> costTexts;

  /// 每天是否含 home 类型（末日回家标识）
  final List<bool> hasHome;

  final ValueChanged<int> onTap;

  /// 横滚控制器（N>7 时使用；N<=7 传 null）
  final ScrollController? scrollController;

  const DayStrip({
    super.key,
    required this.days,
    required this.activeIndex,
    required this.costTexts,
    required this.hasHome,
    required this.onTap,
    this.scrollController,
  });

  static const double cellWidth = 44;
  static const double cellHeight = 52;

  @override
  Widget build(BuildContext context) {
    final n = days.length;
    if (n <= 7) {
      return SizedBox(
        height: cellHeight,
        child: Row(
          children: List<Widget>.generate(n, (i) => Expanded(child: _cell(i))),
        ),
      );
    }
    return SizedBox(
      height: cellHeight,
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: n,
        itemBuilder: (_, i) => SizedBox(width: cellWidth, child: _cell(i)),
      ),
    );
  }

  Widget _cell(int i) {
    final selected = i == activeIndex;
    final d = days[i];
    final cost = i < costTexts.length ? costTexts[i] : CostAggregator.lowerBoundText(0);
    final home = i < hasHome.length ? hasHome[i] : false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: selected ? PreviewColors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${d.dayNumber}',
                  style: PreviewText.dayNum.copyWith(
                    color: selected ? Colors.white : PreviewColors.ink,
                  ),
                ),
                if (home) ...[
                  const SizedBox(width: 2),
                  const Text('🏠', style: TextStyle(fontSize: 9)),
                ],
              ],
            ),
            const SizedBox(height: 1),
            Text(
              cost,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PreviewText.dayNumSub.copyWith(
                color: selected ? Colors.white.withValues(alpha: 0.9) : PreviewColors.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
