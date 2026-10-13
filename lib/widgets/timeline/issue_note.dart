import 'package:flutter/material.dart';

import '../../theme/preview_theme.dart';
import '../../utils/itinerary_checker.dart';

/// 分级提示行（T04 唯一新增 widget）。
///
/// ## 边界
/// - **不含任何校验逻辑**：判据全在 `itinerary_checker.dart`，这里只把
///   `severity + 文案` 翻译成颜色与图标；
/// - **无动画、无阴影、无交互**：它是提示，不是可点按钮，避免产生"点了就能修"的假可供性；
/// - **一行主提示**：换行由 `Text` 自然折行，不做展开/收起（P0 不做完整清单）。
///
/// ## 三级语义
/// | 级别 | 视觉 | 含义 |
/// |---|---|---|
/// | blocking | 红字 + 红底（卡片**另**描红边） | 排不下 / 赶不上，必须改 |
/// | reminder | 橙字 + 灰底（**不描边**） | 需留意，不阻断 |
/// | neutral | 灰字 | 日级声明（CH-09），不上卡片 |
///
/// ⛔ 颜色**不得**复用价格徽章的红态：那是价格区的另一套语义（且本轮恒未启用），
/// 本组表示"行程排不下/赶不上"，两者来源不同，混用会让用户误读。
class IssueNote extends StatelessWidget {
  final IssueSeverity severity;

  /// 主提示文案（由 checker 生成，**已含可核对的时刻/分钟**）
  final String text;

  const IssueNote({
    super.key,
    required this.severity,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 12, color: _foreground),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              // 主句必须完整可见：时刻数字被截断就失去可核对性
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: _foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color get _foreground => switch (severity) {
        IssueSeverity.blocking => PreviewColors.issueBlockingText,
        IssueSeverity.reminder => PreviewColors.issueReminderText,
        IssueSeverity.neutral => PreviewColors.issueNeutralText,
      };

  Color get _background => switch (severity) {
        IssueSeverity.blocking => PreviewColors.issueBlockingBg,
        // reminder 用**灰底**：只有 blocking 才配红底，否则三级提示会糊成一片
        IssueSeverity.reminder => PreviewColors.issueReminderBg,
        IssueSeverity.neutral => Colors.transparent,
      };

  IconData get _icon => switch (severity) {
        IssueSeverity.blocking => Icons.error_outline_rounded,
        IssueSeverity.reminder => Icons.info_outline_rounded,
        IssueSeverity.neutral => Icons.info_outline_rounded,
      };
}
