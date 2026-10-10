import 'package:flutter/material.dart';

import '../../theme/preview_theme.dart';

/// 刷新参考价条：按钮 + 状态行（⏳ / ✅ / ❌）
///
/// 【M7】文案写「🔄 刷新参考价」，**不得**出现「实时价/实时房价/可订状态」。
/// 失败时**不清空已有徽章**（沿用上次参考价）。
///
/// ⚠️ **2026-10-10 修订（外部评审 P0-4）：无数据源时不再渲染按钮**
///
/// 原实现无论有无数据源都渲染按钮，靠 `Opacity(0.45)` + 置灰表达"不可用"。
/// 评审指出：**一个长期不能完成其表面承诺的操作入口，只会持续制造误解。**
/// 本轮 `requestKindFor()` 恒 null → 按钮**永久**置灰，属于典型的"假可供性"。
///
/// 修订后按 `enabled` 二选一：
/// - `enabled == false`（当前实际状态）→ **整条退化为一行静态口径说明**，
///   不再有按钮；用户看到的是"价格从哪来"，而不是一个点了没用的按钮。
/// - `enabled == true`（SR-03 / OTA 接入后）→ 恢复按钮 + 状态行。
///
/// ⛔ 保留自动亮起能力：`enabled` 仍由页面 `supports(l) && needsNetwork(l)` 驱动，
/// **不得硬编码 false**。OTA 接入后只改 `requestKindFor` 一处，按钮自动出现。
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
    // 【P0-4】无数据源 → 不渲染按钮，整条退化为静态口径说明。
    //
    // 这里**不再**用置灰按钮 + 点击弹提示的旧方案：那个方案仍保留了一个
    // "看起来能点"的控件形态，认知负担没真正消除。直接不渲染是最干净的。
    //
    // 说明文字本身承担原 snackbar 的信息量（价格从哪来 + 什么没源），
    // 用户无需点击即可获得，比"点了才知道为什么不能点"更省一步。
    if (!enabled) {
      return const SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.white),
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Text(
              PreviewStrings.priceOfflineNote,
              style: PreviewText.statusLine,
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: [
          Opacity(
            // 刷新中整体淡出（与 loading 态同一视觉语言）。
            // 此处 `enabled` 已为 true，`loading` 是唯一的临时禁用原因，
            // 属**短暂**状态而非"永久不可用"，保留置灰是合理的。
            opacity: loading ? 0.45 : 1,
            child: TextButton.icon(
              // ⛔ `onPressed` 仅由 `loading` 控制；`enabled` 已在上方分流，
              //    此处恒为 true，不会再造出一个永久置灰的按钮。
              onPressed: loading ? null : onRefresh,
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
