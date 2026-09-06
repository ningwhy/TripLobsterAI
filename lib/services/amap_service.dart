import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// 高德地图 Web API 服务
/// 所有请求经后端代理转发（Key 仅存于服务端 .env，客户端零密钥）
/// 代理返回与高德完全一致的结构，模型解析不受影响
class AmapService {
  static const Duration _timeout = Duration(seconds: 15);

  String get _baseUrl => '${AppConfig.serverBaseUrl}/api/amap/v3';

  /// POI 关键字搜索
  /// https://lbs.amap.com/api/webservice/guide/search/text
  Future<List<AmapPoi>> searchPoi(String keyword, {String? city}) async {
    try {
      final params = {
        'keywords': keyword,
        // 不限制类型，返回所有POI
        'city': city ?? '',
        'citylimit': city != null ? 'true' : 'false',
        'output': 'json',
        'offset': '30',
        'page': '1',
        'extensions': 'all',
      };

      final uri = Uri.parse('$_baseUrl/place/text').replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1' && data['pois'] != null) {
          final pois = data['pois'] as List;
          return pois.map((p) => AmapPoi.fromJson(p)).toList();
        }
      }
      return [];
    } catch (e) {
      print('搜索失败: $e');
      return [];
    }
  }

  /// 获取 POI 详情
  Future<AmapPoi?> getPoiDetail(String poiId) async {
    try {
      final params = {
        'id': poiId,
        'extensions': 'all',
      };

      final uri = Uri.parse('$_baseUrl/place/detail').replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1' && data['pois'] != null) {
          final pois = data['pois'] as List;
          if (pois.isNotEmpty) {
            return AmapPoi.fromJson(pois.first);
          }
        }
      }
      return null;
    } catch (e) {
      print('获取详情失败: $e');
      return null;
    }
  }

  /// 驾车路线规划
  /// https://lbs.amap.com/api/webservice/guide/newroute/route
  Future<AmapRoute?> drivingRoute({
    required double originLng,
    required double originLat,
    required double destinationLng,
    required double destinationLat,
  }) async {
    try {
      final params = {
        'origin': '$originLng,$originLat',
        'destination': '$destinationLng,$destinationLat',
        'strategy': '0', // 0：最快速模式
        'extensions': 'all',
      };

      final uri = Uri.parse('$_baseUrl/direction/driving').replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1' && data['route'] != null) {
          return AmapRoute.fromJson(data['route']);
        }
      }
      return null;
    } catch (e) {
      print('路线规划失败: $e');
      return null;
    }
  }

  /// 公交路线规划
  Future<AmapRoute?> transitRoute({
    required double originLng,
    required double originLat,
    required double destinationLng,
    required double destinationLat,
    String? city,
  }) async {
    try {
      final params = {
        'origin': '$originLng,$originLat',
        'destination': '$destinationLng,$destinationLat',
        'city': city ?? 'beijing',
        'strategy': '0', // 0：最快捷
        'extensions': 'all',
      };

      final uri = Uri.parse('$_baseUrl/direction/transit/integrated').replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1' && data['route'] != null) {
          return AmapRoute.fromJson(data['route']);
        }
      }
      return null;
    } catch (e) {
      print('公交路线规划失败: $e');
      return null;
    }
  }

  /// 步行路线规划
  Future<AmapRoute?> walkingRoute({
    required double originLng,
    required double originLat,
    required double destinationLng,
    required double destinationLat,
  }) async {
    try {
      final params = {
        'origin': '$originLng,$originLat',
        'destination': '$destinationLng,$destinationLat',
        'extensions': 'all',
      };

      final uri = Uri.parse('$_baseUrl/direction/walking').replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1' && data['route'] != null) {
          return AmapRoute.fromJson(data['route']);
        }
      }
      return null;
    } catch (e) {
      print('步行路线规划失败: $e');
      return null;
    }
  }

  /// 地理编码（地址转坐标）
  Future<AmapGeocode?> geocode(String address, {String? city}) async {
    try {
      final params = {
        'address': address,
        'city': city ?? '',
      };

      final uri = Uri.parse('$_baseUrl/geocode/geo').replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1' && data['geocodes'] != null) {
          final geocodes = data['geocodes'] as List;
          if (geocodes.isNotEmpty) {
            return AmapGeocode.fromJson(geocodes.first);
          }
        }
      }
      return null;
    } catch (e) {
      print('地理编码失败: $e');
      return null;
    }
  }

  /// 逆地理编码（坐标转地址）
  Future<AmapReGeocode?> reGeocode(double lng, double lat) async {
    try {
      final params = {
        'location': '$lng,$lat',
        'extensions': 'all',
        'radius': '1000',
      };

      final uri = Uri.parse('$_baseUrl/geocode/regeo').replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '1' && data['regeocode'] != null) {
          return AmapReGeocode.fromJson(data['regeocode']);
        }
      }
      return null;
    } catch (e) {
      print('逆地理编码失败: $e');
      return null;
    }
  }
}

