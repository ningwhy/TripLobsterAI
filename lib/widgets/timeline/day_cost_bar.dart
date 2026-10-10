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
    // 【常驻副行】口径说明必须是**独立一行**、且**有数据与空态两种情形下都显示**。
    //
    // 旧实现在空态分支（`cost.isEmpty`）直接 return，只剩一句 `暂无可计价数据`，
    // `scopeText` **整块丢失** —— 恰恰是"这天一分钱都没算出来"的时候最需要告诉用户
    // 「为什么没有 / 缺的是什么」，却什么都不说。这是诚实性的承载点，不能省。
    //
    // 也从括号里挪出来：括号内跟在金额后会被金额的视觉权重压住、且窄屏下换行错位，
    // 独立一行才能稳定可读。
    final scope = cost.scopeText;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 金额行：空态只出文案、**不出金额**（不显示 ¥0、不显示 ¥—）
          cost.isEmpty
              ? Text(
                  PreviewStrings.dayCostEmpty,
                  textAlign: TextAlign.right,
                  style: PreviewText.costLabel,
                )
              : RichText(
                  textAlign: TextAlign.right,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${PreviewStrings.dayCostTitle} ',
                        style: PreviewText.costLabel,
                      ),
                      TextSpan(text: cost.rangeText, style: PreviewText.costNum),
                    ],
                  ),
                ),
          // 口径副行：**两种情形都必须可见**
          if (scope.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              scope,
              textAlign: TextAlign.right,
              style: PreviewText.costLabel,
            ),
          ],
        ],
      ),
    );
  }
}
