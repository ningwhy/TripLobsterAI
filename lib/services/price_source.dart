import '../models/price_quote.dart';
import '../models/trip_models.dart';
import '../theme/preview_theme.dart';

/// 价格数据源抽象层（PR-10）
///
/// 存在的唯一理由：**下阶段要接 OTA 报价 API（用户已决策，4–6 周）**。届时价格语义
/// 从「参考价」变为「实时价」；若 widget / 聚合器里写死数据源语义，届时需全页返工。
/// 本轮把**语义 + 乘数 + 请求参数**全部收进本文件，OTA 接入时的改动面只有三步：
///   1. 新增 `class OtaLivePriceSource extends PriceSource`
///   2. `supports()` 放开 `hotel` / `attraction`
///   3. 改 `PreviewStrings` 里的文案值
/// **widget / `CostAggregator` / `PriceRepository` 零改动** —— 这就是 PR-10 的价值。
///
/// ## 本轮有效口径（依据：真实 `AMAP_KEY` 探针 `_fx06a_probe.mjs`，**不是 stub**）
///
/// | 类型 | `biz_ext.cost` 实测 | 本轮是否计价 | 网络请求数 |
/// |---|---|---|---|
/// | 餐饮 `restaurant` | ✅ 18/20 有值，且确认为**人均**（`"150.00"`） | ✅ `× peopleCount` | **0**（SR-02 后随 payload 下发） |
/// | 跨城班次 `intercity` | ✅ `transport.price` 随行程下发（确定值） | ✅ `× peopleCount` | **0**（随 payload 下发） |
/// | 酒店 `hotel` | ❌ 0/20 全空（`cost: []`、`lowest_price: []`） | ❌ 不渲染 / 不计入 | **0**（源头无数据） |
/// | 景点 `attraction` | ❌ 0/20 全空 | ❌ 不渲染 / 不计入 | **0**（源头无数据） |
///
/// 即：**本轮所有价格类型网络请求数均为 0**，价格全部来自行程 payload 的离线字段。
/// 见 `requestKindFor()` 的注释（含三条收益与一条已知取舍）。
///
/// 反例警示：`test/multicity_corridor_smoke.mjs` 里的 `cost: "400-600"` 是 **stub 数据**，
/// 曾误导我们得出"酒店有价"的错误前提，**不得**作为任何价格口径的判定证据。
///
/// ## ⚠️ 两条乘法规则禁止合并（防呆）
/// - 餐饮：单位**已实测**为人均 → `× peopleCount` **成立**
/// - 酒店：单位**未知且当前无值** → 本轮**不乘**
///
/// 若把它们合并成一个通用 `multiplier` 常量，将来接入酒店实时价时会被错误复用成人均
/// 乘法，数字直接翻倍。故本类**只暴露 `peopleCount()` 一个乘数**。
abstract class PriceSource {
  const PriceSource();

  /// 数据源标识（缓存分区 / 将来的埋点）：`amap_reference` / `ota_live`
  String get id;

  /// 口径说明（当日已计价的常驻副行）。文案集中在 `PreviewStrings`（PR-10 ②）。
  String get scopeText;

  /// 单个地点取不到价时的文案（**卡片级**）。文案集中在 `PreviewStrings`。
  String get absentText;

  /// 本数据源是否为该地点提供价格。
  /// `false` → **不请求、不渲染、不计入聚合**（也不会被算作"缺失项"）。
  bool supports(Location loc);

  /// 按本数据源口径换算出的**合计价**（乘数已在此内部完成）。
  ///
  /// 返回 `null` = 取不到价 → UI 走 `absentText`。**禁止返回 0**（0 会被误读为"免费"）。
  PriceRange? priceOf(Location loc, PriceQuote? quote, Trip trip);

  /// 拉取该地点价格时传给服务端的 `kind`（**协议参数**）。
  ///
  /// 返回 `null` = 没有可发的 kind（本轮全部类型均如此，见子类注释）。
  String? requestKindFor(Location loc);

