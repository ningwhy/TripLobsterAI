import 'package:flutter/material.dart';

import '../../models/price_quote.dart';
import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';
import '../../utils/ota_deeplink.dart';
import 'price_badge.dart';

/// 地点卡（四层信息）
///
/// ① 图标 26px 圆底 + 名称 14sp/600 单行省略 + chip / 「修改」
/// ② meta 11.5sp（停留·营业时间·⚠️ 冲突）
/// ③ 价格徽章（**仅当 `showPrice == true` 才渲染** —— 酒店/景点无数据源 → 不渲染）
/// ④ 操作区（OTA 深链 · 换一家 · 调整停留 · 移除）
///
/// 【PRD §5.7 chip 规则】餐饮人均价 / 交通里程 / `estimated==true` → 灰 chip「估算」
/// 【M6b】**不显示过路费**（属估算，客户端不实现）
/// 【PRD §8】营业时间冲突 → **卡片描边红框**；价格红态本轮不实现（【裁 P-3】）。
/// 【PR-08】酒店 / 景点无参考价 → **深链即价格功能的主要交付形态**（`🏨 去携程看价格 ↗`）。
class LocationCard extends StatelessWidget {
  final Location location;

  /// 到达/离开时刻文本（服务端 arrivalTime 优先，空则页面推算后传入）
  final String? arrivalText;
  final String? leaveText;

  /// 运行时价格缓存
  final PriceQuote? quote;

  /// 该地点是否属于**当前数据源支持**的类型（由页面传 `PriceSource.supports(loc)`）
  ///
  /// false → 不渲染徽章（酒店 / 景点本轮无数据源，渲染出来必然是"暂无参考价"，是噪音）。
  final bool showPrice;

  /// 营业时间冲突（到达+停留 超出 closeTime）
  final bool conflict;

  final VoidCallback onTap;
  final VoidCallback onOta;
  final VoidCallback onEditStay;
  final VoidCallback onRemove;
  final VoidCallback? onSwitchHotel;

  const LocationCard({
    super.key,
    required this.location,
    this.arrivalText,
    this.leaveText,
    this.quote,
    this.showPrice = true,
    this.conflict = false,
    required this.onTap,
    required this.onOta,
    required this.onEditStay,
    required this.onRemove,
    this.onSwitchHotel,
  });