/// POI 点位
class AmapPoi {
  final String id;
  final String name;
  final String type;
  final String typecode;
  final String address;
  final String location; // 经纬度 "lng,lat"
  final String city;
  final String district;
  final double? lat;
  final double? lng;

  AmapPoi({
    required this.id,
    required this.name,
    required this.type,
    required this.typecode,
    required this.address,
    required this.location,
    required this.city,
    required this.district,
    this.lat,
    this.lng,
  });

  factory AmapPoi.fromJson(Map<String, dynamic> json) {
    double? lat;
    double? lng;
    if (json['location'] != null && json['location'].contains(',')) {
      final parts = json['location'].split(',');
      lng = double.tryParse(parts[0]);
      lat = double.tryParse(parts[1]);
    }

    return AmapPoi(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      typecode: json['typecode'] ?? '',
      address: json['address'] ?? '',
      location: json['location'] ?? '',
      city: json['city'] ?? '',
      district: json['district'] ?? '',
      lat: lat,
      lng: lng,
    );
  }

  String get cityName => city.isNotEmpty ? city : district;
}

/// 路线规划结果
class AmapRoute {
  final String origin; // 起点坐标
  final String destination; // 终点坐标
  final List<AmapPath> paths; // 路线列表
  final int distance; // 总距离(米)
  final int duration; // 总时间(秒)

  AmapRoute({
    required this.origin,
    required this.destination,
    required this.paths,
    required this.distance,
    required this.duration,
  });

  factory AmapRoute.fromJson(Map<String, dynamic> json) {
    List<AmapPath> paths = [];
    if (json['paths'] != null) {
      final pathList = json['paths'] as List;
      paths = pathList.map((p) => AmapPath.fromJson(p)).toList();
    }

    return AmapRoute(
      origin: json['origin'] ?? '',
      destination: json['destination'] ?? '',
      paths: paths,
      distance: int.tryParse(json['distance']?.toString() ?? '0') ?? 0,
      duration: int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
    );
  }

  String get durationText {
    final hours = duration ~/ 3600;
    final mins = (duration % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}小时${mins}分钟';
    }
    return '${mins}分钟';
  }

  String get distanceText {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(1)}公里';
    }
    return '${distance}米';
  }
}

/// 单条路线
class AmapPath {
  final int distance; // 距离(米)
  final int duration; // 时间(秒)
  final List<AmapStep> steps; // 步骤列表

  AmapPath({
    required this.distance,
    required this.duration,
    required this.steps,
  });

  factory AmapPath.fromJson(Map<String, dynamic> json) {
    List<AmapStep> steps = [];
    if (json['steps'] != null) {
      final stepList = json['steps'] as List;
      steps = stepList.map((s) => AmapStep.fromJson(s)).toList();
    }

    return AmapPath(
      distance: int.tryParse(json['distance']?.toString() ?? '0') ?? 0,
      duration: int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
      steps: steps,
    );
  }
}

/// 路线步骤
class AmapStep {
  final String instruction; // 导航描述
  final String road; // 道路名称
  final int distance; // 距离(米)
  final int duration; // 时间(秒)
  final String polyline; // 坐标点串

  AmapStep({
    required this.instruction,
    required this.road,
    required this.distance,
    required this.duration,
    required this.polyline,
  });

  factory AmapStep.fromJson(Map<String, dynamic> json) {
    return AmapStep(
      instruction: json['instruction'] ?? '',
      road: json['road'] ?? '',
      distance: int.tryParse(json['distance']?.toString() ?? '0') ?? 0,
      duration: int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
      polyline: json['polyline'] ?? '',
    );
  }
}

/// 地理编码结果
class AmapGeocode {
  final String province;
  final String city;
  final String district;
  final String location; // "lng,lat"

  AmapGeocode({
    required this.province,
    required this.city,
    required this.district,
    required this.location,
  });

  factory AmapGeocode.fromJson(Map<String, dynamic> json) {
    return AmapGeocode(
      province: json['province'] ?? '',
      city: json['city'] ?? '',
      district: json['district'] ?? '',
      location: json['location'] ?? '',
    );
  }

  double? get lat {
    if (location.isEmpty || !location.contains(',')) return null;
    return double.tryParse(location.split(',')[1]);
  }

  double? get lng {
    if (location.isEmpty || !location.contains(',')) return null;
    return double.tryParse(location.split(',')[0]);
  }
}

/// 逆地理编码结果
class AmapReGeocode {
  final String province;
  final String city;
  final String district;
  final String township;
  final String street;
  final String number;
  final String description;