  /// 该地点是否需要联网取价（**演化判断**：随 SR-02 / SR-03 / OTA 接入而翻转）。
  ///
  /// ⛔ **禁止与 `requestKindFor()` 合并**（D-AR-01，架构师裁决，我采纳）：
  /// - `needsNetwork` = **要不要联网**（演化判断，随数据源能力变化）
  /// - `requestKindFor` = **发什么 kind**（协议参数，服务端接口契约）
  ///
  /// 合成一个返回值会让两种语义互相绑架。反例：将来接入不走 `kind` 协议的自研
  /// 报价 API 时，`requestKindFor` 只能返回 null，合并写法会直接判成"不联网"——
  /// 按钮错误置灰、价格永远不刷新，且**没有任何报错**，是最难查的那类 bug。
  ///
  /// 默认实现：`需要联网 ⟺ 有 kind 可发`，保持**单一出口**，避免两处漏改；
  /// 子类可覆写以解耦二者。这样本轮状态变化只需改 `requestKindFor` 一处，
  /// `needsNetwork` 与刷新按钮置灰自动跟随。
  ///
  /// **UI 侧用法**（「🔄 刷新参考价」按钮置灰判定）：
  /// ```dart
  /// final canRefresh = trip.allLocations.any((l) => source.needsNetwork(l));
  /// ```
  /// ⛔ UI 层**禁止**写 `enabled: false` 之类的硬编码常量 —— 那样 OTA 接入后按钮
  /// 不会自动亮起，PR-10 抽象层等于白做。置灰必须走上面这一行。
  /// 本轮 `requestKindFor()` 恒 null → `any()` 恒 false → 按钮置灰
  /// （不可点击 —— 可点击但点了没反应是"假可供性"，比不做更伤信任，PM 裁决）。
  bool needsNetwork(Location loc) => requestKindFor(loc) != null;

  /// 是否为跨城班次点（票价挂在 `transport.price`，随行程下发）
  static bool isIntercity(Location loc) {
    final t = loc.transport;
    return t != null && t.scope == TransportScope.intercity;
  }

  /// 出行人数 —— **全局唯一乘数**（至少 1，防 0 人导致金额归零）
  ///
  /// ⛔ 计价路径只允许出现这一个乘数；`trip.rooms` **不得**参与计价
  /// （房间数与"人均"是两套语义，混用会导致数字翻倍）。
  int peopleCount(Trip trip) {
    final n = trip.adults + trip.children;
    return n < 1 ? 1 : n;
  }

  /// A-11 校验：服务端 `kind='ticket'` 走**泛搜索**（`types:''`），可能命中同名或近似的
  /// **另一个 POI**。返回结果的 `name` 或 `candidates[0].name` 必须与查询名一致，
  /// 否则该价格**一律不使用** —— 宁可显示无价，不可张冠李戴。
  ///
  /// 根因：服务端 `lookupPrice` 的 `kind` 枚举只有 `hotel | ticket`，没有 `dining`；
  /// 查餐饮只能传 `ticket`（因为 `kind !== 'ticket'` 会被当成酒店，限定 `types:'100000'`
  /// 必然搜不到）。建议服务端扩展 `kind=dining`；在此之前靠本方法兜底。
  ///
  /// 🟡 **本轮不触发**：`requestKindFor()` 恒返回 null → 不发请求 → 不会有 quote 进来，
  /// 本方法的校验路径本轮**一次都不会走**。
  /// **保留**它是有意的（不是死代码）：OTA 接入后查 hotel/attraction 时立刻需要它，
  /// 且它是防御性的——删掉的话届时要用时得重新发现一遍这个坑。
  bool matchesSubject(PriceQuote quote, String subjectName) {
    final subject = subjectName.trim();
    if (subject.isEmpty) return false;
    if (quote.name.trim() == subject) return true;
    final c = quote.candidates;
    if (c.isEmpty) return false;
    return c.first.name.trim() == subject;
  }
}

/// 唯一实现：高德 POI 静态参考价（`GET /api/planner/prices`）
///
/// 【M7】价格语义是"参考价"，**不是**实时房价/可订状态 —— 文案不出现后者。
class AmapReferencePriceSource extends PriceSource {
  const AmapReferencePriceSource();

  @override
  String get id => 'amap_reference';

  @override
  String get scopeText => PreviewStrings.priceScope;

  @override
  String get absentText => PreviewStrings.priceAbsent;

  @override
  bool supports(Location loc) =>
      loc.type == LocationType.restaurant || PriceSource.isIntercity(loc);


