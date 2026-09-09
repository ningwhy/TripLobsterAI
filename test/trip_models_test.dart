import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/trip_models.dart';
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
