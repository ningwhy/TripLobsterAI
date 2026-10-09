// 运行时模型：不进 Trip.toJson
//
// 对应 `GET /api/weather`（server/src/weather.js，Open-Meteo 免 Key 代理，16 天预报）。
// 内存缓存 key = `{city}_{date}`（由 WeatherRepository 维护），不落库、不云同步。
//
// 两条硬约束（PRD §5.5）：
//   · 不换算蒲福风级，只显示原始风速 km/h + 16 方位缩写（换算需引入又一套无数据源口径）。
//   · 预报窗口 16 天：日期超出窗口 → `fromOpenMeteoByDate` 返回 null → 徽章整块隐藏，
//     禁止用最后一天充数、禁止留空白占位块。

/// 单日天气（某一天 + 某个取点城市）
class DayWeather {
  /// `yyyy-MM-dd`，必须与分组头日期完全一致（M4 验收项）
  final String date;
  final double max;
  final double min;

  /// WMO `weather_code`；缺失/不可解析时为 -1（→ 描述「未知」+ emoji 🌀）
  final int code;

  /// 中文描述（由 code 映射）
  final String desc;

  /// emoji（由 code 映射）
  final String iconEmoji;

  /// 风文案：`NW 10km/h`；WX-02 之前服务端不返回风字段 → null（风段整块隐藏）
  final String? windText;

  const DayWeather({
    required this.date,
    required this.max,
    required this.min,
    required this.code,
    required this.desc,
    required this.iconEmoji,
    this.windText,
  });

  /// 温度文案：`25°/14°`
  String get tempText => '${max.round()}°/${min.round()}°';

  /// 是否为"未知"天气（code 缺失或未命中映射表）
  bool get isUnknown => code < 0;

  Map<String, dynamic> toJson() => {
        'date': date,
        'max': max,
        'min': min,
        'code': code,
        'desc': desc,
        'iconEmoji': iconEmoji,
        'windText': windText,
      };

  factory DayWeather.fromJson(Map<String, dynamic> json) => DayWeather(
        date: (json['date'] as String?) ?? '',
        max: (json['max'] as num?)?.toDouble() ?? 0,
        min: (json['min'] as num?)?.toDouble() ?? 0,
        code: (json['code'] as num?)?.round() ?? -1,
        desc: (json['desc'] as String?) ?? wmoDesc(-1),
        iconEmoji: (json['iconEmoji'] as String?) ?? wmoEmoji(-1),
        windText: json['windText'] as String?,
      );

  /// 按**下标**取某天（设计文档签名 `fromOpenMeteo(Map,int)`）。
  /// 下标越界或 daily 结构异常 → null（绝不越界取最后一天充数）。
  static DayWeather? fromOpenMeteo(Map<String, dynamic> json, int index) {
    final daily = json['daily'];
    if (daily is! Map) return null;
    final times = daily['time'];
    if (times is! List || index < 0 || index >= times.length) return null;
    return _build(daily, times[index].toString());
  }

  /// 按**日期**取某天（A-8：日期不在预报窗口内 → null → 徽章整块隐藏）。
  /// 这是 UI 唯一应使用的入口，保证"徽章日期 == 分组头日期"（M4）。
  static DayWeather? fromOpenMeteoByDate(Map<String, dynamic> json, String date) {
    final daily = json['daily'];
    if (daily is! Map) return null;
    final times = daily['time'];
    if (times is! List) return null;
    final idx = times.map((e) => e.toString()).toList().indexOf(date);
    if (idx < 0) return null; // 超出 16 天窗口 → 明确无数据
    return _build(daily, date);
  }

  static DayWeather _build(Map<dynamic, dynamic> daily, String date) {
    num? at(String key) {
      final arr = daily[key];
      if (arr is! List) return null;
      final times = daily['time'];
      if (times is! List) return null;
      final idx = times.map((e) => e.toString()).toList().indexOf(date);
      if (idx < 0 || idx >= arr.length) return null;
      final v = arr[idx];
      return v is num ? v : num.tryParse(v.toString());
    }

    final codeRaw = at('weather_code');
    final code = codeRaw == null ? -1 : codeRaw.round();
    final maxRaw = at('temperature_2m_max');
    final minRaw = at('temperature_2m_min');

    // WX-02：风字段可能缺失（旧服务端 / 上游未返回）→ windText 为 null，风段整块隐藏
    final windRaw = at('wind_speed_10m_max');
    final dirRaw = at('wind_direction_10m_dominant');
    String? windText;
    if (windRaw != null) {
      final kmh = windRaw.round();
      final dir = windDir16(dirRaw);
      windText = dir.isEmpty ? '${kmh}km/h' : '$dir ${kmh}km/h';
    }

    return DayWeather(
      date: date,
      max: maxRaw?.toDouble() ?? 0,
      min: minRaw?.toDouble() ?? 0,
      code: code,
      desc: wmoDesc(code),
      iconEmoji: wmoEmoji(code),
      windText: windText,
    );
  }

  // ---------------- WMO weather_code → 中文描述 ----------------
  // 未命中 → 「未知」（PRD §5.5 映射表原样落地）
  static String wmoDesc(int code) => _wmoText[code] ?? '未知';

  static String wmoEmoji(int code) => _wmoEmoji[code] ?? '🌀';

  static const Map<int, String> _wmoText = <int, String>{
    0: '晴',
    1: '大部晴朗',
    2: '局部多云',
    3: '阴',
    45: '雾',
    48: '雾凇',
    51: '毛毛雨',
    53: '毛毛雨',
    55: '毛毛雨',
    56: '冻毛毛雨',
    57: '冻毛毛雨',
    61: '小雨',
    63: '中雨',
    65: '大雨',
    66: '冻雨',
    67: '冻雨',
    71: '小雪',
    73: '中雪',
    75: '大雪',
    77: '米雪',
    80: '阵雨',
    81: '阵雨',
    82: '阵雨',
    85: '阵雪',
    86: '阵雪',
    95: '雷阵雨',
    96: '雷暴伴冰雹',
    99: '雷暴伴冰雹',
  };

  static const Map<int, String> _wmoEmoji = <int, String>{
    0: '☀️',
    1: '🌤',
    2: '⛅',
    3: '☁️',
    45: '🌫',
    48: '🌫',
    51: '🌦',
    53: '🌦',
    55: '🌦',
    56: '🌧',
    57: '🌧',
    61: '🌧',
    63: '🌧',
    65: '🌧',
    66: '🌧',
    67: '🌧',
    71: '❄️',
    73: '❄️',
    75: '❄️',
    77: '❄️',
    80: '🌦',
    81: '🌦',
    82: '🌦',
    85: '❄️',
    86: '❄️',
    95: '⛈',
    96: '⛈',
    99: '⛈',
  };

  /// 风向度 → 16 方位缩写（N / NNE / NE / ENE / E …）
  ///
  /// 度数为 null 或非法时返回空串（调用方据此隐藏风向，只显示风速）。
  static String windDir16(num? degrees) {
    if (degrees == null) return '';
    final d = degrees.toDouble();
    if (!d.isFinite) return '';
    final normalized = ((d % 360) + 360) % 360;
    // 16 方位每格 22.5°，区间居中：N 覆盖 [348.75°, 360°) ∪ [0°, 11.25°)
    const names = <String>[
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final idx = ((normalized + 11.25) / 22.5).floor() % 16;
    return names[idx];
  }

  @override
  String toString() =>
      'DayWeather($date $desc$iconEmoji $tempText${windText == null ? '' : ' $windText'})';
}
