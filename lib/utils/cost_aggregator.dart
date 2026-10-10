import '../models/price_quote.dart';
import '../models/trip_models.dart';
import '../services/price_source.dart';

/// 「当日已计价」聚合器（纯函数：零 IO、零硬编码、**零乘数**，可单测）
///
/// ## 本文件不做什么（PR-10 硬约束）
/// - ❌ **不做任何乘法** —— 乘数与数据源语义全部归 `PriceSource.priceOf()`
/// - ❌ **不出现 `rooms`** —— 房间数不得进入计价路径（"人均"与"每间夜"是两套语义）
/// - ❌ **不出现 0.6 / 0.12 / 0.45 / 300 / 600**（M6b：客户端不做油/电/过路估算）
/// - ❌ **不取中值**（【裁 1】：取中值即估算）
///
/// 本文件只做三件事：问 `source.priceOf()` → 区间分别相加 → 空则降级。
///
/// ## 可归集来源（FX-06a 探针实测后的真实口径）
///
/// | 来源 | 口径 | 实测可用性 |
/// |---|---|---|
/// | 餐饮 | 人均 `cost` × 人数 | ✅ 18/20 有值，**随行程 payload 离线下发**（SR-02：`planner.js` `normalizePoi()` 把 `biz_ext.cost` 归一后由 `toLocation()` 透传），**0 次价格请求** |
/// | 跨城班次 | `transport.price` × 人数 | ✅ 随行程 payload 下发，0 次请求 |
/// | 酒店 | —— | ❌ 0/20 全空 → `supports()==false`，不请求不渲染 |
/// | 景点 | —— | ❌ 0/20 全空 → `supports()==false`，不请求不渲染 |
///
/// 【口径修正记录】此前本表写「餐饮需用户点刷新，服务端不下发」，与 SR-02 事实冲突。
/// 该错误认知已连续三次导致误判（"TTL 是摆设" / "酒店有价" / "餐饮要联网"），
/// 故在此显式写明：**餐饮价格随 payload 下发，点刷新也不会改变它**。
///
/// 明确排除：油 / 电 / 过路 / 租车 / 包车（需按里程估算 → 严禁）。
/// 可归集价格的三类来源
///
/// 【来源透明】评审要求的第三层：区分「来源参考金额」/「用户手填金额」/
/// 「已确认订单金额」。本轮只实现前两类，故枚举成员即全部来源，
/// UI 侧按 `label` 区分，不得把不同来源的数字混成一个不说明来历的合计。
enum CostSource { dining, intercity, manual }

extension CostSourceLabel on CostSource {
  String get label => switch (this) {
        CostSource.dining => '餐饮',
        CostSource.intercity => '交通班次',
        // 「手填」而非「用户填写」：副行空间只有两个字的位置，
        // 且「手填」已足以表达"这个数不是我们算的"
        CostSource.manual => '手填',
      };
}

/// 一行可归集价格（不含文案 —— 文案由 `PriceSource` / `PreviewStrings` 统一提供）
class CostLine {
  final int low;
  final int high;
  final CostSource source;

  const CostLine({
    required this.low,
    required this.high,
    required this.source,
  });
}

/// 某一天的聚合结果（运行时，不落库 —— PRD TL-07）
class DayCost {
  final int low;
  final int high;
  final List<CostLine> lines;

  /// 该日"本数据源支持但取不到价"的条目数（用于全行程脚注）
  final int missingCount;

  /// 口径说明（常驻副行），由 `PriceSource.scopeText` 注入
  final String scopeText;

  const DayCost({
    this.low = 0,
    this.high = 0,
    this.lines = const <CostLine>[],
    this.missingCount = 0,
    this.scopeText = '',
  });

  /// 无任何可归集价格 → UI 显示**整日级**文案 `暂无可计价数据`
  ///
  /// ⚠️ 绝**不**显示 `¥0`，也**不**显示 `¥—`（那属估算占位，PRD v1.5 PR-09 验收③）。
  bool get isEmpty => low == 0 && high == 0;

  /// 区间文案：`¥1,300–1,700`（单值时 `¥1,300`）
  String get rangeText => low == high
      ? '¥${CostAggregator.fmtAmount(low)}'
      : '¥${CostAggregator.fmtAmount(low)}–${CostAggregator.fmtAmount(high)}';
}

/// 「当日已计价」聚合器（静态纯函数）
class CostAggregator {
  CostAggregator._();

