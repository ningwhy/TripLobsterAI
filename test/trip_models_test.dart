import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/models/trip_cost.dart';
import 'package:trip_planner/utils/poi_classifier.dart';

void main() {
  group('Trip 模型序列化', () {
    test('toJson/fromJson 往返一致', () {
      final trip = Trip(
        name: '杭州3日游',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 3),
        days: [
          TripDay(
            date: DateTime(2026, 10, 1),
            dayNumber: 1,
            locations: [
              Location(
                name: '西湖',
                address: '杭州市西湖区',
                latitude: 30.22,
                longitude: 120.15,
                city: '杭州',
                type: LocationType.attraction,
                stayMinutes: 120,
                transportMinutes: 30,
                openTime: '08:00',
                closeTime: '18:00',
              ),
            ],
          ),
        ],
      );

      final restored = Trip.fromJson(trip.toJson());

      expect(restored.id, trip.id);
      expect(restored.name, '杭州3日游');
      expect(restored.days.length, 1);
      final loc = restored.days.first.locations.first;
      expect(loc.name, '西湖');
      expect(loc.type, LocationType.attraction);
      expect(loc.stayMinutes, 120);
      expect(loc.latitude, 30.22);
      expect(loc.openTime, '08:00');
    });

    test('totalMinutes 计算 = 停留 + 交通', () {
      final day = TripDay(
        date: DateTime(2026, 10, 1),
        dayNumber: 1,
        locations: [
          Location(name: 'A', address: '', type: LocationType.attraction, stayMinutes: 90, transportMinutes: 20),
          Location(name: 'B', address: '', type: LocationType.restaurant, stayMinutes: 60),
        ],
      );
      expect(day.totalMinutes, 170);
    });

    test('allLocations 拍平所有天', () {
      final trip = Trip(
        name: 't',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 2),
        days: [
          TripDay(date: DateTime(2026, 10, 1), dayNumber: 1, locations: [
            Location(name: 'A', address: '', type: LocationType.attraction),
          ]),
          TripDay(date: DateTime(2026, 10, 2), dayNumber: 2, locations: [
            Location(name: 'B', address: '', type: LocationType.attraction),
            Location(name: 'C', address: '', type: LocationType.attraction),
          ]),
        ],
      );
      expect(trip.allLocations.length, 3);
      expect(trip.totalDays, 2);
    });
  });

  group('同城判断（跨城交通触发依据）', () {
    test('相同 city 判同城', () {
      final a = Location(name: 'A', address: 'xx路', city: '杭州', type: LocationType.attraction);
      final b = Location(name: 'B', address: 'yy路', city: '杭州', type: LocationType.restaurant);
      expect(a.isSameCity(b), isTrue);
    });

    test('不同 city 判跨城', () {
      final a = Location(name: 'A', address: 'xx路', city: '杭州', type: LocationType.attraction);
      final b = Location(name: 'B', address: 'yy路', city: '苏州', type: LocationType.attraction);
      expect(a.isSameCity(b), isFalse);
    });

    test('无 city 字段时从地址解析', () {
      final a = Location(name: 'A', address: '浙江省杭州市西湖区xx路', type: LocationType.attraction);
      expect(a.cityName, contains('杭州'));
    });
  });

  group('点线模型（tripMode / scope / hubKind）', () {
    test('Trip.tripMode 序列化往返', () {
      final trip = Trip(
        name: 't',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 2),
        tripMode: TripMode.transitPlusRental,
      );
      final r = Trip.fromJson(trip.toJson());
      expect(r.tripMode, TripMode.transitPlusRental);
    });

    test('Transport.scope 代替旧 category', () {
      final t = Transport(type: TransportType.ship, scope: TransportScope.intercity);
      final r = Transport.fromJson(t.toJson());
      expect(r.scope, TransportScope.intercity);
      expect(r.isIntercity, isTrue);
      expect(t.displayName, contains('轮船'));
    });

    test('Location.hubKind 序列化', () {
      final loc = Location(name: '虹桥机场', address: '上海', type: LocationType.transport, hubKind: 'airport');
      final r = Location.fromJson(loc.toJson());
      expect(r.hubKind, 'airport');
    });
  });

  group('T02 新增字段（toJson/fromJson 往返 + 旧数据兼容）', () {
    test('Location 新增字段往返一致', () {
      final loc = Location(
        name: '威海某酒店',
        address: '威海市某路1号',
        type: LocationType.hotel,
        arrivalTime: '18:20',
        leaveTime: '08:00',
        rating: 4.6,
        stayNote: '连住',
        cost: '300-500',
        fixed: true,
      );
      final r = Location.fromJson(loc.toJson());
      expect(r.arrivalTime, '18:20');
      expect(r.leaveTime, '08:00');
      expect(r.rating, 4.6);
      expect(r.stayNote, '连住');
      expect(r.cost, '300-500');
      expect(r.fixed, isTrue); // 【裁 4】fixed 进 toJson，云同步可带走
    });

    test('Location 旧数据缺字段不崩（向后兼容）', () {
      final r = Location.fromJson(<String, dynamic>{
        'name': '旧景点', 'address': '旧地址', 'type': 'attraction',
      });
      expect(r.arrivalTime, isNull);
      expect(r.leaveTime, isNull);
      expect(r.rating, isNull);
      expect(r.stayNote, isNull);
      expect(r.cost, isNull);
      expect(r.fixed, isFalse);
    });

    test('Transport 新增字段往返一致', () {
      final t = Transport(
        type: TransportType.highSpeedTrain,
        scope: TransportScope.intercity,
        flightNumber: 'G123',
        price: 268,
        isFixed: true,
        estimated: false,
      );
      final r = Transport.fromJson(t.toJson());
      expect(r.price, 268);
      expect(r.isFixed, isTrue);
      expect(r.estimated, isFalse);
      expect(r.isScheduled, isTrue);
      expect(r.isEstimate, isFalse);
    });

    test('Transport 旧数据缺字段不崩（generate 管线恒 null）', () {
      final r = Transport.fromJson(<String, dynamic>{
        'type': 'selfDrive', 'scope': 'intraCity',
      });
      expect(r.price, isNull);
      expect(r.isFixed, isNull);
      expect(r.estimated, isNull);
      expect(r.isScheduled, isFalse);
      expect(r.isEstimate, isFalse);
    });

    test('Trip.fromPlannerResponse 从 stats.cost 取到值', () {
      final trip = Trip.fromPlannerResponse(<String, dynamic>{
        'trip': <String, dynamic>{
          'name': '北京环线4日',
          'startDate': '2026-10-01',
          'endDate': '2026-10-04',
          'days': <dynamic>[],
        },
        'stats': <String, dynamic>{
          'cost': <String, dynamic>{
            'currency': 'CNY',
            'items': <String, dynamic>{'fuel': 180, 'toll': 135, 'bad': 'x'},
            'total': 315,
            'note': 'n',
          },
        },
      });
      expect(trip.statsCost, isNotNull);
      expect(trip.statsCost!.total, 315);
      expect(trip.statsCost!.items.containsKey('bad'), isFalse);
    });

    test('无 stats.cost → null（本次不接 corridor，端上恒 null）', () {
      final trip = Trip.fromPlannerResponse(<String, dynamic>{
        'trip': <String, dynamic>{
          'name': 'x', 'startDate': '2026-10-01', 'endDate': '2026-10-02', 'days': <dynamic>[],
        },
      });
      expect(trip.statsCost, isNull);
    });

    test('statsCost 是运行时字段：不进 toJson', () {
      final trip = Trip(
        name: 'x',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 2),
        statsCost: const TripCost(total: 999),
      );
      expect(trip.statsCost!.total, 999);
      expect(trip.toJson().containsKey('statsCost'), isFalse);
    });
  });

  group('POI 六类归类器', () {
    test('餐饮 05 → 美食', () => expect(PoiClassifier.classify('050100'), LocationType.restaurant));
    test('住宿 10 → 住宿', () => expect(PoiClassifier.classify('100100'), LocationType.hotel));
    test('风景 11 → 游玩', () => expect(PoiClassifier.classify('110200'), LocationType.attraction));
    test('博物馆 14 → 游玩', () => expect(PoiClassifier.classify('140100'), LocationType.attraction));
    test('购物 06 → 购物', () => expect(PoiClassifier.classify('060101'), LocationType.shopping));
    test('机场 1501 → 枢纽+airport', () {
      expect(PoiClassifier.classify('150100'), LocationType.transport);
      expect(PoiClassifier.hubKindOf('150100'), 'airport');
    });
    test('火车站 1502 → station，港口 1503 → port，汽车站 1504 → bus', () {
      expect(PoiClassifier.hubKindOf('150200'), 'station');
      expect(PoiClassifier.hubKindOf('150300'), 'port');
      expect(PoiClassifier.hubKindOf('150400'), 'bus');
    });
    test('地铁站/公交站不作为停留点', () {
      expect(PoiClassifier.isStayable('150500'), isFalse);
      expect(PoiClassifier.isStayable('150700'), isFalse);
    });
    test('自然地名 1902 → 游玩，其余 19/18 过滤', () {
      expect(PoiClassifier.classify('190205'), LocationType.attraction);
      expect(PoiClassifier.isStayable('190100'), isFalse);
      expect(PoiClassifier.isStayable('180300'), isFalse);
    });
    test('跨城工具 → 枢纽子类型', () {
      expect(PoiClassifier.hubKindForTransport(TransportType.flight), 'airport');
      expect(PoiClassifier.hubKindForTransport(TransportType.highSpeedTrain), 'station');
      expect(PoiClassifier.hubKindForTransport(TransportType.ship), 'port');
      expect(PoiClassifier.hubKindForTransport(TransportType.selfDrive), isNull);
    });
  });
}
