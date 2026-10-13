import 'package:uuid/uuid.dart';

import 'trip_cost.dart';

enum LocationType { home, hotel, attraction, restaurant, shopping, transport, other }
// 六类语义映射：美食=restaurant 住宿=hotel 游玩=attraction 购物=shopping 枢纽=transport 其他=other；home=行程原点（不属于六类）

enum TransportType { flight, highSpeedTrain, train, bus, ship, taxi, subway, walk, transit, selfDrive, other }

/// 交通范围（与工具正交）：跨城线需枢纽点，同城线不需要
enum TransportScope { intercity, intraCity }

/// 行程类型（3类）：纯自驾 / 纯公共交通 / 公共交通+落地租车
enum TripMode { pureDrive, pureTransit, transitPlusRental }

/// 房型：标间 / 亲子间 / 大床房
enum RoomType { twin, family, king }

extension RoomTypeLabel on RoomType {
  String get label => switch (this) {
        RoomType.twin => '标间',
        RoomType.family => '亲子间',
        RoomType.king => '大床房',
      };
}

RoomType? roomTypeFromName(String? name) {
  if (name == null) return null;
  for (final e in RoomType.values) {
    if (e.name == name) return e;
  }
  return null;
}

enum MemberRole { admin, member }

class Trip {
  final String id;
  String name;
  DateTime startDate;
  DateTime endDate;
  List<TripDay> days;
  HomeLocation? homeLocation;
  List<Member> members;
  TripMode tripMode;
  int adults; // 大人为数量
  int children; // 小孩数量
  int rooms; // 房间数
  RoomType? roomType; // 房型偏好
  String budget; // 酒店预算档：economy/comfort/luxury
  DateTime createdAt;
  DateTime updatedAt;

  /// @nonPersisted 运行时字段：**不进 toJson / 不落库 / 不云同步**。
  ///
  /// 对应服务端 `stats.cost`（它在 `stats` 下，不在 `trip` 下 —— 只解析 `trip` 的写法会静默丢弃它）。
  /// 唯一取数点：`Trip.fromPlannerResponse()`，读 `json['stats']['cost']`（【裁 2】）。
  /// 本次不接 /api/planner/corridor，故端上恒为 null；取数路径先定义好，接 corridor 时零改动。
  TripCost? statsCost;

