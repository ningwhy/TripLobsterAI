import 'package:flutter/material.dart';

import '../../models/price_quote.dart';
import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';
import '../../utils/cost_aggregator.dart';
import '../../utils/itinerary_checker.dart';
import '../../utils/ota_deeplink.dart';
import 'issue_note.dart';
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

  /// 该地点的**唯一**主问题（T04：由 `checkItineraryDay` 产出、页面传入）。
  ///
  /// null = 本设计列出的规则对该地点没有产出问题。
  ///
  /// ⛔ **不要**把它理解成"校验通过"：没有提示只表示列出的规则没触发，
  ///    不代表现实行程没问题 —— 所以页面**不渲染**「已校验通过」。
  ///
  /// ⛔ 中性级（CH-09）**不会**出现在这里：它是日级声明，不上卡片。
  final ItineraryIssue? issue;

  final VoidCallback onTap;
  final VoidCallback onOta;
  final VoidCallback onEditStay;
  final VoidCallback onRemove;
  final VoidCallback? onSwitchHotel;

  /// 手动补录实付金额（评审 2026-10-10 建议）
  ///
  /// null → 卡片不显示补录入口（例如只读场景）。
  /// ⛔ 与 `showPrice` **互不相关**：`showPrice` 管的是"数据源能否给参考价"，
  /// 补录管的是"用户愿不愿意填自己付的钱"。酒店 `showPrice==false` 恰恰
  /// **最需要**补录入口 —— 不要把两者绑在一起。
  final VoidCallback? onManualCost;

  /// 出行人数（用于班次票价 `¥553×2`）。
  ///
  /// 由页面用 `PriceSource.peopleCount(trip)` 传入 —— widget **不自己算人数**，
  /// 避免"乘数语义"散落到多处（PR-10：乘数只允许有一个出口）。
  final int peopleCount;

  const LocationCard({
    super.key,
    required this.location,
    this.arrivalText,
    this.leaveText,
    this.quote,
    this.showPrice = true,
    this.issue,
    required this.onTap,
    required this.onOta,
    required this.onEditStay,
    required this.onRemove,
    this.onSwitchHotel,
    this.onManualCost,
    this.peopleCount = 1,
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
          // 只有**阻塞**描红边：提醒级不描边（否则三级提示视觉上糊成一片，
          // 用户分不清哪个必须改）。红框语义专属于"排不下/赶不上"。
          border: issue?.severity == IssueSeverity.blocking
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
              _metaText(loc, peopleCount: peopleCount),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PreviewText.cardMeta,
            ),
            // ②-bis 可执行性提示：**同地点最多一条**
            //
            // 去重由 `itinerary_checker.dart` 完成（severity 优先、同级按固定 code 优先级），
            // 这里**不做第二次判断** —— widget 不持有业务判据（设计 §1.5）。
            if (issue != null) ...[
              const SizedBox(height: 6),
              IssueNote(severity: issue!.severity, text: issue!.message),
              // 证据副行：**不是第二条问题**，是让用户核对结论来源的原文切片。
              // ⛔ 只显示服务端给的命中子句，**绝不**把结构化值反拼成"原文"
              //    （反拼出来的东西看起来像原文，实际是我们造的）。
              if (issue!.sourceRaw != null && issue!.sourceRaw!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${PreviewStrings.openHoursSourcePrefix}${issue!.sourceRaw}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: PreviewColors.dim,
                  ),
                ),
              ],
            ],
            // ③ 价格区（手填 与 参考价 **互斥**，不同时显示）
            //
            // 互斥理由：两者若并列，用户会以为「当日已计价」把它们**都**算了进去，
            // 而聚合器实际是"手填优先、参考价跳过"（见 `aggregateDay`）。
            // 显示两个数字、只算一个 → 数字对不上，是最伤信任的那类错。
            // 二选一后卡片上永远只有一个数，与聚合口径严格一致。
            if (loc.manualCost != null) ...[
              const SizedBox(height: 6),
              _manualChip(loc.manualCost!),
            ] else if (showPrice) ...[
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
                // 补录入口**不受 showPrice 限制**：酒店/景点无参考价源，
                // 恰恰是最需要用户自己填的两类（见 `onManualCost` 注释）。
                if (onManualCost != null)
                  _action(
                    loc.manualCost == null
                        ? PreviewStrings.manualCostAdd
                        : PreviewStrings.manualCostEdit,
                    onManualCost!,
                  ),
                if (onSwitchHotel != null) _action('换一家', onSwitchHotel!),
                _action('移除', onRemove, color: PreviewColors.sub),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 手填金额标记（点击可改）
  ///
  /// 用灰底而非绿底：绿底在 `price_badge.dart` 里已约定表示"数据源给的参考价"，
  /// 手填是**另一类来源**（来源透明第三层要求两者可辨），复用绿色会抹掉这个区分。
  Widget _manualChip(int amount) {
    return GestureDetector(
      onTap: onManualCost,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: PreviewColors.priceGrayBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PreviewColors.priceGrayBorder, width: 1),
        ),
        child: Text(
          PreviewStrings.manualCostText('¥${CostAggregator.fmtAmount(amount)}'),
          style: PreviewText.badgeGray,
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
        // 餐饮：人均价（探针实测 18/20 有值），**随行程 payload 离线下发，0 次价格请求**。
        // SR-02：`planner.js` `normalizePoi()` 把 `biz_ext.cost` 归一（空数组 → null）、
        // `toLocation()` 透传，故这里通常能取到值；取不到则**不留占位**（占位等于编造）。
        //
        // ⚠️ 不要再把本类型当成"需联网取价"：`requestKindFor()` 恒 null，刷新按钮对它无效。
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

  /// meta 文案（地点 / 停留 / 营业时间 / ⚠️ 冲突 / 连住 / 班次票价）
  ///
  /// 【TL-10 回归 + US-1】首段补地址/城市：服务端 `normalizePoi` 已返回 `address`/`city`，
  /// 但此前**客户端零引用**（grep `\.address` 在 timeline 层 0 命中）。
  /// 多城走廊里"北京站/天津站"这类同名地点很常见，只显示名称无法区分是哪个城的。
  static String _metaText(Location loc, {int peopleCount = 1}) {
    final bits = <String>[];
    // 首段：城市 + 地址（同名地点的区分依据）。两者都空则跳过，不留空占位。
    final place = _placeText(loc);
    if (place.isNotEmpty) bits.add(place);
    if (arrivalTimeOf(loc) != null) bits.add(arrivalTimeOf(loc)!);
    final stay = loc.stayMinutes;
    if (stay != null && stay > 0) bits.add('停留${_dur(stay)}');
    // 营业时间是**目标日期**的解析结论（服务端 `parseOpenTime(poi,date)`）：
    // 只有服务端唯一命中某一时段时才会有值；多时段 / 解析失败 → 全 null，
    // 此时**不显示任何营业片段**（显示 "营业 null-null" 或部分信息都是误导）。
    if (loc.openTime != null && loc.closeTime != null) {
      bits.add('营业 ${loc.openTime}-${loc.closeTime}');
    }
    // 停止入场是**独立事实**，不是"营业时间"的一部分，单独成段更可核对
    if (loc.lastEntryTime != null && loc.lastEntryTime!.isNotEmpty) {
      bits.add('停止入场 ${loc.lastEntryTime}');
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
      // 【新增】班次票价：`¥553×2`。
      //
      // ⛔ `price == null` **不显示任何片段** —— 服务端估算分支恒 null
      // （`planner.js:475` / `multiCity.js:569,735`），此时写"暂无票价"是噪音，
      // 写 `¥0` 是撒谎。诚实缺失即留空。
      //
      // ⚠️ 只乘人数、**不乘 rooms**（与 `PriceSource.peopleCount` 同口径，PR-10 硬约束：
      // "人均"与"每间夜"是两套语义，房间数不得进入计价路径）。
      final fare = _fareText(t.price, n: peopleCount);
      if (fare.isNotEmpty) bits.add(fare);
      if (t.isScheduled) bits.add('班次固定');
      if (t.isEstimate) bits.add('时长为估算占位，班次以 12306/航司为准');
    }
    return bits.join(' · ');
  }

  /// 班次票价文案：`¥553×2`（[n] 为人数）。
  ///
  /// 单人（[n] <= 1）时省略 `×n` —— `¥553×1` 是噪音。
  /// ⛔ [price] 为 null / 非正数 → 返回空串（**不估算、不兜底、不显示 ¥0**）。
  static String _fareText(num? price, {int n = 1}) {
    if (price == null || !price.isFinite || price <= 0) return '';
    // 服务端给的是元（可能带小数），按元展示不换算单位
    final s = price == price.roundToDouble()
        ? price.round().toString()
        : price.toStringAsFixed(1);
    return n > 1 ? '¥$s×$n' : '¥$s';
  }

  /// 地点首段：城市 + 地址。
  ///
  /// 地址过长时截断（meta 只有 2 行，多城走廊的长地址会把班次信息挤出视野）。
  static String _placeText(Location loc) {
    // ⛔ `address` 是**非空** `String`（`Location.fromJson` 已做 `?? ''` 兜底），
    //    这里**不得**再写 `?? ''` —— 那不是防御，是死代码，会掩盖"该兜底的地方没兜底"。
    final city = (loc.city ?? '').trim();
    final addr = loc.address.trim();
    if (city.isEmpty && addr.isEmpty) return '';
    // 地址已含城市名时不重复"北京 · 北京市…"
    final addrHasCity = city.isNotEmpty && addr.contains(city);
    if (city.isEmpty) return _trunc(addr);
    if (addr.isEmpty || addrHasCity) return city;
    return '$city · ${_trunc(addr)}';
  }

  static String _trunc(String s, [int max = 12]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

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
