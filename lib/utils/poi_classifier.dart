import '../models/trip_models.dart';

/// 高德 POI → 六类地点归类器（按 typecode 前缀）
///
/// 六类：美食(restaurant) 住宿(hotel) 游玩(attraction) 购物(shopping) 枢纽(transport) 其他(other)
/// 规则见《行程数据模型设计.md》：
/// - 枢纽仅指跨城级：机场1501xx / 火车站1502xx / 港口1503xx / 长途汽车站1504xx
/// - 地铁站1505xx、公交站1507xx 不作为点（属同城线属性）
/// - 道路附属18xxxx、地名地址19xxxx 过滤（1902xx 自然地名除外，归游玩）
class PoiClassifier {
  PoiClassifier._();

  /// 是否可作为行程停留点（false = 搜索结果中应过滤）
  static bool isStayable(String typecode) {
    if (typecode.isEmpty) return true; // 无 typecode 时保守保留
    if (typecode.startsWith('18')) return false;
    if (typecode.startsWith('19') && !typecode.startsWith('1902')) return false;
    // 地铁/公交站不作为点
    if (typecode.startsWith('1505') || typecode.startsWith('1507')) return false;
    return true;
  }

  /// typecode → 六类
  static LocationType classify(String typecode, {String name = ''}) {
    if (typecode.isEmpty) {
      // 无 typecode 时按名称关键词兜底
      if (name.contains('机场')) return LocationType.transport;
      if (name.contains('火车站') || name.contains('站')) return LocationType.transport;
      return LocationType.other;
    }
    if (typecode.startsWith('05')) return LocationType.restaurant; // 餐饮
    if (typecode.startsWith('10')) return LocationType.hotel; // 住宿
    if (typecode.startsWith('06')) return LocationType.shopping; // 购物
    if (typecode.startsWith('11')) return LocationType.attraction; // 风景名胜
    if (typecode.startsWith('14')) return LocationType.attraction; // 科教文化（博物馆/展馆）
    if (typecode.startsWith('08')) return LocationType.attraction; // 运动休闲（乐园/度假）
    if (typecode.startsWith('1902')) return LocationType.attraction; // 自然地名（西湖等）
    if (typecode.startsWith('15')) {
      // 交通设施：仅跨城枢纽作为点
      if (typecode.startsWith('1501') ||
          typecode.startsWith('1502') ||
          typecode.startsWith('1503') ||
          typecode.startsWith('1504')) {
        return LocationType.transport;
      }
      return LocationType.other; // 其余交通设施（停车场等）
    }
    return LocationType.other;
  }

  /// typecode → 枢纽子类型（仅 transport 类有意义）
  static String? hubKindOf(String typecode) {
    if (typecode.startsWith('1501')) return 'airport';
    if (typecode.startsWith('1502')) return 'station';
    if (typecode.startsWith('1503')) return 'port';
    if (typecode.startsWith('1504')) return 'bus';
    return null;
  }

  /// 跨城交通方式 → 对应枢纽子类型
  static String? hubKindForTransport(TransportType type) {
    switch (type) {
      case TransportType.flight:
        return 'airport';
      case TransportType.highSpeedTrain:
      case TransportType.train:
        return 'station';
      case TransportType.bus:
        return 'bus';
      case TransportType.ship:
        return 'port';
      default:
        return null;
    }
  }

  static String hubKindLabel(String? hubKind) {
    switch (hubKind) {
      case 'airport':
        return '机场';
      case 'station':
        return '火车站';
      case 'bus':
        return '汽车站';
      case 'port':
        return '港口';
      case 'rental':
        return '租车点';
      default:
        return '交通枢纽';
    }
  }
}
