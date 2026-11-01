import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/price_quote.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/services/price_source.dart';
import 'package:trip_planner/theme/preview_theme.dart';
import 'package:trip_planner/utils/cost_aggregator.dart';
import 'package:trip_planner/utils/itinerary_checker.dart';
import 'package:trip_planner/widgets/timeline/day_cost_bar.dart';
import 'package:trip_planner/widgets/timeline/issue_note.dart';
import 'package:trip_planner/widgets/timeline/location_card.dart';
import 'package:trip_planner/widgets/timeline/price_refresh_bar.dart';

/// timeline widget 层回归测试
///
/// ## 为什么需要本文件
///
/// 此前 `lib/widgets/timeline/` 下 12 个组件 **零自动化测试**
/// （既有 97 个用例全是纯逻辑，不 import 任何 timeline widget），
/// 是全项目唯一「改了 UI 但没有任何防线」的缺口。
///
/// 本文件优先锁死 **4 个已经真实发生过、且被修掉** 的 bug，
/// 防止后续重构把它们静默改回去：
///
/// | # | 已修 bug | 锁死点 |
/// |---|---|---|
/// | 1 | `DayCostBar` 空态直接 return，口径副行整块丢失 | 空态**必须**仍显示副行 |
/// | 2 | `PriceRefreshBar` 无数据源仍渲染按钮（P0-4 假可供性） | `enabled==false` 时**零按钮** |
/// | 3 | 手填金额与参考价并列显示 → 两个数字只算一个 | 二者**互斥** |
/// | 4 | 手填若放在 `supports()` 之后会被静默丢弃 | 酒店（supports 恒 false）手填**必须**计入 |
///
/// ## 测试粒度说明（不追求覆盖率，追求回归价值）
///
/// 这里**不**测像素、不测动画、不测滚动手感 —— 那些靠真机验证更划算。
/// 只测「该出现的文案出现了 / 不该出现的控件没出现 / 数字算对了」这类
/// 一旦回归就会造成**用户可见错误**的断言。
void main() {
  const src = AmapReferencePriceSource();

  Trip mkTrip({int adults = 2, int children = 0}) => Trip(
        name: 't',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 3),
        adults: adults,
        children: children,
        rooms: 1,
      );

  TripDay mkDay(List<Location> locs, {int dayNumber = 1}) => TripDay(
        date: DateTime(2026, 10, 1),
        dayNumber: dayNumber,
        locations: locs,
      );

  Location mkLoc({
    LocationType type = LocationType.restaurant,
    String name = '测试点',
    String? cost,
    int? manualCost,
    String city = '杭州',
  }) =>
      Location(
        name: name,
        address: '测试地址',
        type: type,
        city: city,
        cost: cost,
        manualCost: manualCost,
      );

  /// 包一层 MaterialApp：widget 里有 `Text`，裸 `Directionality` 不够稳
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// 从卡片子树中提取 meta 文本（多条用 ' · ' 连接的那一条）。
  /// 操作区文字（如「调整停留」）不含 ' · '，可唯一锁定。
  String? metaOf(WidgetTester tester) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final d = t.data;
      if (d != null && d.contains(' · ')) return d;
    }
    return null;
  }

  // ==================================================================
  group('DayCostBar 空态口径副行（已修 bug #1）', () {
    testWidgets('空态：显示整日文案 + 口径副行，且不出现 ¥0', (tester) async {
      final cost = CostAggregator.aggregateDay(
        mkDay([mkLoc(type: LocationType.hotel)]), // 酒店 supports=false → 聚合为空
        mkTrip(),
        const {},
        src,
      );
      expect(cost.isEmpty, isTrue);

      await tester.pumpWidget(wrap(DayCostBar(cost: cost)));

      expect(find.text(PreviewStrings.dayCostEmpty), findsOneWidget);
      // 副行是诚实性的承载点：恰恰在"一分钱都没算出来"时最需要说明缺什么
      expect(find.text(PreviewStrings.priceScope), findsOneWidget);
      // ⛔ 绝不显示 ¥0（会被读成"这天免费"）
      expect(find.textContaining('¥0'), findsNothing);
    });

    testWidgets('有数据：显示金额与副行', (tester) async {
      final cost = CostAggregator.aggregateDay(
        mkDay([mkLoc(type: LocationType.restaurant, cost: '100')]),
        mkTrip(adults: 2),
        const {},
        src,
      );
      expect(cost.isEmpty, isFalse);

      await tester.pumpWidget(wrap(DayCostBar(cost: cost)));

      // ⚠️ 有数据时 DayCostBar 用 RichText（标题与金额两种样式），
      //    `find.textContaining` 默认只搜 Text/EditableText，必须开 findRichText。
      expect(
        find.textContaining(PreviewStrings.dayCostTitle, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('¥200', findRichText: true), // 人均100 × 2人
        findsOneWidget,
      );
      expect(find.text(PreviewStrings.priceScope), findsOneWidget);
    });

    testWidgets('含手填：副行追加「含手填」（来源透明）', (tester) async {
      final cost = CostAggregator.aggregateDay(
        mkDay([mkLoc(type: LocationType.hotel, manualCost: 520)]),
        mkTrip(),
        const {},
        src,
      );

      await tester.pumpWidget(wrap(DayCostBar(cost: cost)));

      // 副行必须说清"这里面混了你自己填的钱"，否则两类可信度不同的数字无法分辨
      // 副行是普通 Text；金额仍在 RichText 里 → 同样要开 findRichText
      expect(find.textContaining('含手填'), findsOneWidget);
      expect(find.textContaining('¥520', findRichText: true), findsOneWidget);
    });
  });

  // ==================================================================
  group('PriceRefreshBar 无数据源不渲染按钮（已修 bug #2 / P0-4）', () {
    testWidgets('enabled=false：零按钮，只给静态口径说明', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(PriceRefreshBar(
        loading: false,
        enabled: false, // 本轮 requestKindFor() 恒 null → 实际状态
        status: '',
        onRefresh: () => tapped = true,
      )));

      // 核心断言：不能有任何按钮形态的控件
      expect(find.byType(TextButton), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      // 改为静态说明，用户无需点击即可知道价格从哪来
      expect(find.text(PreviewStrings.priceOfflineNote), findsOneWidget);
      // 没有可点击的东西 → 不可能触发回调
      await tester.tap(find.byType(PriceRefreshBar));
      expect(tapped, isFalse);
    });

    testWidgets('enabled=true：恢复按钮（OTA 接入后不得被误删）', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(PriceRefreshBar(
        loading: false,
        enabled: true,
        status: '⏳ 正在刷新',
        onRefresh: () => tapped = true,
      )));

      expect(find.byType(TextButton), findsOneWidget);
      expect(find.text(PreviewStrings.refreshPrice), findsOneWidget);
      expect(find.text('⏳ 正在刷新'), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      expect(tapped, isTrue);
    });

    testWidgets('enabled=true 且 loading：按钮在但不可点（短暂禁用，允许置灰）',
        (tester) async {
      await tester.pumpWidget(wrap(PriceRefreshBar(
        loading: true,
        enabled: true,
        status: '⏳ 正在刷新',
        onRefresh: () {},
      )));

      // loading 是"短暂"状态，与"永久无数据源"性质不同 → 保留按钮形态是对的
      expect(find.byType(TextButton), findsOneWidget);
      final btn = tester.widget<TextButton>(find.byType(TextButton));
      expect(btn.onPressed, isNull);
    });
  });

  // ==================================================================
  group('LocationCard 手填补录（已修 bug #3）', () {
    LocationCard mkCard({
      LocationType type = LocationType.hotel,
      int? manualCost,
      bool showPrice = false,
      PriceQuote? quote,
      VoidCallback? onManualCost,
    }) =>
        LocationCard(
          location: mkLoc(type: type, manualCost: manualCost),
          showPrice: showPrice,
          quote: quote,
          onTap: () {},
          onOta: () {},
          onEditStay: () {},
          onRemove: () {},
          onManualCost: onManualCost,
        );

    const pricedQuote = PriceQuote(
      kind: 'hotel',
      name: '测试点',
      city: '杭州',
      reference: PriceRange(low: 300, high: 500),
      fetchedAtText: '截至 12:00',
    );

    testWidgets('有手填：显示「手填 ¥520」', (tester) async {
      await tester.pumpWidget(wrap(
        mkCard(manualCost: 520, onManualCost: () {}),
      ));

      expect(find.textContaining('手填'), findsOneWidget);
      expect(find.textContaining('¥520'), findsOneWidget);
    });

    testWidgets('有手填时隐藏参考价徽章（互斥，防"两个数字只算一个"）',
        (tester) async {
      // showPrice=true 且 quote 有价 —— 若不加互斥，会同时出现 300–500 与 520
      await tester.pumpWidget(wrap(
        mkCard(
          manualCost: 520,
          showPrice: true,
          quote: pricedQuote,
          onManualCost: () {},
        ),
      ));

      expect(find.textContaining('手填'), findsOneWidget);
      // 参考价文案不得出现（聚合器已跳过了它，卡片若还显示就会对不上账）
      expect(find.textContaining('参考价 ¥300'), findsNothing);
    });

    testWidgets('无手填 + showPrice=true：显示参考价徽章', (tester) async {
      await tester.pumpWidget(wrap(
        mkCard(showPrice: true, quote: pricedQuote, onManualCost: () {}),
      ));

      expect(find.textContaining('参考价'), findsOneWidget);
      expect(find.textContaining('手填'), findsNothing);
    });

    testWidgets('酒店无手填 + showPrice=false：不渲染任何价格区（非关键缺失不展示）',
        (tester) async {
      await tester.pumpWidget(wrap(mkCard(onManualCost: () {})));

      // 评审「缺失分层」：酒店本轮无数据源，不该输出「暂无参考价」噪音
      expect(find.text(PreviewStrings.priceAbsent), findsNothing);
      expect(find.textContaining('¥'), findsNothing);
    });

    testWidgets('入口文案随有无手填切换，且点击触发回调', (tester) async {
      var fired = 0;

      // 未填 → 「补录金额」
      await tester.pumpWidget(wrap(
        mkCard(onManualCost: () => fired++),
      ));
      expect(find.text(PreviewStrings.manualCostAdd), findsOneWidget);
      await tester.tap(find.text(PreviewStrings.manualCostAdd));
      expect(fired, 1);

      // 已填 → 「改金额」
      await tester.pumpWidget(wrap(
        mkCard(manualCost: 520, onManualCost: () => fired++),
      ));
      expect(find.text(PreviewStrings.manualCostEdit), findsOneWidget);
      await tester.tap(find.text(PreviewStrings.manualCostEdit));
      expect(fired, 2);
    });

    testWidgets('onManualCost 为 null：不渲染补录入口', (tester) async {
      await tester.pumpWidget(wrap(mkCard()));

      expect(find.text(PreviewStrings.manualCostAdd), findsNothing);
      expect(find.text(PreviewStrings.manualCostEdit), findsNothing);
    });
  });

  // ==================================================================
  group('CostAggregator 手填补录（已修 bug #4）', () {
    test('酒店手填：绕过 supports() 正常计入（关键回归）', () {
      final hotel = mkLoc(type: LocationType.hotel, manualCost: 520);
      // 前提校验：酒店确实不被数据源支持
      expect(src.supports(hotel), isFalse);

      final cost = CostAggregator.aggregateDay(
        mkDay([hotel]),
        mkTrip(),
        const {},
        src,
      );

      // 若手填判断被误挪到 supports() 之后，这里会是 0 且**没有任何报错**
      expect(cost.low, 520);
      expect(cost.high, 520);
      expect(cost.lines.single.source, CostSource.manual);
      expect(cost.lines.single.source.label, '手填');
    });

    test('景点手填：同样绕过 supports()', () {
      final cost = CostAggregator.aggregateDay(
        mkDay([mkLoc(type: LocationType.attraction, manualCost: 60)]),
        mkTrip(),
        const {},
        src,
      );
      expect(cost.low, 60);
    });

    test('手填**不乘人数**（语义是该项总价）', () {
      final cost = CostAggregator.aggregateDay(
        mkDay([mkLoc(type: LocationType.hotel, manualCost: 520)]),
        mkTrip(adults: 3, children: 1), // 4 人
        const {},
        src,
      );
      // 520 是"一晚房费总价"，不是"520/人"；乘 4 得到 2080 是错的
      expect(cost.low, 520);
    });

    test('手填优先于参考价，不重复计入', () {
      // 餐饮既有 cost 又有手填 → 只算手填
      final cost = CostAggregator.aggregateDay(
        mkDay([mkLoc(type: LocationType.restaurant, cost: '100', manualCost: 260)]),
        mkTrip(adults: 2),
        const {},
        src,
      );
      expect(cost.low, 260);
      expect(cost.high, 260);
      expect(cost.lines.length, 1);
      expect(cost.lines.single.source, CostSource.manual);
    });

    test('手填与餐饮混合：分别累加，来源各自保留', () {
      final cost = CostAggregator.aggregateDay(
        mkDay([
          mkLoc(type: LocationType.restaurant, cost: '100', name: '午餐'),
          mkLoc(type: LocationType.hotel, manualCost: 520, name: '酒店'),
        ]),
        mkTrip(adults: 2),
        const {},
        src,
      );

      // 餐饮 100×2=200 + 酒店手填 520 = 720
      expect(cost.low, 720);
      expect(cost.high, 720);
      final kinds = cost.lines.map((l) => l.source).toSet();
      expect(kinds, contains(CostSource.dining));
      expect(kinds, contains(CostSource.manual));
      // 来源透明：副行必须说明混了手填
      expect(cost.scopeText, contains('含手填'));
    });

    test('无手填时副行不带「含手填」', () {
      final cost = CostAggregator.aggregateDay(
        mkDay([mkLoc(type: LocationType.restaurant, cost: '100')]),
        mkTrip(),
        const {},
        src,
      );
      expect(cost.scopeText, isNot(contains('含手填')));
    });

    test('手填不计入 missingCount（它不是"取不到价"）', () {
      final cost = CostAggregator.aggregateDay(
        mkDay([
          mkLoc(type: LocationType.hotel, manualCost: 520),
          mkLoc(type: LocationType.restaurant, cost: null, name: '无价餐饮'),
        ]),
        mkTrip(),
        const {},
        src,
      );
      // 只有那条没价的餐饮算缺失，手填的酒店不算
      expect(cost.missingCount, 1);
    });
  });

  // ==================================================================
  group('Location.manualCost 序列化（云同步往返）', () {
    test('toJson / fromJson 往返一致', () {
      final loc = mkLoc(type: LocationType.hotel, manualCost: 520);
      final back = Location.fromJson(loc.toJson());
      expect(back.manualCost, 520);
      expect(back.name, loc.name);
    });

    test('旧数据缺 manualCost 字段 → null（不抛异常）', () {
      final json = mkLoc(type: LocationType.hotel).toJson();
      json.remove('manualCost');
      expect(Location.fromJson(json).manualCost, isNull);
    });

    test('JSON 里带小数 → round 成 int（不抛类型错误）', () {
      final json = mkLoc(type: LocationType.hotel).toJson();
      json['manualCost'] = 519.6;
      expect(Location.fromJson(json).manualCost, 520);
    });

    test('manualCost 为 null 与 0 语义不同', () {
      final none = Location.fromJson(
        mkLoc(type: LocationType.hotel).toJson(),
      );
      final zero = Location.fromJson(
        (mkLoc(type: LocationType.hotel, manualCost: 0)).toJson(),
      );
      expect(none.manualCost, isNull); // 未补录
      expect(zero.manualCost, 0); // 用户明确填了"这项没花钱"
    });
  });

  // ==================================================================
  // T04：三级提示渲染契约
  //
  // 锁死「改 UI 但没防线」的缺口：红框只属于 blocking、提醒不描边、
  // 同地点一条、营业问题带原文副行。这四条一旦回归就是**用户可见的错误**
  // （把"需留意"渲染成"排不下"，或把未取到营业时间渲染成"已通过"）。
  // ==================================================================
  group('LocationCard 三级提示（T04）', () {
    Location poi({
      String name = '故宫',
      String? openTime,
      String? closeTime,
      String? lastEntryTime,
      bool? closedOnDate,
      String? openHoursRaw,
    }) =>
        Location(
          name: name,
          address: '北京市东城区',
          type: LocationType.attraction,
          openTime: openTime,
          closeTime: closeTime,
          lastEntryTime: lastEntryTime,
          closedOnDate: closedOnDate,
          openHoursRaw: openHoursRaw,
          stayMinutes: 120,
        );

    Widget card(Location loc, ItineraryIssue? issue) => wrap(
          LocationCard(
            location: loc,
            showPrice: false,
            issue: issue,
            onTap: () {},
            onOta: () {},
            onEditStay: () {},
            onRemove: () {},
          ),
        );

    /// 卡片外框（唯一带 `Border` 的 Container 就是卡片本体）
    Border? borderOf(WidgetTester tester) {
      for (final c in tester.widgetList<Container>(find.byType(Container))) {
        final d = c.decoration;
        if (d is BoxDecoration && d.border is Border) return d.border as Border;
      }
      return null;
    }

    const blocking = ItineraryIssue(
      code: ItineraryIssueCode.ch01LateEntry,
      severity: IssueSeverity.blocking,
      dayNumber: 1,
      locationId: 'x',
      message: '16:50 到达晚于停止入场 16:00，无法入园',
      sourceRaw: '08:30-17:00，16:00 停止检票',
    );
    const reminder = ItineraryIssue(
      code: ItineraryIssueCode.ch02EarlyArrival,
      severity: IssueSeverity.reminder,
      dayNumber: 1,
      locationId: 'x',
      message: '08:05 到达早于 08:30 开门，需等 25 分钟',
      sourceRaw: '08:30-17:00',
    );

    testWidgets('blocking：描红边 + 显示提示行', (tester) async {
      await tester.pumpWidget(card(poi(), blocking));

      final border = borderOf(tester);
      expect(border, isNotNull);
      expect(border!.top.color, PreviewColors.conflictBorder);
      expect(border.top.width, 1.5);
      expect(find.byType(IssueNote), findsOneWidget);
      expect(find.text('16:50 到达晚于停止入场 16:00，无法入园'), findsOneWidget);
    });

    testWidgets('reminder：**不描边**，只有提示行（灰底橙字）', (tester) async {
      await tester.pumpWidget(card(poi(), reminder));

      final border = borderOf(tester);
      expect(border, isNotNull);
      expect(border!.top.color, PreviewColors.line);
      expect(border.top.width, 1);
      expect(find.byType(IssueNote), findsOneWidget);
      expect(find.text('08:05 到达早于 08:30 开门，需等 25 分钟'), findsOneWidget);
    });

    testWidgets('同地点只渲染一条提示（去重已在 checker 完成，widget 不再判断）',
        (tester) async {
      await tester.pumpWidget(card(poi(), blocking));

      // 卡片拿到的是**单条** issue，不存在第二条
      expect(find.byType(IssueNote), findsOneWidget);
    });

    testWidgets('营业问题的原文副行：原样切片，不反拼', (tester) async {
      final p = poi(openTime: '08:30', closeTime: '17:00', lastEntryTime: '16:00', closedOnDate: false, openHoursRaw: '08:30-17:00，16:00 停止检票');
      await tester.pumpWidget(card(p, blocking));

      expect(find.text('原文：08:30-17:00，16:00 停止检票'), findsOneWidget);
      // 结构化值照常显示在 meta（营业/停止入场），与原文副行**互不替代**
      expect(find.textContaining('营业 08:30-17:00'), findsOneWidget);
      // meta 与提示主句都会出现"停止入场 16:00"（两处在说同一事实，不是重复问题）
      expect(find.textContaining('停止入场 16:00'), findsWidgets);
    });

    testWidgets('无 issue：不渲染任何提示，也不渲染"已校验通过"', (tester) async {
      await tester.pumpWidget(card(poi(), null));

      expect(find.byType(IssueNote), findsNothing);
      expect(find.textContaining('已校验通过'), findsNothing);
      expect(find.textContaining('校验通过'), findsNothing);
      final border = borderOf(tester);
      expect(border!.top.color, PreviewColors.line);
    });

    testWidgets('无营业时间时 meta 不出现"营业 null"这类脏片段', (tester) async {
      // 多时段 / 解析失败 → openTime/closeTime 全 null；此时 meta **不写**营业段
      await tester.pumpWidget(card(poi(), null));

      expect(find.textContaining('营业'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
    });
  });

  // ==================================================================
  // P1 质量防线·补强：LocationCard 关键字段渲染 + 异常数据
  //
  // 评审 §九 要求时间线组件具备「关键渲染 + 异常数据」测试防线。
  // 现有本文件的 4 组锁的是**价格层**与**三级提示层**，而信息最密集、
  // 最易「显示错」的 `_metaText`（城市·地址 / 到达 / 停留 / 营业 / 交通时长 /
  // 班次票价）此前**零覆盖**。红线：宁可少显示，不可显示错——下列异常用例
  // 就是锁「缺失不编造、解析失败不吐脏片段、票价缺失不显示 ¥0」。
  // ==================================================================
  group('LocationCard 关键字段渲染 + 异常数据（评审 P1 质量防线）', () {
    Widget card2(Location loc, {int peopleCount = 1, bool showPrice = false}) =>
        wrap(LocationCard(
          location: loc,
          showPrice: showPrice,
          peopleCount: peopleCount,
          onTap: () {},
          onOta: () {},
          onEditStay: () {},
          onRemove: () {},
        ));

    final taxi30 = Transport(
      type: TransportType.taxi,
      scope: TransportScope.intraCity,
      durationMinutes: 30,
      distance: 5000,
    );

    testWidgets('关键渲染：meta 含 城市·地址 / 到达 / 停留 / 营业 / 交通',
        (tester) async {
      final loc = Location(
        name: '西湖餐厅',
        address: '西湖区南山路',
        type: LocationType.restaurant,
        city: '杭州',
        arrivalTime: '09:00',
        stayMinutes: 120,
        openTime: '08:00',
        closeTime: '22:00',
        transport: taxi30,
      );
      await tester.pumpWidget(card2(loc));

      final meta = metaOf(tester);
      expect(meta, isNotNull);
      expect(meta, contains('杭州 · 西湖区南山路')); // 多城同名区分（TL-10）
      expect(meta, contains('09:00'));
      expect(meta, contains('停留2小时'));
      expect(meta, contains('营业 08:00-22:00'));
      expect(meta, contains('打车')); // 交通方式标签（displayName）
      expect(meta, contains('30分钟')); // 交通时长
    });

    testWidgets('关键渲染：餐饮人均价 chip 显示「人均 ¥150」', (tester) async {
      final loc = Location(
        name: '午餐',
        address: '',
        type: LocationType.restaurant,
        city: '杭州',
        cost: '150',
      );
      await tester.pumpWidget(card2(loc));

      expect(find.textContaining('¥150'), findsOneWidget);
    });

    testWidgets('异常·缺失交通：transport==null → meta 不出现时长/里程/班次',
        (tester) async {
      final loc = Location(
        name: '无交通点',
        address: '',
        type: LocationType.attraction,
        city: '杭州',
        arrivalTime: '10:00',
        // 故意不传 transport
      );
      await tester.pumpWidget(card2(loc));

      final meta = metaOf(tester)!;
      expect(meta, contains('杭州 · 10:00'));
      expect(meta.contains('分钟'), isFalse); // 不显示伪造的「28分钟」
      expect(meta.contains('km'), isFalse);
      expect(meta.contains('→'), isFalse);
      expect(meta.contains('班次'), isFalse);
    });

    testWidgets('异常·停留0分钟：stayMinutes==0 → meta 不出现「停留」时长',
        (tester) async {
      final loc = Location(
        name: '瞬时点',
        address: '',
        type: LocationType.attraction,
        city: '杭州',
        arrivalTime: '10:00',
        stayMinutes: 0,
      );
      await tester.pumpWidget(card2(loc));

      // 只断言 meta 内不含停留时长片段（操作区「调整停留」不在 meta 里）
      final meta = metaOf(tester)!;
      expect(meta.contains('停留'), isFalse);
    });

    testWidgets('异常·营业解析失败：openTime/closeTime 全 null → 不吐脏片段',
        (tester) async {
      final loc = Location(
        name: '无营业点',
        address: '',
        type: LocationType.attraction,
        city: '杭州',
        arrivalTime: '10:00',
        // 多时段 / 解析失败 → openTime/closeTime 全 null
      );
      await tester.pumpWidget(card2(loc));

      final meta = metaOf(tester)!;
      expect(meta.contains('营业'), isFalse);
      expect(meta.contains('null'), isFalse);
    });

    testWidgets('异常·班次票价缺失：transport.price==null → 不显示 ¥0/暂无票价',
        (tester) async {
      final loc = Location(
        name: '有交通无票价',
        address: '',
        type: LocationType.attraction,
        city: '杭州',
        transport: Transport(
          type: TransportType.taxi,
          scope: TransportScope.intraCity,
          durationMinutes: 30,
          // 无 price
        ),
      );
      await tester.pumpWidget(card2(loc, showPrice: false));

      // showPrice=false 且无手填 → 整卡不应出现任何 ¥（票价缺失即留空，不编造）
      expect(find.textContaining('¥'), findsNothing);
      final meta = metaOf(tester)!;
      expect(meta.contains('分钟'), isTrue); // 时长仍正常显示
      expect(meta.contains('¥'), isFalse);
    });

    testWidgets('关键·班次票价展示 ¥553×2（按人数，不乘房间）', (tester) async {
      final loc = Location(
        name: '高铁站',
        address: '',
        type: LocationType.transport,
        city: '北京',
        transport: Transport(
          type: TransportType.highSpeedTrain,
          scope: TransportScope.intercity,
          durationMinutes: 20,
          price: 553,
        ),
      );
      await tester.pumpWidget(card2(loc, peopleCount: 2));

      final meta = metaOf(tester)!;
      expect(meta.contains('¥553×2'), isTrue);
    });

    testWidgets('异常·餐饮人均价缺失：cost 为空 → 不留占位 chip', (tester) async {
      final loc = Location(
        name: '无价餐饮',
        address: '',
        type: LocationType.restaurant,
        city: '杭州',
        cost: null,
      );
      await tester.pumpWidget(card2(loc, showPrice: false));

      expect(find.textContaining('人均'), findsNothing); // 不留占位（占位=编造）
      expect(find.textContaining('¥'), findsNothing);
    });

    testWidgets('关键渲染：交通型地点 里程 chip 显示「5km」', (tester) async {
      final loc = Location(
        name: '打车段',
        address: '',
        type: LocationType.transport,
        city: '杭州',
        transport: Transport(
          type: TransportType.taxi,
          scope: TransportScope.intraCity,
          durationMinutes: 15,
          distance: 5000,
        ),
      );
      await tester.pumpWidget(card2(loc));

      // 里程只在「地点类型为 transport」时走 chip（chipText 按 loc.type 分支）
      expect(find.textContaining('5km'), findsOneWidget);
    });
  });

  // ==================================================================
  // P1 质量防线·补强：跨午夜「次日」展示契约（异常数据）
  //
  // 内部比较一律用未 mod 1440 的整数分钟，唯一允许表达「次日」的是
  // [formatClockMinutes]（itinerary_checker.dart:289）。一旦回归成
  // `% 1440` 再显示，1500 分钟（次日 01:00）会被错显成「01:00」，
  // 直接违反「宁可少显示不可显示错」。此处锁死契约。
  // ==================================================================
  group('formatClockMinutes 跨午夜次日契约', () {
    test('1500 分钟 → 次日 01:00（不绕回成 01:00）', () {
      expect(formatClockMinutes(1500), '次日 01:00');
    });
    test('1440 分钟 → 次日 00:00', () {
      expect(formatClockMinutes(1440), '次日 00:00');
    });
    test('90 分钟 → 01:30（未跨天不加次日）', () {
      expect(formatClockMinutes(90), '01:30');
    });
    test('1439 分钟 → 23:59', () {
      expect(formatClockMinutes(1439), '23:59');
    });
    test('0 分钟 → 00:00', () {
      expect(formatClockMinutes(0), '00:00');
    });
  });
}
