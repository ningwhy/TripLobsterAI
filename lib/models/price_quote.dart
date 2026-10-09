// 运行时模型：不进 Trip.toJson
//
// 对应服务端 `GET /api/planner/prices`（server/src/multiCity.js → lookupPrice）。
// 结构严格对齐服务端返回：
//   {kind,name,city,poi,candidates[],reference,realTime,source,fetchedAt,fetchedAtText,warning}
//
// 三条硬约束：
//   【裁 5】比价卡只用 `candidates[]`，禁止把顶层 `poi` 与顶层 `reference` 拼接展示
//           （服务端 :885 取"第一个有价候选"、:889 取"评分最高候选"，可能来自两家不同酒店）。
//   【裁 6】价格脏数据防御：正则不处理千分位（"1,200" 会被解析成 ¥1），
//           故 `low < 20 || high < low` 一律判为脏数据 → 丢弃不显示。
//   【裁 10 / PR-09】缺失即降级：卡片级 `暂无参考价`、整日级 `暂无可计价数据`，
//            严禁估算、严禁兜底、严禁显示 `¥0` 或 `¥—`。
//
// 缓存：由 PriceRepository 走 SharedPreferences（key = price:{city}:{name}，7 天过期），
// 不随 Trip 云同步。

/// 参考价区间（高德 `biz_ext.cost`，静态滞后数据，**不是实时房价**）
class PriceRange {
  /// 低于此值视为脏数据（千分位被正则截断的典型症状："1,200" → 1）
  static const int minPlausiblePrice = 20;

  final int low;
  final int high;
  final String currency;

  const PriceRange({
    required this.low,
    required this.high,
    this.currency = 'CNY',
  });

  /// 脏数据判定：下限不可信 或 区间倒置
  bool get isDirty => low < minPlausiblePrice || high < low;

  /// 展示文案：`¥300–500`（单值时 `¥300`）
  String get text => low == high ? '¥$low' : '¥$low–$high';

  Map<String, dynamic> toJson() => {
        'low': low,
        'high': high,
        'currency': currency,
      };

  /// 解析服务端 `reference`（不做脏值丢弃，脏值判定交给调用方）
  static PriceRange? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final low = _asInt(json['low']);
    final high = _asInt(json['high']);
    if (low == null || high == null) return null;
    return PriceRange(
      low: low,
      high: high,
      currency: (json['currency'] as String?) ?? 'CNY',
    );
  }

  /// 从高德 `biz_ext.cost` 原始字符串解析：`"300-500"` / `"300"` / `"1,200-1,500"`
  ///
  /// 防御顺序：先剥千分位逗号 → 再匹配数字区间 → 最后做脏值判定。
  /// 脏值（low < 20 或 high < low）返回 **null**（丢弃不显示），不抛异常。
  static PriceRange? fromAmapCost(String? cost) {
    if (cost == null) return null;
    final cleaned = cost.replaceAll(',', '').replaceAll('，', '').trim();
    if (cleaned.isEmpty) return null;
    final m = RegExp(r'(\d+)(?:\s*-\s*(\d+))?').firstMatch(cleaned);
    if (m == null) return null;
    final low = int.tryParse(m.group(1)!);
    if (low == null) return null;
    final highRaw = m.group(2);
    final high = highRaw == null ? low : (int.tryParse(highRaw) ?? low);
    final range = PriceRange(low: low, high: high);
    return range.isDirty ? null : range;
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.replaceAll(',', ''));
    return null;
  }

  @override
  String toString() => 'PriceRange($text)';
}

/// 比价候选（服务端只返回 top3：位置 / 评分 / 参考价）
class PriceCandidate {
  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final double? rating;

  /// 该候选自己的参考价（脏值已置 null）
  final PriceRange? reference;
  final String source;

  const PriceCandidate({
    required this.name,
    this.address = '',
    this.latitude,
    this.longitude,
    this.rating,
    this.reference,
    this.source = '',
  });

