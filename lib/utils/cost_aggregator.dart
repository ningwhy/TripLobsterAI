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
/// | 餐饮 | 人均 `cost` × 人数 | ✅ 18/20 有值（**需用户点刷新**，服务端不下发） |
/// | 跨城班次 | `transport.price` × 人数 | ✅ 随行程 payload 下发，0 次请求 |
/// | 酒店 | —— | ❌ 0/20 全空 → `supports()==false`，不请求不渲染 |
/// | 景点 | —— | ❌ 0/20 全空 → `supports()==false`，不请求不渲染 |
///
/// 明确排除：油 / 电 / 过路 / 租车 / 包车（需按里程估算 → 严禁）。
enum CostSource { dining, intercity }

extension CostSourceLabel on CostSource {
  String get label => switch (this) {
        CostSource.dining => '餐饮',
        CostSource.intercity => '交通班次',
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
    return DayCost(
      low: low,
      high: high,
      lines: lines,
      missingCount: missing,
      scopeText: source.scopeText,
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

  /// 日期条格子文案（只显**下限**，保守口径）：`≥¥1,300`；超 1 万压缩为 `≥¥1.2万`
  ///
  /// 无数据时返回 `—`，**绝不显示 `¥0`**。
  static String lowerBoundText(int low) {
    if (low <= 0) return '—';
    if (low >= 10000) {
      final w = low / 10000;
      final s = w >= 10 ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
      return '≥¥${s}万';
    }
    return '≥¥${fmtAmount(low)}';
  }
}

/// 价格缓存 key 约定（与 PriceRepository 共用，避免两处各写一份拼接）
class PriceRepositoryKey {
  PriceRepositoryKey._();

  /// `price:{city}:{name}`；city 为空时用 `-` 占位，保证 key 稳定
  static String of(String? city, String? name) =>
      'price:${(city == null || city.isEmpty) ? '-' : city}:${name ?? ''}';
}
