import 'package:flutter/material.dart';

import '../../theme/preview_theme.dart';
import '../../utils/cost_aggregator.dart';

/// 「当日已计价」（分组尾，右对齐）
///
/// 【M11】**不得叫「当日合计」** —— 只含餐饮+交通的数字叫"合计"，用户会当成完整花费，
/// 而酒店通常占 40~60%。改名「当日已计价」+ 常驻副行口径说明。
///
/// 【裁 1】显示**完整区间** `¥1,300–1,700`，**不取中值**（取中值即估算）。
/// 【PR-09】整日无可计价项 → `暂无可计价数据`，**不显示金额、不显示 `¥—`、绝不显示 `¥0`**。
/// ⚠️ 与**卡片级** `暂无参考价` 是两个不同文案，**不得混用**。
class DayCostBar extends StatelessWidget {
  final DayCost cost;

  const DayCostBar({super.key, required this.cost});

  @override
  Widget build(BuildContext context) {
    if (cost.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        alignment: Alignment.centerRight,
        child: Text(
          PreviewStrings.dayCostEmpty,
          style: PreviewText.costLabel,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      alignment: Alignment.centerRight,
      child: RichText(
        textAlign: TextAlign.right,
        text: TextSpan(
          children: [
            TextSpan(text: '${PreviewStrings.dayCostTitle} ', style: PreviewText.costLabel),
            TextSpan(text: cost.rangeText, style: PreviewText.costNum),
            if (cost.scopeText.isNotEmpty)
              TextSpan(text: '（${cost.scopeText}）', style: PreviewText.costLabel),
          ],
        ),
      ),
    );
  }
}
