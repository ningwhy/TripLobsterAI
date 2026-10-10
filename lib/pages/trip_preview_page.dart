import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/price_quote.dart';
import '../models/trip_models.dart';
import '../models/trip_cost.dart';
import '../services/price_repository.dart';
import '../services/price_source.dart';
import '../services/weather_repository.dart';
import '../theme/preview_theme.dart';
import '../utils/cost_aggregator.dart';
import '../utils/date_fix.dart';
import '../utils/day_anchor.dart';
import '../utils/ota_deeplink.dart';
import '../providers/trip_provider.dart';
import '../widgets/timeline/day_anchor_table.dart';
import '../widgets/timeline/day_cost_bar.dart';
import '../widgets/timeline/day_group_header.dart';
import '../widgets/timeline/day_strip.dart';
import '../widgets/timeline/location_card.dart';
import '../widgets/timeline/members_bar.dart';
import '../widgets/timeline/price_refresh_bar.dart';
import '../widgets/timeline/preview_top_bar.dart';
import '../widgets/timeline/timeline_row.dart';
import 'trip_create_page.dart';
import 'trip_map_page.dart';
import 'route_poster_page.dart';
import 'schematic_map_page.dart';
import 'location_search_page.dart';

/// 行程预览：常驻头 + 单个长列表 + 运行时聚合层
///
/// 结构（设计 §1.3 方案 A）：
/// ```
/// Scaffold └ Column
///   ├ PreviewTopBar     (navy 常驻)
///   ├ MembersBar        (成员为空整块隐藏)
///   ├ DayStrip          (常驻，≤7 等分 / >7 横滚)
///   ├ PriceRefreshBar   (常驻)
///   └ Expanded └ NotificationListener └ ListView
///        └ for each day: DayGroupHeader(锚点) + TimelineBlock + DayCostBar
/// ```
///
/// 【裁 1】当日已计价**不取中值**（取中值即估算）；分组尾显完整区间，日期条显下限。
/// 【PR-09】整日无可计价项 → `暂无可计价数据`，**不显示金额、不显示 `¥—`、绝不 `¥0`**。
/// 【M9】首屏 0 次 `/api/planner/prices`；【FX-06a】酒店/景点永久 0 次价格请求。
class TripPreviewPage extends StatefulWidget {
  final Trip trip;

  const TripPreviewPage({super.key, required this.trip});

  @override
  State<TripPreviewPage> createState() => _TripPreviewPageState();
}

class _Slot {
  final Location location;
  final int arrival; // 分钟
  final int leave;
  final int? travelMinutes;
  _Slot(this.location, this.arrival, this.leave, this.travelMinutes);
}

class _TripPreviewPageState extends State<TripPreviewPage> {
  int _activeDayIndex = 0;
  late final ScrollController _scrollController;
  final ScrollController _dayStripController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  late DayAnchorTable _anchor;

  late final WeatherRepository _weather;
  late final PriceRepository _prices;

