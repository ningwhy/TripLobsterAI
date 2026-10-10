import 'package:flutter/material.dart';

/// 行程预览页**局部**视觉令牌（navy/teal）
///
/// 作用域：仅 `trip_preview_page.dart` 与其 `lib/widgets/timeline/*` 子部件。
/// **禁止**修改全局 `AppColors`，**禁止**在其他页面引用本文件。
class PreviewColors {
  PreviewColors._();

  // ---- 主色（PRD §5.0 原样落地）----
  static const navy = Color(0xFF17212B); // 顶栏底
  static const teal = Color(0xFF26C6A8); // 主强调
  static const blue = Color(0xFF3B82F6); // 景点圆点
  static const green = Color(0xFF34C77B); // 出发/到家圆点
  static const orange = Color(0xFFFF9F43); // 酒店圆点
  static const green2 = Color(0xFF0D9B84); // 当日已计价数字

  // ---- 文字 ----
  static const ink = Color(0xFF22303E); // 主文字
  static const sub = Color(0xFF8A97A5); // 次级文字
  static const dim = Color(0xFFB9C4CF); // 弱文字/占位

  // ---- 线与底 ----
  static const line = Color(0xFFE8EDF2);
  static const line2 = Color(0xFFE2E9EF); // 时间轴轴线
  static const cardBg = Color(0xFFFFFFFF);
  static const pageBg = Color(0xFFF4F7FA);
  static const dateBarBg = Color(0xFFE9EFF4); // 分组头底
  static const chipGray = Color(0xFF7B8896);

  // ---- 价格徽章（二态）----
  static const priceGreenBg = Color(0xFFF0FBF8);
  static const priceGreenBorder = Color(0xFFD4EDE5);
  static const priceGrayBg = Color(0xFFF4F7FA);
  static const priceGrayBorder = Color(0xFFE2E9EF);
  // 红态色值【裁 P-3】：本轮**不实现**红态（"有价但待核实"的前提不存在 —— 酒店根本无价）。
  // 仅保留色值备用，**不写任何代码分支引用**，以免产生死代码。
  static const priceRedText = Color(0xFF9C2B1E);
  static const priceRedBg = Color(0xFFFFF2F0);
  static const priceRedBorder = Color(0xFFF3B4AB);

  // ---- 天气 ----
  static const weatherBg = Color(0xFFF0FBF8);
  static const weatherBorder = Color(0xFFD4EDE5);
  static const tempHigh = Color(0xFFC0392B);
  static const tempLow = Color(0xFF0B6BCB);
  static const windText = Color(0xFF9AA7B4);

  // ---- 语义：营业时间冲突（卡片描边红框，与价格徽章红框不得共用）----
  static const conflictBorder = Color(0xFFE5533D);
}

/// 预览页文本样式（避免每个 widget 各写一份）
class PreviewText {
  PreviewText._();

  static const title = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white);
  static const dayNum = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
  static const dayNumSub = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500);
  static const groupHeader = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF4A5A68));
  static const groupMeta = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: PreviewColors.chipGray);
  static const timeCol = TextStyle(fontSize: 11, color: PreviewColors.sub);
  static const cardName = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: PreviewColors.ink);
  static const cardMeta = TextStyle(fontSize: 11.5, color: PreviewColors.sub);
  static const chip = TextStyle(fontSize: 10.5, color: PreviewColors.chipGray);
  static const badge = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF3D4C5C));
  static const badgeGray = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: PreviewColors.chipGray);
  static const weather = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF3D4C5C));
  static const weatherWind = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w400, color: PreviewColors.windText);
  /// 金额数字样式。
  ///
  /// ⚠️ **2026-10-10 修订（外部评审 P0-2）：价格降为次级信息**
  ///
  /// 原为 `green2`（强调色）+ `w700`。强调色会把视线从"行程执行信息"
  /// （地点顺序 / 时段 / 交通耗时 / 营业时间冲突）抢到金额上，而本页金额
  /// **结构性缺了酒店与门票**（占每日花费 40~60%），不配占据视觉主位。
  ///
  /// 修订后：改用中性墨色 `ink`、字重降至 `w600`，与正文同色系。
  /// 金额仍然可读、仍然在，但不再**跳出来**——这正是评审要的
  /// "价格是行程决策的一部分，不是产品中心"。
  ///
  /// ⛔ 本处**只改样式，不改文案**：「当日已计价」受【三铁律 3】锁定，
  /// 不得改回「当日合计」，本次一字未动。
  ///
  /// ⚠️ 注意：本样式同时被页尾汇总卡与 `stats.cost` 卡复用，
  /// 三处金额会一起降级——这是**故意**的，三者都不含酒店，口径一致。
  static const costNum = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PreviewColors.ink);
  static const costLabel = TextStyle(fontSize: 11.5, color: PreviewColors.sub);
  static const statusLine = TextStyle(fontSize: 11, color: PreviewColors.chipGray);
}

