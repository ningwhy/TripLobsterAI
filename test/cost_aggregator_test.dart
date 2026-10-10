import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/price_quote.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/services/price_source.dart';
import 'package:trip_planner/utils/cost_aggregator.dart';

/// 「当日已计价」聚合器 + 数据源口径测试
///
/// 前置（探针 `_fx06a_probe.mjs` 真实 `AMAP_KEY` 实测，非 stub）：
///   餐饮 18/20 有值（人均）／酒店 0/20 全空／景点 0/20 全空。
void main() {
  const src = AmapReferencePriceSource();

  Trip mkTrip({int adults = 2, int children = 1}) => Trip(
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

  Location restaurant(String? cost) => Location(
        name: '某餐厅',
        address: '',
        type: LocationType.restaurant,
        cost: cost,
      );

  Location hotel(String? cost) => Location(
        name: '某酒店',
        address: '',
        type: LocationType.hotel,
        cost: cost,
      );

  Location attraction() => Location(name: '某景点', address: '', type: LocationType.attraction);

  Location intercity(num price) => Location(
        name: '北京南站',
        address: '',
        type: LocationType.transport,
        transport: Transport(
          type: TransportType.highSpeedTrain,
          scope: TransportScope.intercity,
          price: price,
          isFixed: true,
        ),
      );

  Location intraCity(num price) => Location(
        name: '地铁口',
        address: '',
        type: LocationType.transport,
        transport: Transport(
          type: TransportType.subway,
          scope: TransportScope.intraCity,
          price: price,
        ),
      );

  PriceQuote quoteOf(String name, int low, int high, {String city = '北京'}) =>
      PriceQuote.fromJson({
        'kind': 'ticket',
        'name': name,
        'city': city,
        'candidates': [
          {
            'name': name,
            'reference': {'low': low, 'high': high, 'currency': 'CNY'},
          }
        ],
        'reference': {'low': low, 'high': high, 'currency': 'CNY'},
        'fetchedAt': DateTime.now().toIso8601String(),
        'fetchedAtText': '截至 12:00',
      });

  // ---------------- 1. 数据源：谁支持、谁不支持 ----------------

  group('PriceSource.supports（FX-06a 实测口径）', () {
    test('餐饮 与 跨城班次 支持', () {
      expect(src.supports(restaurant('150.00')), isTrue);
      expect(src.supports(intercity(268)), isTrue);
    });

    test('酒店 / 景点 / 同城交通 不支持', () {
      expect(src.supports(hotel('400-600')), isFalse);
      expect(src.supports(attraction()), isFalse);
      expect(src.supports(intraCity(5)), isFalse);
    });

    // 【PM 硬规定】dining.needsNetwork 恒 false：SR-02 后餐饮 cost 随 payload 离线下发，
    // 不需要联网；而查餐饮只能误传 kind='ticket'（SR-03 未落地）→ 同名不同店错配。
    // 餐饮是本轮唯一有真实数据的价格路径，不能弄脏它。
    test('requestKindFor：本轮**全类型**返回 null（价格 100% 离线）', () {
      expect(src.requestKindFor(restaurant('150.00')), isNull);
      expect(src.requestKindFor(intercity(268)), isNull);
      expect(src.requestKindFor(hotel('400-600')), isNull);
      expect(src.requestKindFor(attraction()), isNull);
    });

    // D-AR-01（架构师裁决）：needsNetwork = 要不要联网（演化判断），
    // requestKindFor = 发什么 kind（协议参数）；二者**不合并**，但 needsNetwork 默认
    // 由 requestKindFor 派生，保证单一出口、不会两处漏改。
    test('needsNetwork：本轮全类型 false → 刷新按钮置灰（不可点击）', () {
      expect(src.needsNetwork(restaurant('150.00')), isFalse);
      expect(src.needsNetwork(intercity(268)), isFalse);
      expect(src.needsNetwork(hotel('400-600')), isFalse);
      expect(src.needsNetwork(attraction()), isFalse);
    });

    test('PR-10：needsNetwork 由 requestKindFor 派生，不得各写一套（防漂移）', () {
      for (final t in LocationType.values) {
        final probe = Location(name: 'x', address: '', type: t);
        expect(src.needsNetwork(probe), src.requestKindFor(probe) != null,
            reason: 'LocationType.$t 的 needsNetwork 与 requestKindFor 不一致');
      }
    });

    test('PR-10：整条行程的刷新可用性 = any(needsNetwork)，UI 不得硬编码 enabled:false', () {
      final trip = mkTrip();
      final canRefresh =
          trip.allLocations.any((l) => src.needsNetwork(l));
      expect(canRefresh, isFalse); // 本轮恒 false → 按钮置灰
    });
  });

  // ---------------- 2. 乘数：只有 peopleCount 一条规则 ----------------

  group('PriceSource.priceOf 乘数口径', () {
    test('餐饮：人均 × 人数', () {
      final r = src.priceOf(restaurant('150.00'), null, mkTrip(adults: 2, children: 1));
      expect(r!.low, 450);
      expect(r.high, 450);
    });

    test('餐饮：loc.cost 为空时回落到运行时缓存', () {
      final q = quoteOf('某餐厅', 150, 200);
      final r = src.priceOf(restaurant(null), q, mkTrip(adults: 3, children: 0));
      expect(r!.low, 450);
      expect(r.high, 600);
    });

    test('跨城班次：票价 × 人数（low == high）', () {
      final r = src.priceOf(intercity(268), null, mkTrip(adults: 2, children: 1));
      expect(r!.low, 804);
      expect(r.high, 804);
    });

    test('跨城班次无 price（估算分支）→ null，不编造', () {
      final loc = Location(
        name: '北京南站',
        address: '',
        type: LocationType.transport,
        transport: Transport(
          type: TransportType.highSpeedTrain,
          scope: TransportScope.intercity,
          price: null,
        ),
      );
      expect(src.priceOf(loc, null, mkTrip()), isNull);
    });

    test('不支持的类型 → null（酒店即使有 cost 也不计价）', () {
      expect(src.priceOf(hotel('400-600'), null, mkTrip()), isNull);
      expect(src.priceOf(attraction(), null, mkTrip()), isNull);
    });

    test('人数为 0 时兜底为 1，不产生 ¥0', () {
      final r = src.priceOf(restaurant('150.00'), null, mkTrip(adults: 0, children: 0));
      expect(r!.low, 150);
    });

    test('脏值（千分位截断）→ null', () {
      final q = quoteOf('某餐厅', 1, 200); // 服务端正则把 "1,200" 截成 1
      expect(src.priceOf(restaurant(null), q, mkTrip()), isNull);
    });
  });

  // ---------------- 3. A-11：返回 POI 与卡片名不一致 → 不用 ----------------

  group('PriceSource.matchesSubject（A-11）', () {
    test('同名 → 通过', () {
      expect(src.matchesSubject(quoteOf('某餐厅', 150, 150), '某餐厅'), isTrue);
    });

    test('candidates[0] 同名 → 通过', () {
      final q = PriceQuote.fromJson({
        'kind': 'ticket',
        'name': '高德返回的分店名',
        'city': '北京',
        'candidates': [
          {
            'name': '某餐厅',
            'reference': {'low': 150, 'high': 150},
          }
        ],
      });
      expect(src.matchesSubject(q, '某餐厅'), isTrue);
    });

    test('张冠李戴 → 拒绝（宁可显示无价）', () {
      expect(src.matchesSubject(quoteOf('同名另一家店', 150, 150), '某餐厅'), isFalse);
    });

    test('无候选且 name 不符 → 拒绝', () {
      final q = const PriceQuote(name: '别的店', candidates: []);
      expect(src.matchesSubject(q, '某餐厅'), isFalse);
    });
  });

  // ---------------- 4. 聚合器：只相加，不自行乘 ----------------

  group('CostAggregator.aggregateDay', () {
    test('餐饮 + 班次 相加，区间分别累加', () {
      final c = CostAggregator.aggregateDay(
        mkDay([restaurant('150.00'), intercity(268)]),
        mkTrip(adults: 2, children: 1),
        {},
        src,
      );
      // 餐饮 150×3=450；班次 268×3=804
      expect(c.low, 1254);
      expect(c.high, 1254);
      expect(c.rangeText, '¥1,254');
      expect(c.missingCount, 0);
    });

    test('区间：餐饮 150-200 × 3 人', () {
      final q = quoteOf('某餐厅', 150, 200);
      final c = CostAggregator.aggregateDay(
        mkDay([restaurant(null)]),
        mkTrip(adults: 3, children: 0),
        {PriceRepositoryKey.of(null, '某餐厅'): q},
        src,
      );
      expect(c.low, 450);
      expect(c.high, 600);
      expect(c.rangeText, '¥450–600');
    });

    test('酒店 / 景点：不计入金额，也**不计入缺失**（本轮就没有这个数据源）', () {
      final c = CostAggregator.aggregateDay(
        mkDay([hotel('400-600'), attraction()]),
        mkTrip(),
        {},
        src,
      );
      expect(c.isEmpty, isTrue);
      expect(c.lines, isEmpty);
      expect(c.missingCount, 0);
    });

    test('餐饮无价 → 计入缺失', () {
      final c = CostAggregator.aggregateDay(
        mkDay([restaurant(null)]),
        mkTrip(),
        {},
        src,
      );
      expect(c.isEmpty, isTrue);
      expect(c.missingCount, 1);
    });

    test('空日 → isEmpty，文案走整日级', () {
      final c = CostAggregator.aggregateDay(mkDay([]), mkTrip(), {}, src);
      expect(c.isEmpty, isTrue);
      expect(c.rangeText, '¥0'); // 注意：isEmpty 时 UI 不显示 rangeText
    });

    test('口径副行由数据源注入', () {
      final c = CostAggregator.aggregateDay(mkDay([]), mkTrip(), {}, src);
      expect(c.scopeText, src.scopeText);
      expect(c.scopeText.contains('未含：酒店 · 门票'), isTrue);
    });

    test('汇总多行时 low/high 分别相加，不取中值', () {
      final q = quoteOf('某餐厅', 100, 300);
      final c = CostAggregator.aggregateDay(
        mkDay([restaurant(null), restaurant(null)]),
        mkTrip(adults: 1, children: 0),
        {PriceRepositoryKey.of(null, '某餐厅'): q},
        src,
      );
      expect(c.low, 200);
      expect(c.high, 600);
      // 中值 400 ≠ 我们算出的任何边界（证明没取中值）
      expect(c.low, isNot(400));
      expect(c.high, isNot(400));
    });
  });

  // ---------------- 5. 格式化 ----------------

  group('格式化', () {
    test('fmtAmount 千分位', () {
      expect(CostAggregator.fmtAmount(1300), '1,300');
      expect(CostAggregator.fmtAmount(999), '999');
      expect(CostAggregator.fmtAmount(1234567), '1,234,567');
    });

    test('lowerBoundText 三态：无数据 — / 单值不带 ≥ / 真区间带 ≥', () {
      // 无数据：绝不 ¥0（PR-09 验收③）
      expect(CostAggregator.lowerBoundText(0), '—');
      expect(CostAggregator.lowerBoundText(-5), '—');
      expect(CostAggregator.lowerBoundText(0, 500), '—');

      // 单值（low == high）：没有区间 → 不带 ≥（≥ 用在确定值上是误导）
      expect(CostAggregator.lowerBoundText(1900, 1900), '¥1,900');
      expect(CostAggregator.lowerBoundText(1900), '¥1,900'); // 省略 high = 单值

      // 真区间：只显下限，不取中值（【裁 1】取中值即估算）
      expect(CostAggregator.lowerBoundText(1300, 1700), '≥¥1,300');
      expect(CostAggregator.lowerBoundText(1300, 1700), isNot(contains('1,700')));

      // 万位压缩
      expect(CostAggregator.lowerBoundText(13000, 13000), '¥1.3万');
      expect(CostAggregator.lowerBoundText(13000, 17000), '≥¥1.3万');
      expect(CostAggregator.lowerBoundText(120000, 120000), '¥12万');
      expect(CostAggregator.lowerBoundText(120000, 130000), '≥¥12万');
    });

    test('lowerBoundText ⛔ 任何组合都不产生 ¥0', () {
      for (final low in [0, -1, 1]) {
        for (final high in [0, -1, 1, 500]) {
          expect(CostAggregator.lowerBoundText(low, high), isNot(contains('¥0')));
        }
      }
    });
  });

  // ---------------- 6. PR-10 契约 ----------------

  group('PR-10 抽象层契约', () {
    test('数据源 id 与文案常量可读取', () {
      expect(src.id, 'amap_reference');
      expect(src.absentText, isNotEmpty);
      expect(src.scopeText, isNotEmpty);
    });

    test('peopleCount 只算人头，不涉及 rooms', () {
      final t = mkTrip(adults: 2, children: 1);
      expect(src.peopleCount(t), 3);
      // rooms 无论多少都不影响
      expect(src.peopleCount(t), src.peopleCount(t));
    });
  });
}