  /// 是否有可用参考价（脏值不算有）
  bool get hasPrice => reference != null;

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'rating': rating,
        'reference': reference?.toJson(),
        'source': source,
      };

  /// 解析单个候选；`reference` 脏值 → null（不显示、不报错）
  factory PriceCandidate.fromJson(Map<String, dynamic> json) {
    final parsed = PriceRange.tryParse(json['reference']);
    return PriceCandidate(
      name: (json['name'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      reference: (parsed != null && parsed.isDirty) ? null : parsed,
      source: (json['source'] as String?) ?? '',
    );
  }

  @override
  String toString() => 'PriceCandidate($name, ${reference?.text ?? '无参考价'})';
}

/// 实时价能力（服务端恒 `available:false` —— OTA 有反爬，未接联盟 API）
///
/// UI 不得据此做"实时价加载中"态；`available==false` 是常量而非状态。
class PriceRealTime {
  final bool available;
  final String provider;
  final String deepLink;
  final String note;

  const PriceRealTime({
    this.available = false,
    this.provider = '',
    this.deepLink = '',
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'available': available,
        'provider': provider,
        'deepLink': deepLink,
        'note': note,
      };

  factory PriceRealTime.fromJson(Map<String, dynamic> json) => PriceRealTime(
        available: json['available'] == true,
        provider: (json['provider'] as String?) ?? '',
        deepLink: (json['deepLink'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
      );

  @override
  String toString() => 'PriceRealTime(available=$available, provider=$provider)';
}

/// 一次价格查询的结果（可缓存，7 天过期）
class PriceQuote {
  /// hotel / ticket
  final String kind;
  final String name;
  final String city;

  /// 服务端"评分最高候选"（**禁止**与 reference 拼接展示，见文件头【裁 5】）
  final PriceCandidate? poi;

  /// 比价卡唯一数据源：top3 候选（各自带自己的参考价）
  final List<PriceCandidate> candidates;

  /// 服务端挑出的"第一个有价候选"的参考价（仅作快速展示；脏值已置 null）
  final PriceRange? reference;
  final PriceRealTime realTime;
  final String source;

  /// ISO8601 时间戳（缓存过期判定用）
  final String fetchedAt;

  /// 服务端给的展示文案：`截至 HH:mm`
  final String fetchedAtText;
  final String? warning;

  /// 该次查询的参考价是否被判为脏数据（千分位 / 区间倒置）
  final bool isDirty;

  const PriceQuote({
    this.kind = 'hotel',
    this.name = '',
    this.city = '',
    this.poi,
    this.candidates = const <PriceCandidate>[],
    this.reference,
    this.realTime = const PriceRealTime(),
    this.source = '',
    this.fetchedAt = '',
    this.fetchedAtText = '',
    this.warning,
    this.isDirty = false,
  });

  /// 是否有可展示的参考价（脏值 / 缺失都算没有）
  bool get hasReference => reference != null;

  /// 是否有候选（无候选 → 灰徽章「未匹配到 POI」）
  bool get hasCandidates => candidates.isNotEmpty;

  /// 缓存是否过期（默认 7 天，PRD Q4-A）
  bool isStale(Duration ttl) {
    final t = DateTime.tryParse(fetchedAt);
    if (t == null) return true; // 无时间戳 → 视为过期（无法证明新鲜）
    return DateTime.now().difference(t) > ttl;
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'name': name,
        'city': city,
        'poi': poi?.toJson(),
        'candidates': candidates.map((c) => c.toJson()).toList(),
        'reference': reference?.toJson(),
        'realTime': realTime.toJson(),
        'source': source,
        'fetchedAt': fetchedAt,
        'fetchedAtText': fetchedAtText,
        'warning': warning,
        'isDirty': isDirty,
      };

  /// 写 SharedPreferences 用的精简结构（去掉不可变冗余，保留缓存必要字段）
  Map<String, dynamic> toCacheJson() => {
        'kind': kind,
        'name': name,
        'city': city,
        'candidates': candidates.map((c) => c.toJson()).toList(),
        'reference': reference?.toJson(),
        'realTime': realTime.toJson(),
        'source': source,
        'fetchedAt': fetchedAt,
        'fetchedAtText': fetchedAtText,
        'warning': warning,
        'isDirty': isDirty,
      };

  /// 严格对齐服务端结构解析；脏值 → 丢弃且置 `isDirty=true`
  factory PriceQuote.fromJson(Map<String, dynamic> json) {
    final rawCandidates = json['candidates'];
    final candidates = <PriceCandidate>[];
    if (rawCandidates is List) {
      for (final c in rawCandidates) {
        if (c is Map) {
          candidates.add(PriceCandidate.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }

    final parsedRef = PriceRange.tryParse(json['reference']);
    final dirty = parsedRef != null && parsedRef.isDirty;

    final rawPoi = json['poi'];
    final rawRealTime = json['realTime'];

    return PriceQuote(
      kind: (json['kind'] as String?) ?? 'hotel',
      name: (json['name'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      poi: rawPoi is Map ? PriceCandidate.fromJson(Map<String, dynamic>.from(rawPoi)) : null,
      candidates: candidates,
      reference: dirty ? null : parsedRef,
      realTime: rawRealTime is Map
          ? PriceRealTime.fromJson(Map<String, dynamic>.from(rawRealTime))
          : const PriceRealTime(),
      source: (json['source'] as String?) ?? '',
      fetchedAt: (json['fetchedAt'] as String?) ?? '',
      fetchedAtText: (json['fetchedAtText'] as String?) ?? '',
      warning: json['warning'] as String?,
      isDirty: dirty,
    );
  }

  @override
  String toString() =>
      'PriceQuote($kind/$city:$name, ref=${reference?.text ?? '—'}, candidates=${candidates.length}, dirty=$isDirty)';
}