  @override
  String? requestKindFor(Location loc) {
    // 【本轮恒 null —— 全部价格类型 0 次网络请求】
    //
    // 餐饮：SR-02 已让 `biz_ext.cost` 随行程 payload 离线下发
    //   （`server/src/planner.js` → `normalizePoi()` 归一 + `toLocation()` 透传），
    //   客户端直接读 `loc.cost`，**不需要**再打 `/api/planner/prices`。
    // 跨城班次：票价挂在 `transport.price`，同样随 payload 下发。
    // 酒店 / 景点：FX-06a 探针实测 `biz_ext.cost` **0/20 全空**，源头无数据，拉也白拉。
    //
    // ⚠️ 这个 null 不是"暂时没想到"，而是三条收益换来的主动选择：
    //   1. A-11 张冠李戴风险**归零** —— 原路径查餐饮只能传 `kind='ticket'`
    //      （服务端 `isHotel = kind !== 'ticket'`，非 ticket 一律按酒店处理），
    //      走的是泛搜索，可能命中同名不同店。不发起请求就不需要防线，
    //      这是根因消除，不是打补丁。
    //   2. 省高德配额 —— 酒店/景点请求必空，纯烧配额。
    //   3. M9 验证口径变硬：从"hotel/ticket 请求数为 0"升级为"全部价格请求数为 0"。
    //
    // 已知取舍（不是 bug，勿"修复"）：SR-02 只对**新生成**的行程生效，
    // SR-02 之前保存的历史行程其餐饮 `cost` 恒 null，本轮将显示「暂无参考价」。
    // 曾评估过按 `createdAt` 开白名单给历史行程联网补价，**否决**——
    // 那等于重新打开 A-11 通道，收益是补价格、代价是可能显示另一家同名店的价，
    // 违反「宁可少显示，不可显示错」。
    //
    // 🔓 OTA 接入时（用户已决策，4–6 周）：本方法改为对 hotel/attraction 返回
    // 对应 kind 即可，刷新按钮随之自动亮起，widget / 聚合器零改动。
    return null;
  }

  @override
  PriceRange? priceOf(Location loc, PriceQuote? quote, Trip trip) {
    if (!supports(loc)) return null;
    final n = peopleCount(trip);

    // 跨城班次票价：确定值（low == high）。数值字段无千分位风险 → 只做正数校验，
    // 不套 `low < 20` 的脏值规则（票价本就可能低于 20 元）。
    if (PriceSource.isIntercity(loc)) {
      final p = loc.transport?.price;
      if (p == null) return null; // 估算分支服务端恒 null —— 诚实缺失，不编造
      final unit = p.round();
      if (unit <= 0) return null;
      final total = unit * n;
      return PriceRange(low: total, high: total);
    }

    // 餐饮：优先读 `loc.cost`（SR-02 后随 payload 离线下发，**本轮唯一实际生效的取值路径**），
    // 取不到才回落到运行时缓存的参考价 `_referenceOf(quote)`。
    //
    // 🟡 `_referenceOf` 分支本轮**恒为 null**：`requestKindFor()` 不发请求 → 永远没有
    // quote 进来。保留它是有意的——删掉需要同时改 `priceOf` 签名与 widget 调用点，
    // 而 OTA 接入后这条分支会立刻变成主路径。此处标注清楚，避免被误读为"缓存读路径在用"。
    //
    // 两条路径都是**人均**口径（探针实测餐饮 18/20 为 `"150.00"`），故 `× peopleCount` 成立。
    //
    // 【D-AR-03】回落分支**必须先过 `matchesSubject`**：`fetch()` 拉回的 quote 是泛搜索
    // 结果，可能命中同名不同店；不加这道校验，错配价会经缓存一路流到 UI 出价，
    // A-11 防线等于被绕过。本轮该分支恒为 null（无请求即无 quote），但**防御要写在
    // 消费点**——将来任何一条路径启用时它立刻生效。
    final cached = (quote != null && matchesSubject(quote, loc.name)) ? _referenceOf(quote) : null;
    final unit = PriceRange.fromAmapCost(loc.cost) ?? cached;
    if (unit == null) return null;
    if (unit.isDirty) return null; // 二次防御（fromAmapCost 已滤，quote 路径再滤一次）
    return PriceRange(low: unit.low * n, high: unit.high * n);
  }

  /// 取缓存里的参考价（脏值 / 无缓存 → null）
  static PriceRange? _referenceOf(PriceQuote? quote) {
    final q = quote;
    if (q == null) return null;
    if (q.isDirty) return null;
    return q.reference;
  }
}
