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

  //本组回归针对一个**真实运行时崩溃**：`Location.address` 声明为非空 `String`，
  // 而 `fromJson` 原直接 `address: json['address']`。服务端任一条 POI 缺 address 时，
  // null 赋给非空 String 会抛类型错误、整页崩，而非安全降级为「无地址」。
  // 由 `flutter analyze` 的 dead_null_aware_expression 顺带暴露。
  group('Location.fromJson 缺字段兜底（address 为非空 String）', () {
    test('完全无 address 键 → 空串，不抛类型错误', () {
      final loc = Location.fromJson({'id': 'A1', 'name': '某店', 'type': 'restaurant'});
      expect(loc.address, '');
    });

    test('address 显式为 null → 空串', () {
      final loc = Location.fromJson({
        'id': 'A2',
        'name': '某店',
        'type': 'restaurant',
        'address': null,
      });
      expect(loc.address, '');
    });

    test('address 正常 → 原样保留', () {
      final loc = Location.fromJson({
        'id': 'A3',
        'name': '某店',
        'type': 'restaurant',
        'address': '北京市东城区某某路 1 号',
      });
      expect(loc.address, '北京市东城区某某路 1 号');
    });

    test('city 缺失仍为 null（它是真正的可空字段，勿一并兜底成空串）', () {
      final loc = Location.fromJson({'id': 'A4', 'name': '某店', 'type': 'restaurant'});
      expect(loc.city, isNull);
    });

    test('最小可用POI 即可解析，不因可选字段缺失而崩', () {
      final loc = Location.fromJson({'name': '只有名字'});
      expect(loc.name, '只有名字');
      expect(loc.address, '');
      expect(loc.type, LocationType.other);
    });
  });

  // ==========================================================================
  // T03：日期感知营业事实（openHoursRaw / lastEntryTime / closedOnDate / openSegments）
  // ==========================================================================
  group('Location 营业事实字段（T03）', () {
    test('四个新字段全部进 toJson（要云同步，漏一个就丢一条链路）', () {
      final loc = Location(
        name: '故宫博物院',
        address: '北京市东城区景山前街4号',
        type: LocationType.attraction,
        openTime: '08:30',
        closeTime: '17:00',
        lastEntryTime: '16:00',
        closedOnDate: false,
        openHoursRaw: '旺季 08:30-17:00，16:00 停止检票',
        openSegments: const [OpenSegment(open: '08:30', close: '17:00', lastEntry: '16:00')],
      );

      final json = loc.toJson();
      expect(json['lastEntryTime'], '16:00');
      expect(json['closedOnDate'], false);
      expect(json['openHoursRaw'], '旺季 08:30-17:00，16:00 停止检票');
      expect(json['openSegments'], isA<List>());
      expect((json['openSegments'] as List).length, 1);
      expect((json['openSegments'] as List).first['open'], '08:30');
    });

    test('云同步往返：四个新字段一个都不丢', () {
      final loc = Location(
        name: '苏州博物馆',
        address: '苏州市姑苏区',
        type: LocationType.attraction,
        closedOnDate: true,
        openHoursRaw: '周一闭馆',
        openSegments: const [OpenSegment(open: '09:00', close: '17:00')],
      );
      final restored = Location.fromJson(loc.toJson());

      expect(restored.closedOnDate, true);
      expect(restored.openHoursRaw, '周一闭馆');
      expect(restored.lastEntryTime, isNull);
      expect(restored.openSegments?.length, 1);
      expect(restored.openSegments!.first.close, '17:00');
    });

    test('旧 JSON 缺四个新键 → 全 null，不抛异常', () {
      // 这是"老行程"的真实形态：服务端还没下发营业事实时的存量数据。
      // 期望是 null（未知 → CH-09），**不是** false / 空串 / 空数组。
      final loc = Location.fromJson({
        'id': 'OLD-1',
        'name': '老行程景点',
        'address': '某地',
        'type': 'attraction',
        'openTime': '08:00',
        'closeTime': '18:00',
      });

      expect(loc.openHoursRaw, isNull);
      expect(loc.lastEntryTime, isNull);
      expect(loc.closedOnDate, isNull);
      expect(loc.openSegments, isNull);
    });

    test('fromJson 兼容服务端别名 closedOnThisDate', () {
      final closed = Location.fromJson({
        'name': '国博',
        'type': 'attraction',
        'closedOnThisDate': true,
        'openHoursRaw': '周一闭馆（法定节假日除外）',
      });
      expect(closed.closedOnDate, true);

      final open = Location.fromJson({
        'name': '国博',
        'type': 'attraction',
        'closedOnThisDate': false,
        'openTime': '09:00',
        'closeTime': '17:00',
        'openHoursRaw': '09:00-17:00',
      });
      expect(open.closedOnDate, false);
    });

    test('closedOnDate 三态：非 bool 值一律当未知，绝不折叠成 false', () {
      // 三态是本次修复的核心：null 表示"没校验"，绝不等于 false（明确开放）。
      expect(Location.fromJson({'name': 'a', 'closedOnDate': null}).closedOnDate, isNull);
      expect(Location.fromJson({'name': 'a', 'closedOnDate': 0}).closedOnDate, isNull);
      expect(Location.fromJson({'name': 'a', 'closedOnDate': 'false'}).closedOnDate, isNull);
      expect(Location.fromJson({'name': 'a', 'closedOnDate': []}).closedOnDate, isNull);
    });

    test('openSegments 缺 open 或 close 的脏元素被丢弃，不补空串占位', () {
      final loc = Location.fromJson({
        'name': '多时段餐厅',
        'type': 'restaurant',
        'openSegments': [
          {'open': '11:00', 'close': '14:00'},
          {'open': '16:00'}, // 缺 close → 丢弃
          {'close': '22:00'}, // 缺 open  → 丢弃
          'not-a-map', // 类型不对   → 丢弃
        ],
      });
      expect(loc.openSegments?.length, 1);
      expect(loc.openSegments!.single.open, '11:00');
      expect(loc.openSegments!.single.close, '14:00');
      expect(loc.openSegments!.single.lastEntry, isNull);
    });

    test('clearOpenHoursFacts 清空全部营业事实（改日期后不得沿用旧结论）', () {
      final loc = Location(
        name: '故宫',
        address: '北京',
        type: LocationType.attraction,
        openTime: '08:30',
        closeTime: '17:00',
        lastEntryTime: '16:00',
        closedOnDate: false,
        openHoursRaw: '旺季 08:30-17:00',
        openSegments: const [OpenSegment(open: '08:30', close: '17:00')],
      );

      loc.clearOpenHoursFacts();

      expect(loc.openTime, isNull);
      expect(loc.closeTime, isNull);
      expect(loc.lastEntryTime, isNull);
      expect(loc.closedOnDate, isNull);
      expect(loc.openHoursRaw, isNull);
      expect(loc.openSegments, isNull);
    });

    test('Trip 整体往返：新字段随 Location 一起云同步', () {
      final trip = Trip(
        name: '北京2日',
        startDate: DateTime(2026, 10, 13),
        endDate: DateTime(2026, 10, 14),
        days: [
          TripDay(
            date: DateTime(2026, 10, 13),
            dayNumber: 1,
            locations: [
              Location(
                name: '故宫',
                address: '北京',
                type: LocationType.attraction,
                arrivalTime: '09:00',
                openTime: '08:30',
                closeTime: '17:00',
                lastEntryTime: '16:00',
                closedOnDate: false,
                openHoursRaw: '08:30-17:00，16:00 停止检票',
                openSegments: const [OpenSegment(open: '08:30', close: '17:00', lastEntry: '16:00')],
              ),
            ],
          ),
        ],
      );

      final restored = Trip.fromJson(trip.toJson());
      final loc = restored.days.first.locations.first;
      expect(loc.lastEntryTime, '16:00');
      expect(loc.closedOnDate, false);
      expect(loc.openHoursRaw, '08:30-17:00，16:00 停止检票');
      expect(loc.openSegments?.single.lastEntry, '16:00');
    });
  });

  // ==========================================================================
  // T04：节假日关系（holidayName / holidayStatus）
  //
  // 两个字段都是**纯展示用的可空字段**：缺键 → null（不兜底、不填默认值）。
  // ==========================================================================
  group('Location 节假日字段（T04）', () {
    test('两个新字段都进 toJson（要云同步，漏一个就丢一条链路）', () {
      final loc = Location(
        name: '中国国家博物馆',
        address: '北京市东城区',
        type: LocationType.attraction,
        openTime: '09:00',
        closeTime: '17:00',
        closedOnDate: false,
        openHoursRaw: '09:00-17:00',
        holidayName: '劳动节',
        holidayStatus: HolidayStatus.holiday,
      );

      final json = loc.toJson();
      expect(json['holidayName'], '劳动节');
      expect(json['holidayStatus'], 'holiday');
    });

    test('云同步往返：两个字段一个都不丢', () {
      final loc = Location(
        name: '苏州博物馆',
        address: '苏州市姑苏区',
        type: LocationType.attraction,
        holidayName: '国庆节',
        holidayStatus: HolidayStatus.holidayExcludedClose,
      );
      final restored = Location.fromJson(loc.toJson());

      expect(restored.holidayName, '国庆节');
      expect(restored.holidayStatus, HolidayStatus.holidayExcludedClose);
    });

    test('旧 JSON 缺两个新键 → 全 null，不抛异常、不兜底', () {
      // 这是 T02 上线前存量数据的真实形态：期望 null（未知），
      // **不是** '' / 'none' —— 后者会把"服务端没下发"伪造出结论。
      final loc = Location.fromJson({
        'id': 'OLD-2',
        'name': '老行程景点',
        'address': '某地',
        'type': 'attraction',
        'openTime': '08:00',
        'closeTime': '18:00',
      });

      expect(loc.holidayName, isNull);
      expect(loc.holidayStatus, isNull);
    });

    test('默认值即 null：不传就是未下发，不给默认值', () {
      final loc = Location(name: '某馆', address: '某地', type: LocationType.attraction);
      expect(loc.holidayName, isNull);
      expect(loc.holidayStatus, isNull);
      expect(loc.toJson()['holidayName'], isNull);
      expect(loc.toJson()['holidayStatus'], isNull);
    });

    test('三种服务端取值都能原样承载（none / holiday / holiday_excluded_close）', () {
      for (final status in [
        HolidayStatus.none,
        HolidayStatus.holiday,
        HolidayStatus.holidayExcludedClose,
      ]) {
        final loc = Location.fromJson({
          'name': '某馆',
          'type': 'attraction',
          'holidayStatus': status,
          'holidayName': status == HolidayStatus.none ? null : '劳动节',
        });
        expect(loc.holidayStatus, status);
        expect(loc.holidayName, status == HolidayStatus.none ? null : '劳动节');
        expect(loc.toJson()['holidayStatus'], status);
      }
    });

    test('clearOpenHoursFacts 一并清空节假日字段（它们是**按日期**的结论）', () {
      final loc = Location(
        name: '故宫',
        address: '北京',
        type: LocationType.attraction,
        openTime: '08:30',
        closeTime: '17:00',
        closedOnDate: false,
        openHoursRaw: '旺季 08:30-17:00',
        openSegments: const [OpenSegment(open: '08:30', close: '17:00')],
        holidayName: '劳动节',
        holidayStatus: HolidayStatus.holiday,
      );

      loc.clearOpenHoursFacts();

      expect(loc.holidayName, isNull,
          reason: '把「劳动节」这类别名搬到别的日期 = 编造数据');
      expect(loc.holidayStatus, isNull);
    });
  });
}