  Trip({
    String? id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.days = const [],
    this.homeLocation,
    this.members = const [],
    this.tripMode = TripMode.pureTransit,
    this.adults = 2,
    this.children = 0,
    this.rooms = 1,
    this.roomType,
    this.budget = 'comfort',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.statsCost,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get totalDays => days.length;

  List<Location> get allLocations {
    return days.expand((day) => day.locations).toList();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'days': days.map((d) => d.toJson()).toList(),
    'homeLocation': homeLocation?.toJson(),
    'members': members.map((m) => m.toJson()).toList(),
    'tripMode': tripMode.name,
    'adults': adults,
    'children': children,
    'rooms': rooms,
    'roomType': roomType?.name,
    'budget': budget,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Trip.fromJson(Map<String, dynamic> json, {TripCost? statsCost}) => Trip(
    id: json['id'],
    name: json['name'],
    startDate: DateTime.parse(json['startDate']),
    endDate: DateTime.parse(json['endDate']),
    days: (json['days'] as List? ?? const [])
        .whereType<Map>()
        .map((d) => TripDay.fromJson(Map<String, dynamic>.from(d)))
        .toList(),
    homeLocation: json['homeLocation'] != null ? HomeLocation.fromJson(json['homeLocation']) : null,
    members: (json['members'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Member.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
    tripMode: TripMode.values.firstWhere((e) => e.name == json['tripMode'], orElse: () => TripMode.pureTransit),
    adults: json['adults'] ?? 2,
    children: json['children'] ?? 0,
    rooms: json['rooms'] ?? 1,
    roomType: roomTypeFromName(json['roomType']),
    budget: json['budget'] ?? 'comfort',
    // 向后兼容：规划接口响应 / 旧数据可能不带时间戳 → 取"现在"（构造器默认值）
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
    updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
    statsCost: statsCost,
  );

  /// 规划接口（`generate` / `corridor`）完整响应 → Trip。
  ///
  /// 【裁 2】唯一取数点：`json['stats']['cost']` —— 它在 `stats` 下、不在 `trip` 下。
  /// 缺失时为 null（本次恒为 null），**不估算、不兜底**。
  factory Trip.fromPlannerResponse(Map<String, dynamic> json) {
    final rawTrip = json['trip'];
    final tripJson = rawTrip is Map
        ? Map<String, dynamic>.from(rawTrip)
        : <String, dynamic>{};

    TripCost? cost;
    final rawStats = json['stats'];
    if (rawStats is Map) {
      final rawCost = rawStats['cost'];
      if (rawCost is Map) {
        cost = TripCost.fromJson(Map<String, dynamic>.from(rawCost));
      }
    }
    return Trip.fromJson(tripJson, statsCost: cost);
  }
}

class TripDay {
  final String id;
  final DateTime date;
  int dayNumber;
  List<Location> locations;

  TripDay({
    String? id,
    required this.date,
    required this.dayNumber,
    this.locations = const [],
  }) : id = id ?? const Uuid().v4();

  int get totalMinutes {
    int total = 0;
    for (var loc in locations) {
      total += loc.stayMinutes ?? 0;
      total += loc.transportMinutes ?? 0;
    }
    return total;
  }

  String get formattedTime {
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '$hours小时${mins > 0 ? "$mins分钟" : ""}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'dayNumber': dayNumber,
    'locations': locations.map((l) => l.toJson()).toList(),
  };

  factory TripDay.fromJson(Map<String, dynamic> json) => TripDay(
    id: json['id'],
    date: DateTime.parse(json['date']),
    dayNumber: json['dayNumber'],
    // 向后兼容：旧数据缺 locations → 空列表，不抛异常
    locations: (json['locations'] as List? ?? const [])
        .whereType<Map>()
        .map((l) => Location.fromJson(Map<String, dynamic>.from(l)))
        .toList(),
  );
}

/// 单个营业时段（服务端 `toLocation.openSegments[]` 的元素，T03）。
///
/// 只承载「某一天里的一个开放区间」，**不含**星期/季节/节假日语义 ——
/// 那些是服务端 `parseOpenTime(poi, dateISO)` 按具体日期解完之后才成立的结论，
/// 客户端不重复解读。
///
/// 【为什么多时段时 `openTime/closeTime` 恒为 null】
/// 服务端为避免「只取第一个匹配时段」造成的结构性假阳性
/// （`11:00-14:00 16:00-22:00` 若取首个 → 19:00 到达被误判打烊），
/// 命中多于一段时五字段全 null，时段信息**只**由本类承载。
class OpenSegment {
  /// 开门时刻 `HH:mm`
  final String open;

  /// 打烊时刻 `HH:mm`（`24:00` 合法，但**仅**作打烊时刻）
  final String close;

  /// 该时段的停止入场时刻 `HH:mm`；null = 该时段没有/无法唯一解析
  final String? lastEntry;

  const OpenSegment({
    required this.open,
    required this.close,
    this.lastEntry,
  });

  Map<String, dynamic> toJson() => {
        'open': open,
        'close': close,
        'lastEntry': lastEntry,
      };

  /// 兼容解析：**缺 open/close 的脏元素直接丢弃**，不补空串占位。
  ///
  /// 三铁律：半个时段（只有 open 没有 close）无法支撑任何判断，
  /// 补一个 `''` 进去等于造数据 —— 一律返回 null 由调用方跳过。
  static OpenSegment? tryFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final open = json['open'] as String?;
    final close = json['close'] as String?;
    if (open == null || close == null || open.isEmpty || close.isEmpty) {
      return null;
    }
    return OpenSegment(
      open: open,
      close: close,
      lastEntry: json['lastEntry'] as String?,
    );
  }
}

class Location {
  final String id;
  String name;
  String address;
  double? latitude;
  double? longitude;
  String? city; // 城市名称（来自高德POI）
  String? district; // 区县名称（来自高德POI）
  LocationType type;
  /// 枢纽子类型（仅 type==transport 时有意义）：station火车站/airport机场/bus汽车站/port港口/rental租车点
  String? hubKind;
  int? stayMinutes;
  int? transportMinutes;
  String? openTime;
  String? closeTime;
  bool isAutoAdded; // 系统自动添加的交通枢纽
  Transport? transport; // 到达此地点的交通
  List<String> photoIds;
  /// 酒店三候选（仅 type==hotel 时有值）：name/address/latitude/longitude/rating/cost/reason
  List<Map<String, dynamic>>? hotelCandidates;

  // ---- T02 新增（全部**进** toJson/fromJson，要云同步）----
  /// 服务端时刻表到达时刻 `HH:mm`（planner.js toLocation）。
  ///
  /// 它是 `itinerary_checker.dart` 重建当日时刻链的**唯一锚**：
  /// 首站缺它 → 整条时间链不可靠，CH-01/02/06/07/08 全部跳过。
  ///
  /// ⛔ 早期实现曾用「回退 9:00 起点累加」兜底 —— 那是编造起点，违反三铁律，已移除；
  ///    现在的正确行为是**不推算**，由 CH-09 日级披露"未校验"。
  String? arrivalTime;
  /// 服务端时刻表离开时刻 `HH:mm`
  String? leaveTime;
  /// 高德评分（0 分服务端已置 null）
  double? rating;
  /// 服务端备注（如「连住」，multiCity.js:674）
  String? stayNote;
  /// 酒店/POI 参考价原串（高德 `biz_ext.cost`，如 `"300-500"`）。
  ///
  /// 【FX-06a 探针实测】酒店与景点该字段 **0/20 全空**（`cost: []`），
  /// 服务端 `multiCity.js` 给 `hotelLoc` 补的 cost 同样取不到值（源头无数据）。
  /// 故本字段当前**实际只在餐饮场景下可能非空**，且是否计价由 `PriceSource.supports()` 决定。
  /// 解析与脏值过滤统一走 `PriceRange.fromAmapCost()`。
  String? cost;
  /// 必去点（**客户端维护**，进 toJson 随云同步走）。
  /// 【裁 4】不读服务端 `_must`：它经 buildDay 后恒为 false、不可依赖。
  bool fixed;

  /// 用户手动补录的实付金额（单位：元，**该项总价**，进 toJson 随云同步走）。
  ///
  /// ## 为什么需要它（外部评审 2026-10-10 建议，评审原话：
  /// 「让用户自己填已订金额，比你们估算可靠」）
  ///
  /// 酒店/景点 `biz_ext.cost` 探针实测 **0/20 全空**，是源头无数据，短期内
  /// 既接不到 OTA 报价也无解 —— 而这两类恰恰占每日花费 40~60%，「当日已计价」
  /// 因此存在**结构性缺口**。但用户自己订完酒店/门票后**知道真实金额**。
  ///
  /// 由他填进来 → 缺口被真实数据补上，且**不违反三铁律**：
  /// 三铁律禁止的是「**我们**造数据」（估算/编造/兜底填充），
  /// 用户提供的实际支出是事实，不是估算。
  ///
  /// ## ⛔ 语义硬约束：**总价，不是人均**
  /// 1. 用户填的是「我付了多少钱」，天然是总价（酒店一晚 520、门票 60）；
  /// 2. 若当人均，就会与餐饮/交通的「人均 × 人数」口径混在同一聚合里，
  ///    同一个数字出现两套语义，无法向用户解释；
  /// 3. 故手填项**不参与任何乘法** —— `CostAggregator.aggregateDay()` 直接累加。
  ///
  /// `null` = 未补录（**与 0 不同**：0 表示用户明确填了「这项没花钱」）。
  int? manualCost;

  // ---- T03 新增：日期感知营业事实（全部**进** toJson/fromJson，要云同步）----
  //
  // ⛔ 这五个字段是**绑定某个具体日期**的结论（服务端 `buildDay(dateStr)` 才解析）。
  //    日期变化 / 地点跨日移动后必须整体清空（见 `clearOpenHoursFacts()`），
  //    把旧日期结论搬到新日期 = 编造数据。
  /// 与营业结论对应的**原文命中子句**（服务端 `openHoursRaw`，原样切片，不得改写）。
  ///
  /// null = 无可靠证据（解析失败 / 旧数据）。
  /// UI 副行只在非 null 时展示 —— 来源透明第三层：无证据时不展示结构化结论。
  String? openHoursRaw;
  /// 停止检票/入馆/入园时刻 `HH:mm`。
  ///
  /// null = 该场所没有停止入场要求，**或**无法唯一解析 —— 两者在客户端不可区分，
  /// 也无需区分：CH-01 在 null 时退回到用 `closeTime` 判「打烊」。
  String? lastEntryTime;
  /// 目标日期是否闭馆：**三态** —— true=明确关闭 / false=明确命中开放段 / null=未知。
  ///
  /// ⛔ **null 绝不当 false**。这是本次修复的核心陷阱之一：
  /// 服务端曾用 `String(poi.biz_ext.opentime)` 把 `undefined` / `[]` 当成有效源，
  /// 使「未知」被当成「有营业时间」，进而产生阻塞级假阳性。
  bool? closedOnDate;
  /// 多时段营业段（服务端 `openSegments`）。单时段也会产出长度 1 的列表。
  ///
  /// 多时段时 `openTime/closeTime` 恒为 null，时段信息只由本字段承载；
  /// CH-01/02 因营业结构不完整而跳过，走 CH-09 日级披露。
  /// null = 旧数据 / 服务端未下发（**与 `[]` 不同**：`[]` 是"明确无时段"）。
  List<OpenSegment>? openSegments;

  Location({
    String? id,
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
    this.city,
    this.district,
    required this.type,
    this.hubKind,
    this.stayMinutes,
    this.transportMinutes,
    this.openTime,
    this.closeTime,
    this.isAutoAdded = false,
    this.transport,
    this.photoIds = const [],
    this.hotelCandidates,
    this.arrivalTime,
    this.leaveTime,
    this.rating,
    this.stayNote,
    this.cost,
    this.fixed = false,
    this.manualCost,
    // ---- T03 新增：营业事实（默认 null = 未知，不填默认值）----
    this.openHoursRaw,
    this.lastEntryTime,
    this.closedOnDate,
    this.openSegments,
  }) : id = id ?? const Uuid().v4();

  /// 清空「针对某个日期」的营业事实（T04：日期变化 / 跨日移动后调用）。
  ///
  /// 营业时间是**日期感知**的：旧日期的解析结论搬到新日期就是假数据。
  /// 按三铁律必须清空并走 CH-09 日级披露 —— **不联网补查、不回填默认营业时间**。
  void clearOpenHoursFacts() {
    openTime = null;
    closeTime = null;
    lastEntryTime = null;
    closedOnDate = null;
    openHoursRaw = null;
    openSegments = null;
  }

  /// 获取城市名称，优先使用POI返回的city，否则从address解析
  String get cityName {
    // 优先使用高德返回的城市名
    if (city != null && city!.isNotEmpty) {
      return city!;
    }
    // 尝试从地址中提取
    if (address.contains('市')) {
      final index = address.indexOf('市');
      // 北京、天津、上海、重庆 等直辖市需要特殊处理
      String cityStr = address.substring(0, index + 1);
      // 去掉"北京市" -> "北京"
      if (cityStr.endsWith('市') && cityStr.length > 2) {
        cityStr = cityStr.substring(0, cityStr.length - 1);
      }
      return cityStr;
    }
    return address;
  }

  /// 判断是否同城：比较两个地点是否在同一城市
  bool isSameCity(Location other) {
    return cityName == other.cityName;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
    'district': district,
    'type': type.name,
    'hubKind': hubKind,
    'stayMinutes': stayMinutes,
    'transportMinutes': transportMinutes,
    'openTime': openTime,
    'closeTime': closeTime,
    'isAutoAdded': isAutoAdded,
    'transport': transport?.toJson(),
    'photoIds': photoIds,
    'hotelCandidates': hotelCandidates,
    // T02 新增：全部进 toJson（要云同步）
    'arrivalTime': arrivalTime,
    'leaveTime': leaveTime,
    'rating': rating,
    'stayNote': stayNote,
    'cost': cost,
    'fixed': fixed,
    'manualCost': manualCost,
    // ---- T03 新增：营业事实同步（要云同步，故必须进 toJson）----
    'openHoursRaw': openHoursRaw,
    'lastEntryTime': lastEntryTime,
    // 客户端命名 `closedOnDate`（服务端别名 `closedOnThisDate` 只在 fromJson 兼容读取）
    'closedOnDate': closedOnDate,
    'openSegments': openSegments?.map((s) => s.toJson()).toList(),
  };

  /// 🔒 [address] 声明为非空 `String`，故从 JSON 取值**必须**做 null 兜底。
  ///
  /// 【真实 bug，`flutter analyze` 的 `dead_null_aware_expression` 顺带暴露】
  /// 原为 `address: json['address']` —— 直接把可能为 null 的动态值赋给非空 `String`，
  /// 服务端任一条 POI 缺 address 时 `fromJson` 会**抛运行时类型错误**（整页崩），
  /// 而非安全降级为「无地址」。这与三铁律「宁可少显示，不可显示错」相违：
  /// 正确行为是**地址缺失就显示没有**，而不是让整页挂掉。
  factory Location.fromJson(Map<String, dynamic> json) => Location(
        id: json['id'],
        name: json['name'],
        address: (json['address'] as String?) ?? '',
        latitude: json['latitude'],
        longitude: json['longitude'],
        city: json['city'],
        district: json['district'],
        type: LocationType.values.firstWhere((e) => e.name == json['type'], orElse: () => LocationType.other),
        hubKind: json['hubKind'],
        stayMinutes: json['stayMinutes'],
        transportMinutes: json['transportMinutes'],
    openTime: json['openTime'],
    closeTime: json['closeTime'],
    isAutoAdded: json['isAutoAdded'] ?? false,
    transport: json['transport'] != null ? Transport.fromJson(json['transport']) : null,
    photoIds: List<String>.from(json['photoIds'] ?? []),
    hotelCandidates: (json['hotelCandidates'] as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    // T02 新增：向后兼容 —— 旧数据缺字段一律取默认值，不抛异常
    arrivalTime: json['arrivalTime'] as String?,
    leaveTime: json['leaveTime'] as String?,
    rating: (json['rating'] as num?)?.toDouble(),
    stayNote: json['stayNote'] as String?,
    cost: json['cost'] as String?,
    fixed: json['fixed'] == true,
    // `as num?` 而非 `as int?`：云同步往返经 JSON 后整数可能被带成小数，
    // 直接 as int? 会抛；旧数据缺该字段 → null（未补录），向后兼容。
    manualCost: (json['manualCost'] as num?)?.round(),
    // ---- T03 新增：向后兼容 —— 旧 JSON 缺这四个键一律 null，不抛、不兜底 ----
    openHoursRaw: json['openHoursRaw'] as String?,
    lastEntryTime: json['lastEntryTime'] as String?,
    // 服务端 payload 用 `closedOnThisDate`，客户端用 `closedOnDate`：两个键都读。
    // ⛔ 必须 `v is bool` 判定：真/假/未知是三态，非 bool 一律当**未知**，
    //    绝不能写成 `== true`（那会把 null 折叠成 false，正是本次要修的陷阱）。
    closedOnDate: _readTriStateBool(json['closedOnDate'] ?? json['closedOnThisDate']),
    openSegments: (json['openSegments'] as List?)
        ?.map(OpenSegment.tryFromJson)
        .whereType<OpenSegment>()
        .toList(),
  );
}

/// 三态布尔读取：只有真正的 `bool` 才被接受，其余（null / 数字 / 字符串）一律「未知」。
///
/// 单独抽成函数是因为这个判定在 `fromJson` 里只有一处、却最容易写错：
/// 写成 `json[k] == true` 会把 null 悄悄折叠成 false，
/// 而本次修复的核心正是「`closedOnDate == null` 不得当成没闭馆」。
bool? _readTriStateBool(dynamic v) => (v is bool) ? v : null;

class Transport {
  final String id;
  TransportType type;
  TransportScope scope;
  String? flightNumber;
  String? departureTime;
  String? arrivalTime;
  int? durationMinutes;
  double? distance;

  // ---- T02 新增（全部**进** toJson/fromJson，要云同步）----
  /// 票价（真实班次才有；服务端估算分支恒 null —— planner.js:475 / multiCity.js:569,735）
  num? price;
  /// 是否为固定班次（corridor 产出；generate 管线恒 null）
  bool? isFixed;
  /// 是否为估算占位（corridor 产出；generate 管线恒 null）
  /// 注：generate 管线不产出 isFixed/estimated（恒 null）→ UI 用 flightNumber 空值辅助判「估算占位」
  bool? estimated;

  Transport({
    String? id,
    required this.type,
    required this.scope,
    this.flightNumber,
    this.departureTime,
    this.arrivalTime,
    this.durationMinutes,
    this.distance,
    this.price,
    this.isFixed,
    this.estimated,
  }) : id = id ?? const Uuid().v4();

  bool get isIntercity => scope == TransportScope.intercity;

  /// 是否"真实班次"（有固定时刻锚）：UI 据此决定是否展示"班次固定"标识
  bool get isScheduled => isFixed == true;

  /// 是否"估算占位"（无真实班次）：UI 据此提示"时长为估算占位，班次以 12306/航司为准"
  bool get isEstimate => estimated == true;

  String get displayName {
    switch (type) {
      case TransportType.flight:
        return '✈️ 飞机';
      case TransportType.highSpeedTrain:
        return '🚄 高铁';
      case TransportType.train:
        return '🚃 火车';
      case TransportType.bus:
        return '🚌 大巴';
      case TransportType.ship:
        return '⛴️ 轮船';
      case TransportType.taxi:
        return '🚕 打车';
      case TransportType.subway:
        return '🚇 地铁';
      case TransportType.walk:
        return '🚶 步行';
      case TransportType.transit:
        return '🚌 公共交通';
      case TransportType.selfDrive:
        return '🚗 自驾';
      default:
        return '其他';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'scope': scope.name,
    'flightNumber': flightNumber,
    'departureTime': departureTime,
    'arrivalTime': arrivalTime,
    'durationMinutes': durationMinutes,
    'distance': distance,
    // T02 新增：全部进 toJson（要云同步）
    'price': price,
    'isFixed': isFixed,
    'estimated': estimated,
  };

  factory Transport.fromJson(Map<String, dynamic> json) => Transport(
    id: json['id'],
    type: TransportType.values.firstWhere((e) => e.name == json['type'], orElse: () => TransportType.other),
    scope: TransportScope.values.firstWhere((e) => e.name == json['scope'], orElse: () => TransportScope.intraCity),
    flightNumber: json['flightNumber'],
    departureTime: json['departureTime'],
    arrivalTime: json['arrivalTime'],
    durationMinutes: json['durationMinutes'],
    distance: json['distance']?.toDouble(),
    // T02 新增：向后兼容 —— 旧数据缺字段为 null，不抛异常
    price: json['price'] as num?,
    isFixed: json['isFixed'] as bool?,
    estimated: json['estimated'] as bool?,
  );
}

class HomeLocation {
  final String id;
  String name;
  String address;
  double? latitude;
  double? longitude;
  String? city;
  String? district;

  HomeLocation({
    String? id,
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
    this.city,
    this.district,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'city': city,
    'district': district,
  };

  factory HomeLocation.fromJson(Map<String, dynamic> json) => HomeLocation(
    id: json['id'],
    name: json['name'],
    address: json['address'],
    latitude: json['latitude']?.toDouble(),
    longitude: json['longitude']?.toDouble(),
    city: json['city'],
    district: json['district'],
  );
}

class Member {
  final String id;
  String name;
  MemberRole role;
  String? avatarUrl;
  List<String> photoIds;
  DateTime? lastActiveAt;

  Member({
    String? id,
    required this.name,
    required this.role,
    this.avatarUrl,
    this.photoIds = const [],
    this.lastActiveAt,
  }) : id = id ?? const Uuid().v4();

  bool get isAdmin => role == MemberRole.admin;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'role': role.name,
    'avatarUrl': avatarUrl,
    'photoIds': photoIds,
    'lastActiveAt': lastActiveAt?.toIso8601String(),
  };

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'],
    name: json['name'],
    role: MemberRole.values.firstWhere((e) => e.name == json['role']),
    avatarUrl: json['avatarUrl'],
    photoIds: List<String>.from(json['photoIds'] ?? []),
    lastActiveAt: json['lastActiveAt'] != null ? DateTime.parse(json['lastActiveAt']) : null,
  );
}

class Footprint {
  final String id;
  final String city;
  final String province;
  final double latitude;
  final double longitude;
  final DateTime visitedAt;
  final int visitCount;

  Footprint({
    String? id,
    required this.city,
    required this.province,
    required this.latitude,
    required this.longitude,
    required this.visitedAt,
    this.visitCount = 1,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'city': city,
    'province': province,
    'latitude': latitude,
    'longitude': longitude,
    'visitedAt': visitedAt.toIso8601String(),
    'visitCount': visitCount,
  };

  factory Footprint.fromJson(Map<String, dynamic> json) => Footprint(
    id: json['id'],
    city: json['city'],
    province: json['province'],
    latitude: json['latitude'].toDouble(),
    longitude: json['longitude'].toDouble(),
    visitedAt: DateTime.parse(json['visitedAt']),
    visitCount: json['visitCount'] ?? 1,
  );
}