  /// 聚合某一天
  ///
  /// - [quotes] 运行时价格缓存（key = `price:{city}:{name}`），首屏通常为空
  /// - [source] 价格数据源；**所有乘法与"是否支持"判定都由它决定**
  static DayCost aggregateDay(
    TripDay day,
    Trip trip,
    Map<String, PriceQuote> quotes,
    PriceSource source,
  ) {
    final lines = <CostLine>[];
    var missing = 0;

    for (final loc in day.locations) {
      // 【手填优先，且必须在 `supports()` 之前】
      //
      // 位置是有意的，且**不能挪到 supports() 之后**：
      // 酒店/景点 `supports()` 恒 false（源头 0/20 无数据），而它们恰恰是用户
      // 最可能手填的两类（订完酒店知道自己付了多少）。若放在 supports() 之后，
      // 手填金额会被静默丢弃 —— 本功能等于白做，且没有任何报错，是最难查的那类 bug。
      //
      // 语义上也应优先：手填是**已发生的真实支出**，参考价只是"大约"，
      // 两者冲突时真实支出更可信。（本轮二者不会同时存在，但优先级要先定死。）
      //
      // ⛔ **不乘人数**：manualCost 是该项总价（见字段注释），
      //    乘人数会与餐饮/交通的"人均×人数"口径混在一起。
      final manual = loc.manualCost;
      if (manual != null && manual >= 0) {
        lines.add(CostLine(low: manual, high: manual, source: CostSource.manual));
        continue;
      }

      // 酒店 / 景点等不支持的类型：不请求、不渲染、也**不计入缺失**
      // （它们不是"取不到价"，而是"本轮本就没有这个数据源"，写进缺失项会误导用户）
      if (!source.supports(loc)) continue;

      final quote = quotes[PriceRepositoryKey.of(loc.city, loc.name)];
      final r = source.priceOf(loc, quote, trip);
      if (r == null) {
        missing++;
        continue;
      }
      lines.add(CostLine(low: r.low, high: r.high, source: kindOf(loc)));
    }

    var low = 0;
    var high = 0;
    for (final l in lines) {
      low += l.low;
      high += l.high;
    }
    // 【来源透明】只要当天的数字里混有手填项，口径副行就必须显式带上「含手填」。
    //
    // 不加会怎样：用户看到「当日已计价 ¥2,340」，却无法分辨其中 520 是自己填的
    // 酒店钱、1,820 是我们算的餐饮参考价 —— 两类可信度完全不同的数字被合成一个，
    // 正是评审指出的「来源不透明」。副行是唯一能说清这件事的位置。
    var scope = source.scopeText;
    if (lines.any((l) => l.source == CostSource.manual) && scope.isNotEmpty) {
      scope = '$scope · 含手填';
    }

    return DayCost(
      low: low,
      high: high,
      lines: lines,
      missingCount: missing,
      scopeText: scope,
    );
  }

  /// 某地点在聚合里的归类（跨城班次票价挂在 transport 上，其余按餐饮）
  static CostSource kindOf(Location loc) =>
      PriceSource.isIntercity(loc) ? CostSource.intercity : CostSource.dining;

  /// 金额千分位：`1300 → 1,300`
  static String fmtAmount(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$buf';
  }

  /// 日期条格子文案（**三态**，保守口径）
  ///
  /// | 情形 | 输出 | 理由 |
  /// |---|---|---|
  /// | 无数据（`low <= 0`） | `—` | **绝不显示 `¥0`**（PR-09 验收③） |
  /// | 单值（`low == high`） | `¥1,900` | 没有区间，不该带 `≥`（`≥¥1,900` 会被读成"至少 1900"，与实际确定值不符） |
  /// | 真区间（`low < high`） | `≥¥1,300` | 只显下限，**不取中值**（取中值即估算，【裁 1】） |
  ///
  /// 超 1 万压缩：`≥¥1.2万`（单值时 `¥1.2万`）。
  ///
  /// [high] 缺省等于 [low]（旧调用点只有下限，保持单值语义）。
  static String lowerBoundText(int low, [int? high]) {
    if (low <= 0) return '—';
    final h = high ?? low;
    // 单值：无区间 → 不带 `≥`（`≥` 是"下界"符号，用在确定值上是误导）
    final single = h <= low;
    if (low >= 10000) {
      final w = low / 10000;
      final s = w >= 10 ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
      return single ? '¥$s万' : '≥¥$s万';
    }
    return single ? '¥${fmtAmount(low)}' : '≥¥${fmtAmount(low)}';
  }
}

/// 价格缓存 key 约定（与 PriceRepository 共用，避免两处各写一份拼接）
class PriceRepositoryKey {
  PriceRepositoryKey._();

  /// `price:{city}:{name}`；city 为空时用 `-` 占位，保证 key 稳定
  static String of(String? city, String? name) =>
      'price:${(city == null || city.isEmpty) ? '-' : city}:${name ?? ''}';
}