  AmapReGeocode({
    required this.province,
    required this.city,
    required this.district,
    required this.township,
    required this.street,
    required this.number,
    required this.description,
  });

  factory AmapReGeocode.fromJson(Map<String, dynamic> json) {
    final address = json['addressComponent'] ?? {};
    return AmapReGeocode(
      province: address['province'] ?? '',
      city: address['city'] ?? '',
      district: address['district'] ?? '',
      township: address['township'] ?? '',
      street: address['street'] ?? '',
      number: address['number'] ?? '',
      description: json['formatted_address'] ?? '',
    );
  }

  String get fullAddress => description;
}

/// 跨城公共交通班次
class IntercityTransitLine {
  final String type; // 交通类型：flight(飞机), train(火车), bus(汽车)
  final String lineName; // 航班号/车次号
  final String departureTime; // 出发时间
  final String arrivalTime; // 到达时间
  final int duration; // 耗时(分钟)
  final double? price; // 价格(元)
  final String? airline; // 航空公司
  final String? airport; // 出发/到达机场

  IntercityTransitLine({
    required this.type,
    required this.lineName,
    required this.departureTime,
    required this.arrivalTime,
    required this.duration,
    this.price,
    this.airline,
    this.airport,
  });

  factory IntercityTransitLine.fromJson(Map<String, dynamic> json, String type) {
    return IntercityTransitLine(
      type: type,
      lineName: json['line_name'] ?? json['flight_no'] ?? json['train_no'] ?? '',
      departureTime: json['dep_time'] ?? '',
      arrivalTime: json['arr_time'] ?? '',
      duration: int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
      price: double.tryParse(json['price']?.toString() ?? ''),
      airline: json['airline'],
      airport: json['dep_airport'] ?? json['arr_airport'],
    );
  }

  String get typeIcon {
    switch (type) {
      case 'flight':
        return '✈️';
      case 'train':
        return '🚄';
      case 'bus':
        return '🚌';
      default:
        return '🚗';
    }
  }

  String get typeName {
    switch (type) {
      case 'flight':
        return '飞机';
      case 'train':
        return '火车';
      case 'bus':
        return '汽车';
      default:
        return '其他';
    }
  }
}

/// 跨城公共交通规划结果
class IntercityTransitResult {
  final String origin;
  final String destination;
  final List<IntercityTransitLine> flights;
  final List<IntercityTransitLine> trains;
  final List<IntercityTransitLine> buses;

  IntercityTransitResult({
    required this.origin,
    required this.destination,
    required this.flights,
    required this.trains,
    required this.buses,
  });

  List<IntercityTransitLine> get allLines => [...flights, ...trains, ...buses];
}

/// 高德跨城公共交通规划 API
/// https://lbs.amap.com/api/webservice/guide/newroute/intercity-transit
Future<IntercityTransitResult?> getIntercityTransit({
  required double originLng,
  required double originLat,
  required double destinationLng,
  required double destinationLat,
  String? originCity,
  String? destinationCity,
}) async {
  try {
    final params = <String, String>{
      'origin': '$originLng,$originLat',
      'destination': '$destinationLng,$destinationLat',
      'strategy': '0', // 0:最经济, 1:最快捷, 2:最少换乘
      'extensions': 'all',
    };

    // 添加城市名称（如果提供）
    if (originCity != null && originCity.isNotEmpty) {
      params['city'] = originCity;
    }
    if (destinationCity != null && destinationCity.isNotEmpty) {
      params['destinationCity'] = destinationCity;
    }

    final uri = Uri.parse('${AppConfig.serverBaseUrl}/api/amap/v3/intercity/transit').replace(queryParameters: params);

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
  
      if (data['status'] != '1') {
        return null;
      }

      final List<IntercityTransitLine> flights = [];
      final List<IntercityTransitLine> trains = [];
      final List<IntercityTransitLine> buses = [];

        // 解析航班
        if (data['flight'] != null) {
          final flightList = data['flight'] as List;
          for (var f in flightList) {
            flights.add(IntercityTransitLine.fromJson(f, 'flight'));
          }
        }

        // 解析火车
        if (data['train'] != null) {
          final trainList = data['train'] as List;
          for (var t in trainList) {
            trains.add(IntercityTransitLine.fromJson(t, 'train'));
          }
        }

        // 解析汽车
        if (data['bus'] != null) {
          final busList = data['bus'] as List;
          for (var b in busList) {
            buses.add(IntercityTransitLine.fromJson(b, 'bus'));
          }
        }

        return IntercityTransitResult(
          origin: '$originLng,$originLat',
          destination: '$destinationLng,$destinationLat',
          flights: flights,
          trains: trains,
          buses: buses,
        );
      }
      return null;
    } catch (e) {
      print('跨城公共交通规划失败: $e');
      return null;
    }
  }
