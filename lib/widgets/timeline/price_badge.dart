import 'package:flutter/material.dart';

import '../../models/price_quote.dart';
import '../../theme/preview_theme.dart';

/// 价格徽章（**二态**，【裁 P-3】红态本轮不实现）
///
/// 1. 绿：`💰 参考价 ¥300–500 · 截至 HH:mm`
/// 2. 灰：`暂无参考价`（含「未匹配到 POI」—— 归入同一分支，不单独造态）
/// 3. 未刷新（`quote == null`）→ **整块不渲染**（宁可隐藏，不可编造 —— 三铁律 1）
///
/// 【裁 P-3】"价格待核实"红态的前提是"有价格但待核实"，探针实测**酒店 0/20 全空**，
/// 该前提不存在 → 本轮不实现红态，改灰字 `暂无参考价`。
///
/// 【PR-10 ①】widget 层**零数据源语义**：本文件不出现 `amap` / `高德` / `参考价` 字面量，
/// 文案一律引用 `PreviewStrings` 常量（将来切 OTA 只改常量值，本文件不动）。
/// 【M7】全页不得出现「实时价 / 实时房价 / 可订状态 / 售罄 / 不可订 / 待核实」。
class PriceBadge extends StatelessWidget {
  /// 运行时价格缓存（null = 还没刷过 → 不渲染）
  final PriceQuote? quote;

  final VoidCallback? onTap;

  const PriceBadge({super.key, this.quote, this.onTap});

  @override
  Widget build(BuildContext context) {
    final q = quote;
    if (q == null) return const SizedBox.shrink();

    if (q.hasReference) {
      final r = q.reference!;
      return _box(
        PreviewStrings.priceBadgeText(r.text, timeSuffix: q.fetchedAtText),
        PreviewText.badge,
        PreviewColors.priceGreenBg,
        PreviewColors.priceGreenBorder,
      );
    }
    // 无参考价：无论"有候选但没价"还是"未匹配到 POI"，都归入灰字分支
    return _box(
      PreviewStrings.priceAbsent,
      PreviewText.badgeGray,
      PreviewColors.priceGrayBg,
      PreviewColors.priceGrayBorder,
    );
  }

  Widget _box(String text, TextStyle style, Color bg, Color border) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border, width: 1),
        ),
        child: Text(text, style: style),
      ),
    );
  }
}
