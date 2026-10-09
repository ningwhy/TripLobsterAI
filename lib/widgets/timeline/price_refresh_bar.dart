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
    return Container(
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
    );
  }
}