/// 预览页文案常量（**单一来源**，评审 grep 一处即可）
///
/// M7 硬约束：全页**不得**出现「实时价 / 实时房价 / 可订状态 / 售罄 / 不可订 / 待核实」。
///
/// 【PR-10 ②】所有**口径**文案只在本文出现一次；widget 与 `PriceSource` 均**引用常量**，
/// 不得各自硬编码 —— 将来切 OTA 只改这里的值，widget / 聚合器 / 缓存层零改动。
class PreviewStrings {
  PreviewStrings._();

  // ---------------- 价格徽章（二态；【裁 P-3】红态本轮不实现）----------------
  /// 卡片级无价文案（某张卡查不到价）。与**整日级** `dayCostEmpty` 不得混用。
  static const priceAbsent = '暂无参考价';

  /// 徽章有价文案：widget 只传数值，语义集中在此（PR-10 ①：widget 层零数据源语义）
  static String priceBadgeText(String amount, {String timeSuffix = ''}) {
    final ts = timeSuffix.isEmpty ? '' : ' · $timeSuffix';
    return '💰 参考价 $amount$ts';
  }

  // ---------------- 当日已计价（M11：不得叫「当日合计」）----------------
  static const dayCostTitle = '当日已计价';

  /// 整日级无价文案（这天没有任何可计价项）→ 不显示金额、不显示 `¥—`、绝不 `¥0`
  static const dayCostEmpty = '暂无可计价数据';

  /// 常驻副行口径说明
  static const priceScope = '含 餐饮·交通 ｜ 未含：酒店 · 门票（暂无参考价）';

  /// 【A-15】刷新条在**无任何地点需要联网取价**时的常驻说明。
  ///
  /// 按钮置灰时用它兜底 `status` 行——保留可解释性，让用户知道价格从哪来、
  /// 而不是以为功能坏了（完全隐藏按钮会让用户无从判断）。
  /// 【M7】只说「参考价」，**不得**出现「实时房价 / 可订状态」。
  static const priceOfflineNote =
      '餐饮与交通参考价随行程下发 · 酒店与门票暂无参考价源';

  // ---------------- 刷新按钮状态行（v1.3 §7.6）----------------
  static const refreshPrice = '🔄 刷新参考价';

  /// M7：不写「非实时房价」（含违禁子串「实时房价」），改写「静态数据」
  static const refreshing = '⏳ 正在拉取参考价（高德 POI 静态数据）…';

  static const refreshDone = '餐饮/交通参考价已为最新';
  static const refreshFailed = '❌ 刷新失败（沿用上次参考价）';
  static const refreshScopeNote =
      '酒店与门票参考价需高德住宿专项数据或 OTA 接入，当前数据源不可用';

  /// 状态行组装：成功/失败**后半句口径说明不变**（§7.6 要求），失败仅加前缀
  static String refreshStatusLine({required bool failed}) => failed
      ? '$refreshFailed · $refreshScopeNote'
      : '$refreshDone · $refreshScopeNote';

  /// 本行程没有任何需要刷新的价格项（如：全程无餐饮点）
  static const refreshNone = '本行程没有可刷新的餐饮参考价';

  // ---------------- 卡片 chip ----------------
  /// 餐饮 chip 前缀（探针实测 `biz_ext.cost` 为**人均**价）
  static const mealPerPersonSuffix = '人均';

  // ---------------- OTA（PR-08：酒店/景点无价 → 深链即价格功能的主要交付形态）----------------
  static const otaHotelText = '🏨 去携程看价格 ↗';
  static const otaTicketText = '🎟 去携程看票价 ↗';
  static const otaNavText = '🧭 导航 ↗';
  /// 【TL-10 回归】旧版地点详情弹窗的第三个 OTA 入口（美团比价）
  static const otaMeituanText = '🍊 去美团比价 ↗';

  /// 二次确认文案（M7：不写「可订状态」，改用「价格以平台实时页面为准」）
  ///
  /// [platform] 必须写明跳去哪家，不能一律写「携程」（TL-10 补回美团入口后才有此需求）。
  static String otaConfirm(String name, {String platform = '携程'}) =>
      '将跳转到$platform查看「$name」，价格以平台实时页面为准';
  static const inviteTodo = '邀请功能开发中，可先分享行程海报';
}
