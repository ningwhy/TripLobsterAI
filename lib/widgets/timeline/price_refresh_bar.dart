import 'package:flutter/material.dart';

import '../../theme/preview_theme.dart';

/// 刷新参考价条（常驻）：按钮 + 状态行（⏳ / ✅ / ❌）
///
/// 【M7】文案写「🔄 刷新参考价」，**不得**出现「实时价/实时房价/可订状态」。
/// 失败时**不清空已有徽章**（沿用上次参考价）。
class PriceRefreshBar extends StatelessWidget {
  final bool loading;

  /// 【A-15】是否有**任何**地点需要联网取价。
  ///
  /// ⛔ **必须由数据源驱动，不得硬编码 `false`**：本轮 `requestKindFor()` 恒 null
  /// → 恒 false → 按钮置灰；SR-03 / OTA 接入后只改 `requestKindFor` 一处，
  /// 本值自动翻 true、按钮自动亮起，无需改 UI。
  /// 硬编码会让将来接入时"按钮点了没反应"且**无任何报错**。
  final bool enabled;

  final String status;
  final VoidCallback onRefresh;

  const PriceRefreshBar({
    super.key,
    required this.loading,
    required this.enabled,
    required this.status,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // 【PRD §6.3】禁用态点击 → 给出原因，而不是让用户对着一个灰按钮瞎点。
    //
    // `TextButton.onPressed == null` 时 Flutter **吞掉点击**（这是 A-15 刻意要的
    // "不产生假可供性"），但代价是**零反馈**——用户无法判断是坏了还是没内容。
    // 这里在外层补一层 `GestureDetector`：只在"因无数据源而置灰"时接管点击并弹说明。
    //
    // ⛔ 三个边界，缺一不可：
    //   1. **只在 `!enabled` 时接管** —— `enabled == true` 时 `onTap` 为 null，
    //      不参与手势竞技，按钮的点击完全不受影响；
    //   2. **`loading` 时不弹** —— 刷新中按钮也是灰的，但那时弹"暂无参考价源"
    //      是错的（用户正在刷新，却告诉他没有源），状态行已在显示进度；
    //   3. **不改 `enabled` 的来源** —— 置灰仍由 `supports && needsNetwork` 决定。
    final explainDisabled = !enabled && !loading;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: explainDisabled
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(PreviewStrings.priceOfflineNote),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          : null,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(
          children: [
            Opacity(
              // 【A-15】无项可刷时按钮整体淡出（与 loading 态同一视觉语言），
              // 且 `onPressed` 为 null → Flutter 自动置灰并吞掉点击事件，
              // 不产生"可点击但无反应"的假可供性。
              opacity: (loading || !enabled) ? 0.45 : 1,
              child: TextButton.icon(
                // ⛔ `enabled` 仍由页面用 `supports(l) && needsNetwork(l)` 驱动。
                //    本次只加"点了给解释"，**不改该不该灰**（D-AR-02）：
                //    灰是数据源决定的，解释是交互补齐的，两件事。
                onPressed: (loading || !enabled) ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text(PreviewStrings.refreshPrice),
                style: TextButton.styleFrom(
                  foregroundColor: PreviewColors.green2,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const Spacer(),
            if (status.isNotEmpty)
              Flexible(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PreviewText.statusLine,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
