import 'package:uuid/uuid.dart';

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

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'],
    name: json['name'],
    startDate: DateTime.parse(json['startDate']),
    endDate: DateTime.parse(json['endDate']),
    days: (json['days'] as List).map((d) => TripDay.fromJson(d)).toList(),
    homeLocation: json['homeLocation'] != null ? HomeLocation.fromJson(json['homeLocation']) : null,
    members: (json['members'] as List).map((m) => Member.fromJson(m)).toList(),
    tripMode: TripMode.values.firstWhere((e) => e.name == json['tripMode'], orElse: () => TripMode.pureTransit),
    adults: json['adults'] ?? 2,
    children: json['children'] ?? 0,
    rooms: json['rooms'] ?? 1,
    roomType: roomTypeFromName(json['roomType']),
    budget: json['budget'] ?? 'comfort',
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );
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
    return '${hours}小时${mins > 0 ? "${mins}分钟" : ""}';
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
    locations: (json['locations'] as List).map((l) => Location.fromJson(l)).toList(),
  );
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
  }) : id = id ?? const Uuid().v4();

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
  };

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    id: json['id'],
    name: json['name'],
    address: json['address'],
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
  );
}

class Transport {
  final String id;
  TransportType type;
  TransportScope scope;
  String? flightNumber;
  String? departureTime;
  String? arrivalTime;
  int? durationMinutes;
  double? distance;

  Transport({
    String? id,
    required this.type,
    required this.scope,
    this.flightNumber,
    this.departureTime,
    this.arrivalTime,
    this.durationMinutes,
    this.distance,
  }) : id = id ?? const Uuid().v4();

  bool get isIntercity => scope == TransportScope.intercity;

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