  @override
  Widget build(BuildContext context) {
    final loc = location;
    final chip = chipText(loc);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 12, 0),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: PreviewColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: conflict
              ? Border.all(color: PreviewColors.conflictBorder, width: 1.5)
              : Border.all(color: PreviewColors.line, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ① 图标 + 名称 + chip
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _iconBg(loc.type),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_icon(loc.type), size: 15, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PreviewText.cardName,
                  ),
                ),
                if (chip != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: PreviewColors.pageBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(chip, style: PreviewText.chip),
                  ),
                ],
                if (loc.fixed) ...[
                  const SizedBox(width: 4),
                  const Text('📌', style: TextStyle(fontSize: 10)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            // ② meta
            Text(
              _metaText(loc),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PreviewText.cardMeta,
            ),
            // ③ 价格徽章（不支持的类型整块跳过，不占高度）
            if (showPrice) ...[
              const SizedBox(height: 6),
              PriceBadge(quote: quote),
            ],
            const SizedBox(height: 6),
            // ④ 操作区（酒店/景点无价 → 深链即价格入口，PR-08）
            Wrap(
              spacing: 8,
              children: [
                _action(OtaDeepLink.buttonText(OtaDeepLink.purposeOf(loc)), onOta),
                _action('调整停留', onEditStay),
                if (onSwitchHotel != null) _action('换一家', onSwitchHotel!),
                _action('移除', onRemove, color: PreviewColors.sub),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(String text, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color ?? PreviewColors.teal,
        ),
      ),
    );
  }

  // ---------------- 文案 ----------------

  /// chip 文案（PRD §5.7）
  ///
  /// 【FX-06a】酒店 / 景点 `biz_ext.cost` 探针实测 **0/20 全空** → chip 恒为 null，
  /// 不留任何占位（占位等于编造）。价格功能在这两类上走**深链**（PR-08），不走 chip。
  static String? chipText(Location loc) {
    final t = loc.transport;
    if (t != null && t.estimated == true) return '估算';
    switch (loc.type) {
      case LocationType.restaurant:
        // 餐饮：人均价（探针实测 18/20 有值）。
        // SR-02 后服务端已随 payload 下发（`planner.js`：`normalizePoi()` 把空数组归一为 null、
        // `toLocation()` 透传），故这里通常能取到值；取不到则**不留占位**（占位等于编造）。
        //
        // 逗号处理必须与服务端 `costText()` 同口径：中英文逗号都要清掉。
        // 只清英文逗号的话，高德偶发的中文逗号会静默解析失败 → 明明有价却显示"无价"。
        final c = loc.cost;
        if (c == null || c.isEmpty) return null;
        final n = num.tryParse(c.replaceAll(',', '').replaceAll('，', ''));
        if (n == null) return null;
        return '${PreviewStrings.mealPerPersonSuffix} ¥${n.round()}';
      case LocationType.hotel:
        return null; // 酒店无价格源（探针 0/20）→ 不显示 chip，走 OTA 深链
      case LocationType.attraction:
        return null; // 门票无价格源（探针 0/20）→ 不显示 chip，走 OTA 深链
      case LocationType.transport:
        if (t == null) return null;
        if (t.distance != null && t.distance! > 0) {
          return '${(t.distance! / 1000).toStringAsFixed(0)}km';
        }
        return null;
      default:
        return null;
    }
  }

  /// meta 文案（停留 / 营业时间 / ⚠️ 冲突 / 连住 / 班次）
  static String _metaText(Location loc) {
    final bits = <String>[];
    if (arrivalTimeOf(loc) != null) bits.add(arrivalTimeOf(loc)!);
    final stay = loc.stayMinutes;
    if (stay != null && stay > 0) bits.add('停留${_dur(stay)}');
    if (loc.openTime != null && loc.closeTime != null) {
      bits.add('营业 ${loc.openTime}-${loc.closeTime}');
    }
    if (loc.stayNote != null && loc.stayNote!.isNotEmpty) bits.add(loc.stayNote!);
    final t = loc.transport;
    if (t != null) {
      // 【TL-10 回归】旧版有独立「交通行」展示车次/航班、起止时刻、时长、里程；
      // 新版卡片无独立交通行，这些信息若不进 meta 就整条丢失，故在此补齐。
      final label = (t.flightNumber != null && t.flightNumber!.isNotEmpty)
          ? t.flightNumber!
          : t.displayName;
      if (label.isNotEmpty) bits.add(label);
      final dep = t.departureTime;
      final arr = t.arrivalTime;
      if (dep != null && arr != null && dep.isNotEmpty && arr.isNotEmpty) {
        bits.add('$dep → $arr');
      }
      if (t.durationMinutes != null && t.durationMinutes! > 0) {
        bits.add(_dur(t.durationMinutes!));
      }
      if (t.isScheduled) bits.add('班次固定');
      if (t.isEstimate) bits.add('时长为估算占位，班次以 12306/航司为准');
    }
    return bits.join(' · ');
  }

  /// 优先用服务端时刻表
  static String? arrivalTimeOf(Location loc) =>
      (loc.arrivalTime != null && loc.arrivalTime!.isNotEmpty) ? loc.arrivalTime : null;

  static String _dur(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    if (h == 0) return '$m分钟';
    return m == 0 ? '$h小时' : '$h小时$m分';
  }

  static Color _iconBg(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return PreviewColors.orange;
      case LocationType.restaurant:
        return const Color(0xFFFA8A4F);
      case LocationType.attraction:
        return PreviewColors.blue;
      case LocationType.shopping:
        return const Color(0xFFF5576C);
      case LocationType.transport:
        return const Color(0xFF8FA3AD);
      case LocationType.home:
        return PreviewColors.green;
      default:
        return PreviewColors.chipGray;
    }
  }

  static IconData _icon(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return Icons.hotel_rounded;
      case LocationType.restaurant:
        return Icons.restaurant_rounded;
      case LocationType.attraction:
        return Icons.attractions_rounded;
      case LocationType.shopping:
        return Icons.shopping_bag_rounded;
      case LocationType.transport:
        return Icons.directions_bus_rounded;
      case LocationType.home:
        return Icons.home_rounded;
      default:
        return Icons.place_rounded;
    }
  }
}