  /// 价格数据源（PR-10）：语义与乘数全在这里，页面与聚合器都不含数据源语义。
  /// 将来切 OTA 只改这一行为 `OtaLivePriceSource()`。
  final PriceSource _priceSource = const AmapReferencePriceSource();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _weather = WeatherRepository();
    _prices = PriceRepository(source: _priceSource);
    _prices.addListener(_onPricesChanged);
    _weather.addListener(_onWeatherChanged);
    _anchor = DayAnchorTable(dayCount: _days.length);
    // 天气并发预取（不阻塞首屏）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _weather.prefetch(_days);
      _scheduleMeasure();
    });
  }

  @override
  void dispose() {
    _prices.removeListener(_onPricesChanged);
    _weather.removeListener(_onWeatherChanged);
    _scrollController.dispose();
    _dayStripController.dispose();
    super.dispose();
  }

  void _onPricesChanged() {
    if (!mounted) return;
    setState(_anchor.markDirty); // 价格徽章改变卡片高度 → 偏移表失效，下一帧重测
  }

  void _onWeatherChanged() {
    if (!mounted) return;
    setState(_anchor.markDirty);
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _listKey.currentContext;
      if (ctx == null || !_scrollController.hasClients) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) return;
      _anchor.measure(box, _scrollController.position);
    });
  }

  // ---------------- 数据 ----------------

  /// 展示用天列表：先做 FX-04 存量日期校正（**不写库**，用户编辑时才写回）
  List<TripDay> get _days {
    final trip = widget.trip;
    if (trip.days.isEmpty) {
      return List<TripDay>.generate(
        3,
        (i) => TripDay(
          date: trip.startDate.add(Duration(days: i)),
          dayNumber: i + 1,
          locations: const [],
        ),
      );
    }
    return DateFix.corrected(trip);
  }

  /// 用户任一次编辑时把校正后的日期写回（FX-04）
  void _persistDays(List<TripDay> days) {
    widget.trip.days = days;
  }

  /// 当日聚合（每次 build 现算，不落库 —— PRD TL-07）
  ///
  /// 乘法与"哪些类型可计价"全部由 `_priceSource` 决定，聚合器只做区间相加。
  DayCost _costOf(TripDay day) =>
      CostAggregator.aggregateDay(day, widget.trip, _prices.snapshot, _priceSource);

  PriceQuote? _quoteOf(Location loc) =>
      _prices.snapshot[PriceRepositoryKey.of(loc.city, loc.name)];

  /// 营业时间冲突（红框）：到达 + 停留 超出 closeTime
  bool _isConflict(Location loc, _Slot slot) {
    final close = loc.closeTime;
    if (close == null) return false;
    final parts = close.split(':');
    if (parts.length < 2) return false;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return false;
    return slot.leave > h * 60 + m;
  }

  // ---------------- 时刻推算（服务端 arrivalTime 优先）----------------

  String _fmt(int min) {
    final m = ((min % 1440) + 1440) % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String _dur(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    if (h == 0) return '$m分钟';
    return m == 0 ? '$h小时' : '$h小时$m分';
  }

  /// 时刻表：服务端 `arrivalTime` 非空则直接用；否则回退 9:00 累加（FX-02 验收②）
  List<_Slot> _slots(TripDay day) {
    var clock = 9 * 60;
    final out = <_Slot>[];
    for (final loc in day.locations) {
      final travel = (loc.transportMinutes != null && loc.transportMinutes! > 0) ? loc.transportMinutes : null;
      if (travel != null) clock += travel;
      final stay = loc.stayMinutes ?? 60;
      final serverArrival = _toMin(loc.arrivalTime);
      final arrival = serverArrival ?? clock;
      final serverLeave = _toMin(loc.leaveTime);
      final leave = serverLeave ?? (arrival + stay);
      out.add(_Slot(loc, arrival, leave, travel));
      clock = leave;
    }
    return out;
  }

  int? _toMin(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return null;
    final p = hhmm.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  // ---------------- 交互 ----------------

  void _onDayTap(int i) {
    setState(() => _activeDayIndex = i); // 立即高亮，不等动画
    _centerDayStripCell(i); // >7 天横滚模式：选中格滚到中间
    _anchor.isProgrammatic = true;
    final target = _anchor.targetFor(i);
    if (target == null) {
      // 偏移表尚未测量 → 下一帧重测后重试一次
      _scheduleMeasure();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final t = _anchor.targetFor(i);
        if (t != null) _animateTo(t, i);
        else _anchor.isProgrammatic = false;
      });
      return;
    }
    _animateTo(target, i);
  }

  /// 【横滚接线】>7 天时把选中格横向居中（PM 规格：`animateTo`，300ms）。
  ///
  /// `DayAnchor.centeredScrollOffset` 内已做首/末格钳制（负 → 0，超 → maxScroll），
  /// 故这里只需取真实视口宽与最大滚动量，不用自己判边界。
  ///
  /// 此前 `DayAnchor.centeredScrollOffset` 是**零调用点**的死代码
  /// （`_dayStripController` 只声明/dispose/传入，从未被驱动）。
  void _centerDayStripCell(int i) {
    final c = _dayStripController;
    if (!c.hasClients) return;
    final pos = c.position;
    // 视口尺寸未就绪时不猜，避免用错宽度把选中格推出屏幕
    if (!pos.hasViewportDimension || !pos.hasContentDimensions) return;

    final offset = DayAnchor.centeredScrollOffset(
      index: i,
      count: _days.length,
      cellWidth: DayStrip.cellWidth,
      viewportWidth: pos.viewportDimension,
      maxScroll: pos.maxScrollExtent,
    );
    // 已在目标位置就不动画，避免每次点击都触发一次无谓的横向滚动
    if ((c.offset - offset).abs() < 0.5) return;
    c.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _animateTo(double target, int i) async {
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    if (!mounted) return;
    _anchor.isProgrammatic = false;
    // 动画结束做一次 spy 校正（防停在两个分组之间）
    final idx = _anchor.activeIndex(_scrollController.offset);
    if (idx != _activeDayIndex) setState(() => _activeDayIndex = idx);
  }

  bool _onScroll(ScrollNotification n) {
    if (_anchor.isDirty) _scheduleMeasure();
    if (_anchor.isProgrammatic) return false; // 程序化滚动期间不抢高亮
    if (!_scrollController.hasClients) return false;
    final idx = _anchor.activeIndex(_scrollController.offset);
    if (idx != _activeDayIndex) setState(() => _activeDayIndex = idx);
    return false;
  }

  /// 行程级副标题：出发日期 + 总天数。
  ///
  /// 【TL-10 回归】旧版预览页顶部有「出发日期」元信息卡，重写时整条掉了，此处补回。
  /// 分组头虽有每天日期，但行程级出发日与天数是另一回事——用户核对"这趟行程
  /// 拿对了没"看的是出发日，不是其中某一天。
  String get _tripSubtitle {
    final d = widget.trip.startDate;
    final ymd = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return '出发 $ymd · 共 ${widget.trip.totalDays} 天';
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    final days = _days;
    if (_activeDayIndex >= days.length) _activeDayIndex = 0;
    if (_anchor.dayCount != days.length) {
      _anchor = DayAnchorTable(dayCount: days.length);
      _scheduleMeasure();
    }

    // 【三态】单值不带 `≥`、真区间带 `≥`、无数据 `—`；必须传 high，否则退化成单值。
    // ⚠️ 每 day 只算一次：`_costOf` 会跑一遍全量聚合，重复调用是 O(n²)。
    final dayCosts = days.map(_costOf).toList();
    final costTexts = dayCosts
        .map((c) => CostAggregator.lowerBoundText(c.low, c.high))
        .toList();
    final hasHome = days
        .map((d) => d.locations.any((l) => l.type == LocationType.home))
        .toList();

    return Scaffold(
      backgroundColor: PreviewColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PreviewTopBar(
              onBack: () => Navigator.of(context).maybePop(),
              onEdit: _openEdit,
              onPoster: _showPosterSheet,
              onSave: _saveTrip,
              subtitle: _tripSubtitle,
            ),
            MembersBar(trip: widget.trip, onInvite: _onInvite),
            Container(
              color: PreviewColors.navy,
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: DayStrip(
                days: days,
                activeIndex: _activeDayIndex,
                costTexts: costTexts,
                hasHome: hasHome,
                onTap: _onDayTap,
                scrollController: days.length > 7 ? _dayStripController : null,
              ),
            ),
            PriceRefreshBar(
              loading: _prices.isLoading,
              // 【A-15】置灰**由数据源驱动**：只要有任一地点「既计价、又需要联网」就亮起。
              //
              // 两层判断缺一不可（架构师 v1.9 指出，采纳）：
              // - `supports(l)`    = 该类型是否被计价（餐饮/跨城 ✅，酒店/景点 ❌）
              // - `needsNetwork(l)` = 是否需要联网取价（本轮恒 false）
              // 少了 `supports` 的话，若将来出现「支持计价但数据随 payload 下发」的类型，
              // 按钮会亮起却拉回一条根本不会被引用的价 —— `priceOf` 首行即
              // `if (!supports(loc)) return null`，白烧配额且无任何报错。
              //
              // 本轮二者恒 false → 恒置灰；OTA 接入后只改 `requestKindFor` 一处即自动亮起。
              enabled: widget.trip.allLocations
                  .any((l) => _priceSource.supports(l) && _priceSource.needsNetwork(l)),
              // 无可刷项时兜底常驻说明，避免用户以为功能坏了
              status: _prices.refreshStatus.isNotEmpty
                  ? _prices.refreshStatus
                  : PreviewStrings.priceOfflineNote,
              onRefresh: _refreshPrices,
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListView(
                  key: _listKey,
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                  children: [
                    for (var i = 0; i < days.length; i++) _buildDaySection(i, days[i]),
                    _buildTripCostFooter(days),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _fab(Icons.map_outlined, const Color(0xFFFF9F43), () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => TripMapPage(trip: widget.trip)));
          }),
          const SizedBox(height: 12),
          _fab(Icons.add, PreviewColors.teal, _addLocationToDay),
        ],
      ),
    );
  }

  Widget _buildDaySection(int index, TripDay day) {
    final slots = _slots(day);
    final isTripStartDay = day.dayNumber == 1;

    final rows = <Widget>[];
    for (var k = 0; k < slots.length; k++) {
      final s = slots[k];
      final loc = s.location;
      rows.add(
        TimelineRow(
          timeText: _fmt(s.arrival),
          dotColor: TimelineRow.dotColorOf(loc, isTripStart: isTripStartDay && k == 0),
          child: LocationCard(
            location: loc,
            arrivalText: _fmt(s.arrival),
            leaveText: _fmt(s.leave),
            quote: _quoteOf(loc),
            // 酒店/景点本轮无价格源 → 不渲染徽章（渲染出来必然是"暂无参考价"，是噪音）
            showPrice: _priceSource.supports(loc),
            conflict: _isConflict(loc, s),
            onTap: () => _showLocationSheet(loc),
            onOta: () => _openOta(loc),
            onEditStay: () => _editStay(loc),
            onRemove: () => _removeLocation(loc),
            // 【TL-10 回归】旧版判据是「过滤掉自己之后还有候选」，不是「原始长度 > 1」。
            // 当 hotelCandidates 里不含当前酒店时，旧版能换、新版会误判为不能换。
            onSwitchHotel:
                loc.type == LocationType.hotel &&
                        (loc.hotelCandidates ?? const <Map<String, dynamic>>[])
                            .where((c) => c['name'] != loc.name)
                            .isNotEmpty
                    ? () => _showHotelSwitch(loc)
                    : null,
            // 乘数唯一出口（PR-10）：票价 `¥553×2` 用它，widget 不自己算人数
            peopleCount: _priceSource.peopleCount(widget.trip),
          ),
        ),
      );
      rows.add(const SizedBox(height: 7));
    }

    return Column(
      key: _anchor.keys[index],
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DayGroupHeader(
          day: day,
          weather: _weather.peek(day),
          weatherLoading: _weather.isPending(day),
        ),
        if (slots.isEmpty)
          _buildEmptyDay()
        else
          TimelineBlock(rows: rows),
        DayCostBar(cost: _costOf(day)),
      ],
    );
  }

  /// 行程级费用出口：
  /// - 有 `stats.cost` → 独立小卡（items + total + note + 口径冲突说明）【裁 2】
  /// - 无 → 全行程"可归集合计"（仅卡片可归集价格），明写未含油电过路
  Widget _buildTripCostFooter(List<TripDay> days) {
    final stats = widget.trip.statsCost;
    if (stats != null) return _buildStatsCostCard(stats);

    var low = 0;
    var high = 0;
    var missing = 0;
    for (final d in days) {
      final c = _costOf(d);
      low += c.low;
      high += c.high;
      missing += c.missingCount;
    }
    final isEmptyAmount = low == 0 && high == 0;
    final amount = isEmptyAmount
        ? PreviewStrings.dayCostEmpty
        : (low == high
            ? '¥${CostAggregator.fmtAmount(low)}'
            : '¥${CostAggregator.fmtAmount(low)}–${CostAggregator.fmtAmount(high)}');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PreviewColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PreviewColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 16, color: PreviewColors.green2),
              const SizedBox(width: 6),
              const Text('全行程已计价', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PreviewColors.ink)),
              const Spacer(),
              // 空态不出金额（不显示 ¥0、不显示 ¥—）
              if (isEmptyAmount)
                Flexible(child: Text(amount, style: PreviewText.costLabel))
              else
                Text(amount, style: PreviewText.costNum),
            ],
          ),
          const SizedBox(height: 6),
          // 【常驻副行】与分组尾同一口径文案，**空态也必须显示**（诚实性承载点）
          Text(
            '${PreviewStrings.priceScope}${missing > 0 ? ' · $missing 项未取到价' : ''}',
            style: PreviewText.costLabel,
          ),
        ],
      ),
    );
  }

  /// 【裁 2 / M6】`stats.cost` 与「当日已计价」**并列**展示，卡面明写口径不同、不可相加
  Widget _buildStatsCostCard(TripCost stats) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PreviewColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PreviewColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 16, color: PreviewColors.green2),
              const SizedBox(width: 6),
              const Text('费用预估（服务端口径）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PreviewColors.ink)),
              const Spacer(),
              Text('¥${CostAggregator.fmtAmount(stats.total)}', style: PreviewText.costNum),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: stats.sortedItems
                .map((e) => Text('${e.key} ¥${CostAggregator.fmtAmount(e.value)}', style: PreviewText.costLabel))
                .toList(),
          ),
          if (stats.note != null && stats.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(stats.note!, style: PreviewText.costLabel),
          ],
          const SizedBox(height: 6),
          // 【常驻副行】与分组尾同口径：本卡**只含服务端那几项**，不含餐饮/交通参考价。
          // 明写出来，避免用户把它与「当日已计价」当成同一口径相加。
          Text(PreviewStrings.priceScope, style: PreviewText.costLabel),
          const SizedBox(height: 6),
          Text(TripCost.scopeConflictNote,
              style: const TextStyle(fontSize: 11, color: PreviewColors.priceRedText)),
        ],
      ),
    );
  }

  Widget _buildEmptyDay() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: PreviewColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PreviewColors.line),
      ),
      child: Column(
        children: [
          Icon(Icons.calendar_month_outlined, size: 36, color: PreviewColors.dim),
          const SizedBox(height: 8),
          const Text('这一天还没有安排', style: TextStyle(fontSize: 13, color: PreviewColors.sub)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _addLocationToDay,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加地点'),
            style: TextButton.styleFrom(foregroundColor: PreviewColors.green2),
          ),
        ],
      ),
    );
  }

  Widget _fab(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  // ---------------- 业务动作 ----------------

  Future<void> _refreshPrices() async {
    await _prices.refreshTrip(widget.trip);
  }

  void _onInvite() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(PreviewStrings.inviteTodo)),
    );
    _showPosterSheet();
  }

  void _openEdit() {
    context.read<TripProvider>().setCurrentTrip(widget.trip);
    Navigator.push(context, MaterialPageRoute(builder: (_) => TripCreatePage(trip: widget.trip)));
  }

  Future<void> _saveTrip() async {
    final provider = context.read<TripProvider>();
    await provider.updateTrip(widget.trip);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('行程已保存')));
  }

  Future<void> _addLocationToDay() async {
    final result = await Navigator.push<Location>(
      context,
      MaterialPageRoute(builder: (_) => const LocationSearchPage()),
    );
    if (result == null || !mounted) return;
    final days = _days;
    final i = _activeDayIndex;
    if (i >= days.length) return;
    final day = days[i];
    final locations = List<Location>.from(day.locations)..add(result);
    days[i] = TripDay(id: day.id, date: day.date, dayNumber: day.dayNumber, locations: locations);
    _persistDays(days); // FX-04：编辑即写回校正日期
    await context.read<TripProvider>().updateTrip(widget.trip);
    if (!mounted) return;
    setState(() => _anchor.markDirty());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加「${result.name}」到第${day.dayNumber}天')),
    );
  }

  Future<void> _removeLocation(Location loc) async {
    final days = _days;
    final i = _activeDayIndex;
    if (i >= days.length) return;
    final day = days[i];
    if (loc.fixed) {
      // 【裁 4】必去点保护由客户端维护
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${loc.name}」是必去点，不能移除')),
      );
      return;
    }
    final locations = List<Location>.from(day.locations)..removeWhere((l) => l.id == loc.id);
    days[i] = TripDay(id: day.id, date: day.date, dayNumber: day.dayNumber, locations: locations);
    _persistDays(days);
    await context.read<TripProvider>().updateTrip(widget.trip);
    if (!mounted) return;
    setState(() => _anchor.markDirty());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已移除「${loc.name}」')));
  }

  void _editStay(Location loc) {
    const options = [30, 60, 90, 120, 150, 180, 240];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('停留时长', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: PreviewColors.ink)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: options.map((m) {
                  final selected = loc.stayMinutes == m;
                  return ChoiceChip(
                    label: Text(_dur(m)),
                    selected: selected,
                    onSelected: (_) async {
                      Navigator.pop(ctx);
                      loc.stayMinutes = m;
                      final days = _days;
                      _persistDays(days);
                      await context.read<TripProvider>().updateTrip(widget.trip);
                      if (mounted) setState(() => _anchor.markDirty());
                    },
                    selectedColor: PreviewColors.priceGreenBg,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: selected ? PreviewColors.green2 : PreviewColors.ink,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchHotel(Location loc, Map<String, dynamic> cand) async {
    loc.name = cand['name']?.toString() ?? loc.name;
    loc.address = cand['address']?.toString() ?? loc.address;
    loc.latitude = (cand['latitude'] as num?)?.toDouble() ?? loc.latitude;
    loc.longitude = (cand['longitude'] as num?)?.toDouble() ?? loc.longitude;
    loc.cost = cand['cost']?.toString() ?? loc.cost;
    _persistDays(_days);
    await context.read<TripProvider>().updateTrip(widget.trip);
    if (!mounted) return;
    setState(() => _anchor.markDirty());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已切换酒店，次日出发交通时长可重新编辑校准')),
    );
  }

  void _showHotelSwitch(Location loc) {
    final cands = (loc.hotelCandidates ?? []).where((c) => c['name'] != loc.name).toList();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('换一家（AI 已按位置/口碑/星级/预算筛过）',
                  style: TextStyle(fontSize: 12, color: PreviewColors.sub)),
            ),
            ...cands.map((c) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.hotel_rounded, size: 20, color: PreviewColors.green2),
                  title: Text(c['name']?.toString() ?? '', style: const TextStyle(fontSize: 14)),
                  subtitle: Text(c['reason']?.toString() ?? '', style: PreviewText.cardMeta),
                  onTap: () {
                    Navigator.pop(ctx);
                    _switchHotel(loc, c);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLocationSheet(Location loc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(loc.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: PreviewColors.ink)),
            ),
            if (loc.stayNote != null && loc.stayNote!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(loc.stayNote!, style: PreviewText.cardMeta),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('查看房型与价格（跳转第三方）', style: PreviewText.cardMeta),
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.map_rounded, size: 20, color: Color(0xFF4CA84A)),
              title: const Text('高德·详情与导航', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _openExternal(OtaDeepLink.build(loc, OtaDeepLink.nav));
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.flight_takeoff_rounded, size: 20, color: Color(0xFF2E7D9C)),
              title: Text('携程·${OtaDeepLink.buttonText(OtaDeepLink.purposeOf(loc))}',
                  style: const TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _openOta(loc);
              },
            ),
            // 【TL-10 回归】旧版此处有「美团·比价」，重写时丢失，补回。
            // 用途固定传 meituan（不按地点类型推导）：任何地点都能比价。
            ListTile(
              dense: true,
              leading: const Icon(Icons.storefront_rounded, size: 20, color: Color(0xFFE58E26)),
              title: const Text('美团·比价', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _openOtaWith(loc, OtaDeepLink.meituan);
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            ListTile(
              leading: const Icon(Icons.timelapse_outlined, color: PreviewColors.green2),
              title: const Text('调整停留时长'),
              onTap: () {
                Navigator.pop(ctx);
                _editStay(loc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('从行程中移除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _removeLocation(loc);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showPosterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('生成行程海报',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: PreviewColors.ink)),
            ),
            ListTile(
              leading: const Icon(Icons.satellite_alt_rounded, size: 22, color: Color(0xFF5B9BD5)),
              title: const Text('卫星路线图', style: TextStyle(fontSize: 14)),
              subtitle: const Text('卫星底图 + 真实路线，硬核风', style: PreviewText.cardMeta),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => RoutePosterPage(trip: widget.trip)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.map_rounded, size: 22, color: Color(0xFFC9A227)),
              title: const Text('手绘示意图（游戏风）', style: TextStyle(fontSize: 14)),
              subtitle: const Text('羊皮纸底图 + 贴纸点位 + 山水标注', style: PreviewText.cardMeta),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => SchematicMapPage(trip: widget.trip)));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 花钱类 OTA 跳转：二次确认（三铁律第 3 条）
  Future<void> _openOta(Location loc) => _openOtaWith(loc, OtaDeepLink.purposeOf(loc));

  /// 指定用途的 OTA 跳转（【TL-10】美团比价等固定渠道入口走这里）
  Future<void> _openOtaWith(Location loc, String purpose) async {
    final url = OtaDeepLink.build(loc, purpose);
    if (!OtaDeepLink.needsConfirm(purpose)) {
      await _openExternal(url);
      return;
    }
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(OtaDeepLink.confirmTitle(purpose)),
        content: Text(OtaDeepLink.confirmText(loc, purpose)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
        ],
      ),
    );
    if (go != true) return;
    await _openExternal(url);
  }

  Future<void> _openExternal(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能打开链接，可复制地点名称到对应 App 搜索')),
      );
    }
  }
}
