import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/utils/itinerary_checker.dart';

/// P1「质量防线」代表性行程语料：营业时间、交通衔接、停留时间、冲突。
///
/// 本文件与函数级单测的区别：每个样本都是一整天的真实城市行程，保留景点、
/// 餐厅、酒店和逐段交通耗时，再对 [checkItineraryDay] 的全量结果做金标比对。
/// 所有交通分钟均同时写入服务端 payload 对应的 `transportMinutes` 与
/// `transport.durationMinutes`，测试不访问网络，也不消耗高德配额。
///
/// ## 三分类账本
/// - 规划逻辑错误：北京紧凑转场、杭州宽松转场、西安紧凑冲突、北京长日，
///   以及苏州/北京两家「周一闭馆」的馆被排进行程；
/// - 数据缺失：杭州丝绸博物馆缺当日营业原文、广州样本同时缺一段交通耗时与
///   广东省博物馆当日营业原文、北京样本中景山公园缺营业依据；
/// - 用户偏好修改：上海把上博停留改为 10 分钟、成都把午餐改为 0 分钟、
///   北京把晚餐延长到 5 小时。
///
/// ## CH-01…CH-09 覆盖度
/// 11 个 [ItineraryIssueCode] 分支**全部**由本语料直接覆盖（含 CH-03 当日闭馆），
/// 覆盖账本断言会校验这一点：新增规则却不补语料会直接红灯。
/// 唯一按设计跳过的场景是广州样本缺交通耗时时的 CH-06/07 —— 缺关键输入就
/// 跳过是校验器的三铁律，不能把该跳过写成冲突金标。
enum _CorpusFocus {
  openHoursClosure,
  transportConnection,
  stayDuration,
  conflict,
  dataGapControl,
}

enum _Density { compact, relaxed }

enum _Classification {
  planningLogicError,
  missingData,
  userPreferenceModification,
}

class _ExpectedIssue {
  final ItineraryIssueCode code;
  final IssueSeverity severity;
  final String? locationName;

  const _ExpectedIssue(this.code, this.severity, this.locationName);
}

class _CorpusCase {
  final String name;
  final String city;
  final _CorpusFocus focus;
  final _Density density;
  final TripDay day;
  final Set<ItineraryIssueCode> codes;
  final List<_ExpectedIssue> expectedIssues;
  final int blockingCount;
  final int reminderCount;
  final int uncheckedAttractionCount;
  final Map<_Classification, String> classificationRationale;

  const _CorpusCase({
    required this.name,
    required this.city,
    required this.focus,
    required this.density,
    required this.day,
    required this.codes,
    required this.expectedIssues,
    required this.blockingCount,
    required this.reminderCount,
    required this.uncheckedAttractionCount,
    required this.classificationRationale,
  });
}

Location _location({
  required String name,
  required String address,
  required String city,
  required LocationType type,
  required int stayMinutes,
  String? arrivalTime,
  String? leaveTime,
  int? transportMinutes,
  TransportType transportType = TransportType.transit,
  String? openTime,
  String? closeTime,
  String? lastEntryTime,
  bool? closedOnDate,
  String? openHoursRaw,
  String? holidayStatus,
}) {
  return Location(
    name: name,
    address: address,
    city: city,
    type: type,
    stayMinutes: stayMinutes,
    arrivalTime: arrivalTime,
    leaveTime: leaveTime,
    transportMinutes: transportMinutes,
    transport: transportMinutes == null
        ? null
        : Transport(
            type: transportType,
            scope: TransportScope.intraCity,
            durationMinutes: transportMinutes,
          ),
    openTime: openTime,
    closeTime: closeTime,
    lastEntryTime: lastEntryTime,
    closedOnDate: closedOnDate,
    openHoursRaw: openHoursRaw,
    holidayStatus: holidayStatus,
  );
}

TripDay _day(DateTime date, List<Location> locations) => TripDay(
      date: date,
      dayNumber: 1,
      locations: locations,
    );

List<_CorpusCase> _buildCorpus() => [
      _CorpusCase(
        name: '营业时间·苏州博物馆非节假日周一闭馆（CH-03）',
        city: '苏州',
        focus: _CorpusFocus.openHoursClosure,
        density: _Density.relaxed,
        day: _day(DateTime(2026, 10, 12), [
          _location(
            name: '苏州博物馆',
            address: '苏州市姑苏区东北街204号',
            city: '苏州',
            type: LocationType.attraction,
            arrivalTime: '09:00',
            leaveTime: '11:00',
            stayMinutes: 120,
            closedOnDate: true,
            openHoursRaw: '周一 不开放',
            holidayStatus: HolidayStatus.none,
          ),
          _location(
            name: '松鹤楼观前街店',
            address: '苏州市姑苏区太监弄72号',
            city: '苏州',
            type: LocationType.restaurant,
            arrivalTime: '11:20',
            leaveTime: '12:50',
            stayMinutes: 90,
            transportMinutes: 20,
            transportType: TransportType.walk,
          ),
          _location(
            name: '拙政园',
            address: '苏州市姑苏区东北街178号',
            city: '苏州',
            type: LocationType.attraction,
            arrivalTime: '13:10',
            leaveTime: '15:40',
            stayMinutes: 150,
            transportMinutes: 20,
            transportType: TransportType.transit,
            openTime: '07:30',
            closeTime: '17:30',
            closedOnDate: false,
            openHoursRaw: '07:30-17:30',
          ),
          _location(
            name: '平江路历史街区',
            address: '苏州市姑苏区平江路',
            city: '苏州',
            type: LocationType.attraction,
            arrivalTime: '16:00',
            leaveTime: '17:40',
            stayMinutes: 100,
            transportMinutes: 20,
            transportType: TransportType.walk,
            openTime: '00:00',
            closeTime: '23:30',
            closedOnDate: false,
            openHoursRaw: '全天开放',
          ),
          _location(
            name: '苏州观前街希尔顿酒店',
            address: '苏州市姑苏区观前街附近',
            city: '苏州',
            type: LocationType.hotel,
            arrivalTime: '17:55',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 15,
            transportType: TransportType.walk,
          ),
        ]),
        codes: const {ItineraryIssueCode.ch03ClosedDate},
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch03ClosedDate,
            IssueSeverity.blocking,
            '苏州博物馆',
          ),
        ],
        blockingCount: 1,
        reminderCount: 0,
        uncheckedAttractionCount: 0,
        classificationRationale: const {
          _Classification.planningLogicError:
              '非节假日周一仍把「周一闭馆」的苏州博物馆排成首站：闭馆结论是已确定的，'
                  '排进去就是不可执行的安排（P0-1 修复后旧逻辑遇「节假日除外」整体返 null 的误伤已消除）。',
        },
      ),
      _CorpusCase(
        name: '营业时间·北京国博周一闭馆 + 景山无营业依据（CH-03 + CH-09）',
        city: '北京',
        focus: _CorpusFocus.openHoursClosure,
        density: _Density.compact,
        day: _day(DateTime(2026, 10, 12), [
          _location(
            name: '中国国家博物馆',
            address: '北京市东城区东长安街16号',
            city: '北京',
            type: LocationType.attraction,
            arrivalTime: '09:00',
            leaveTime: '11:00',
            stayMinutes: 120,
            closedOnDate: true,
            openHoursRaw: '周一 不开放',
            holidayStatus: HolidayStatus.none,
          ),
          _location(
            name: '王府井狗不理',
            address: '北京市东城区王府井大街',
            city: '北京',
            type: LocationType.restaurant,
            arrivalTime: '11:45',
            leaveTime: '13:00',
            stayMinutes: 75,
            transportMinutes: 30,
            transportType: TransportType.transit,
          ),
          _location(
            name: '景山公园',
            address: '北京市西城区景山西街44号',
            city: '北京',
            type: LocationType.attraction,
            arrivalTime: '13:20',
            leaveTime: '14:50',
            stayMinutes: 90,
            transportMinutes: 20,
            transportType: TransportType.transit,
            // 该景点服务端没给出可核对的营业依据：只能诚实未知。
            //
            // ⚠️ 注意与交通规则的联动：本样本 CH-03 之外**不**含 CH-06/CH-07，
            //    因为营业依据缺失并不影响时刻链（stay 仍已知），这里刻意保持
            //   「只有闭馆与未知两条」的最小并置口径，便于核对日级/地点级数量。
          ),
          _location(
            name: '北京王府井半岛酒店',
            address: '北京市东城区金鱼胡同8号',
            city: '北京',
            type: LocationType.hotel,
            arrivalTime: '15:20',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 25,
            transportType: TransportType.taxi,
          ),
        ]),
        codes: const {
          ItineraryIssueCode.ch03ClosedDate,
          ItineraryIssueCode.ch09OpenHoursUnknown,
        },
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch03ClosedDate,
            IssueSeverity.blocking,
            '中国国家博物馆',
          ),
          _ExpectedIssue(
            ItineraryIssueCode.ch09OpenHoursUnknown,
            IssueSeverity.neutral,
            null,
          ),
        ],
        blockingCount: 1,
        reminderCount: 0,
        uncheckedAttractionCount: 1,
        classificationRationale: const {
          _Classification.planningLogicError:
              '国博非节假日周一闭馆却被排成首站：闭馆日进安排是不可执行的排程结论。',
          _Classification.missingData: '景山公园缺该日营业依据，走CH-09日级中性披露，不能反推它是否开放。',
        },
      ),
      _CorpusCase(
        name: '交通衔接·北京中轴紧凑日（CH-06）',
        city: '北京',
        focus: _CorpusFocus.transportConnection,
        density: _Density.compact,
        day: _day(DateTime(2026, 10, 13), [
          _location(
            name: '故宫博物院',
            address: '北京市东城区景山前街4号',
            city: '北京',
            type: LocationType.attraction,
            arrivalTime: '09:00',
            leaveTime: '11:30',
            stayMinutes: 150,
            openTime: '08:30',
            closeTime: '17:00',
            lastEntryTime: '16:00',
            closedOnDate: false,
            openHoursRaw: '08:30-17:00，16:00停止入馆',
          ),
          _location(
            name: '四季民福故宫店',
            address: '北京市东城区南池子大街11号',
            city: '北京',
            type: LocationType.restaurant,
            arrivalTime: '11:45',
            leaveTime: '13:00',
            stayMinutes: 75,
            transportMinutes: 35,
            transportType: TransportType.transit,
          ),
          _location(
            name: '天坛公园',
            address: '北京市东城区天坛东里甲1号',
            city: '北京',
            type: LocationType.attraction,
            arrivalTime: '13:50',
            leaveTime: '15:50',
            stayMinutes: 120,
            transportMinutes: 30,
            transportType: TransportType.transit,
            openTime: '06:00',
            closeTime: '22:00',
            closedOnDate: false,
            openHoursRaw: '06:00-22:00',
          ),
          _location(
            name: '北京饭店',
            address: '北京市东城区东长安街33号',
            city: '北京',
            type: LocationType.hotel,
            arrivalTime: '16:15',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 25,
            transportType: TransportType.taxi,
          ),
        ]),
        codes: const {ItineraryIssueCode.ch06InsufficientTransfer},
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch06InsufficientTransfer,
            IssueSeverity.blocking,
            '四季民福故宫店',
          ),
        ],
        blockingCount: 1,
        reminderCount: 0,
        uncheckedAttractionCount: 0,
        classificationRationale: const {
          _Classification.planningLogicError:
              '故宫11:30离开，原计划11:45到餐厅只留15分钟，但路线耗时35分钟。',
        },
      ),
      _CorpusCase(
        name: '交通衔接·杭州湖滨宽松日（CH-07 + CH-09）',
        city: '杭州',
        focus: _CorpusFocus.transportConnection,
        density: _Density.relaxed,
        day: _day(DateTime(2026, 10, 14), [
          _location(
            name: '中国丝绸博物馆',
            address: '杭州市西湖区玉皇山路73-1号',
            city: '杭州',
            type: LocationType.attraction,
            arrivalTime: '09:30',
            leaveTime: '12:30',
            stayMinutes: 180,
            // 模拟服务端没有取得该日可核对的营业原文：不得编造时段。
          ),
          _location(
            name: '楼外楼孤山路店',
            address: '杭州市西湖区孤山路30号',
            city: '杭州',
            type: LocationType.restaurant,
            arrivalTime: '13:05',
            leaveTime: '14:20',
            stayMinutes: 75,
            transportMinutes: 30,
            transportType: TransportType.transit,
          ),
          _location(
            name: '杭州西湖国宾馆',
            address: '杭州市西湖区杨公堤18号',
            city: '杭州',
            type: LocationType.hotel,
            arrivalTime: '14:40',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 25,
            transportType: TransportType.taxi,
          ),
        ]),
        codes: const {
          ItineraryIssueCode.ch07TightBuffer,
          ItineraryIssueCode.ch09OpenHoursUnknown,
        },
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch07TightBuffer,
            IssueSeverity.reminder,
            '楼外楼孤山路店',
          ),
          _ExpectedIssue(
            ItineraryIssueCode.ch09OpenHoursUnknown,
            IssueSeverity.neutral,
            null,
          ),
        ],
        blockingCount: 0,
        reminderCount: 1,
        uncheckedAttractionCount: 1,
        classificationRationale: const {
          _Classification.planningLogicError:
              '博物馆12:30离开，30分钟交通后只剩5分钟缓冲，小于产品阈值10分钟。',
          _Classification.missingData: '中国丝绸博物馆缺该日营业原文和结构化时段，只能以CH-09诚实披露。',
        },
      ),
      _CorpusCase(
        name: '停留时间·上海城区紧凑日（CH-05过短）',
        city: '上海',
        focus: _CorpusFocus.stayDuration,
        density: _Density.compact,
        day: _day(DateTime(2026, 10, 15), [
          _location(
            name: '上海博物馆人民广场馆',
            address: '上海市黄浦区人民大道201号',
            city: '上海',
            type: LocationType.attraction,
            arrivalTime: '09:30',
            leaveTime: '09:40',
            stayMinutes: 10,
            openTime: '09:00',
            closeTime: '17:00',
            lastEntryTime: '16:00',
            closedOnDate: false,
            openHoursRaw: '09:00-17:00，16:00停止入馆',
          ),
          _location(
            name: '杏花楼福州路总店',
            address: '上海市黄浦区福州路343号',
            city: '上海',
            type: LocationType.restaurant,
            arrivalTime: '10:20',
            leaveTime: '11:20',
            stayMinutes: 60,
            transportMinutes: 30,
            transportType: TransportType.walk,
          ),
          _location(
            name: '豫园',
            address: '上海市黄浦区福佑路168号',
            city: '上海',
            type: LocationType.attraction,
            arrivalTime: '11:40',
            leaveTime: '13:10',
            stayMinutes: 90,
            transportMinutes: 30,
            transportType: TransportType.transit,
            openTime: '09:00',
            closeTime: '16:30',
            closedOnDate: false,
            openHoursRaw: '09:00-16:30',
          ),
          _location(
            name: '上海和平饭店',
            address: '上海市黄浦区南京东路20号',
            city: '上海',
            type: LocationType.hotel,
            arrivalTime: '13:35',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 25,
            transportType: TransportType.transit,
          ),
        ]),
        codes: const {ItineraryIssueCode.ch05ShortStay},
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch05ShortStay,
            IssueSeverity.reminder,
            '上海博物馆人民广场馆',
          ),
        ],
        blockingCount: 0,
        reminderCount: 1,
        uncheckedAttractionCount: 0,
        classificationRationale: const {
          _Classification.userPreferenceModification:
              '用户把上海博物馆停留缩短为10分钟，低于景点15分钟产品阈值。',
        },
      ),
      _CorpusCase(
        name: '停留时间·成都熊猫基地宽松日（CH-05非法）',
        city: '成都',
        focus: _CorpusFocus.stayDuration,
        density: _Density.relaxed,
        day: _day(DateTime(2026, 10, 16), [
          _location(
            name: '成都大熊猫繁育研究基地',
            address: '成都市成华区熊猫大道1375号',
            city: '成都',
            type: LocationType.attraction,
            arrivalTime: '10:00',
            leaveTime: '13:00',
            stayMinutes: 180,
            openTime: '07:30',
            closeTime: '18:00',
            closedOnDate: false,
            openHoursRaw: '07:30-18:00',
          ),
          _location(
            name: '陈麻婆豆腐青华路店',
            address: '成都市青羊区青华路10号',
            city: '成都',
            type: LocationType.restaurant,
            arrivalTime: '13:45',
            leaveTime: '13:45',
            stayMinutes: 0,
            transportMinutes: 30,
            transportType: TransportType.taxi,
          ),
          _location(
            name: '成都宽窄巷子希尔顿花园酒店',
            address: '成都市青羊区宽巷子附近',
            city: '成都',
            type: LocationType.hotel,
            arrivalTime: '14:05',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 20,
            transportType: TransportType.taxi,
          ),
        ]),
        codes: const {ItineraryIssueCode.ch05InvalidStay},
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch05InvalidStay,
            IssueSeverity.blocking,
            '陈麻婆豆腐青华路店',
          ),
        ],
        blockingCount: 1,
        reminderCount: 0,
        uncheckedAttractionCount: 0,
        classificationRationale: const {
          _Classification.userPreferenceModification:
              '用户把午餐停留改成0分钟；非正数停留是不可执行输入。',
        },
      ),
      _CorpusCase(
        name: '冲突·西安城墙紧凑日（CH-01晚到 + CH-02早到）',
        city: '西安',
        focus: _CorpusFocus.conflict,
        density: _Density.compact,
        day: _day(DateTime(2026, 10, 17), [
          _location(
            name: '陕西历史博物馆',
            address: '西安市雁塔区小寨东路91号',
            city: '西安',
            type: LocationType.attraction,
            arrivalTime: '08:20',
            leaveTime: '10:20',
            stayMinutes: 120,
            openTime: '09:00',
            closeTime: '17:30',
            lastEntryTime: '16:30',
            closedOnDate: false,
            openHoursRaw: '09:00-17:30，16:30停止入馆',
          ),
          _location(
            name: '老孙家饭庄东大街店',
            address: '西安市碑林区东大街364号',
            city: '西安',
            type: LocationType.restaurant,
            arrivalTime: '10:50',
            leaveTime: '11:50',
            stayMinutes: 60,
            transportMinutes: 30,
            transportType: TransportType.transit,
          ),
          _location(
            name: '西安城墙永宁门',
            address: '西安市碑林区南大街2号',
            city: '西安',
            type: LocationType.attraction,
            arrivalTime: '12:10',
            leaveTime: '16:10',
            stayMinutes: 240,
            transportMinutes: 20,
            transportType: TransportType.transit,
            openTime: '08:00',
            closeTime: '22:00',
            closedOnDate: false,
            openHoursRaw: '08:00-22:00',
          ),
          _location(
            name: '大雁塔景区',
            address: '西安市雁塔区雁塔路南段11号',
            city: '西安',
            type: LocationType.attraction,
            arrivalTime: '16:50',
            leaveTime: '17:50',
            stayMinutes: 60,
            transportMinutes: 40,
            transportType: TransportType.transit,
            openTime: '08:30',
            closeTime: '17:30',
            lastEntryTime: '16:30',
            closedOnDate: false,
            openHoursRaw: '08:30-17:30，16:30停止入园',
          ),
          _location(
            name: '西安钟楼饭店',
            address: '西安市碑林区南大街110号',
            city: '西安',
            type: LocationType.hotel,
            arrivalTime: '18:10',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 20,
            transportType: TransportType.taxi,
          ),
        ]),
        codes: const {
          ItineraryIssueCode.ch01LateEntry,
          ItineraryIssueCode.ch02EarlyArrival,
        },
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch02EarlyArrival,
            IssueSeverity.reminder,
            '陕西历史博物馆',
          ),
          _ExpectedIssue(
            ItineraryIssueCode.ch01LateEntry,
            IssueSeverity.blocking,
            '大雁塔景区',
          ),
        ],
        blockingCount: 1,
        reminderCount: 1,
        uncheckedAttractionCount: 0,
        classificationRationale: const {
          _Classification.planningLogicError:
              '首站08:20早于09:00开门，末站16:50晚于16:30停止入园，均来自排程时刻。',
        },
      ),
      _CorpusCase(
        name: '冲突·北京西郊宽松长日（CH-01近打烊 + CH-04 + CH-08）',
        city: '北京',
        focus: _CorpusFocus.conflict,
        density: _Density.relaxed,
        day: _day(DateTime(2026, 10, 18), [
          _location(
            name: '颐和园',
            address: '北京市海淀区新建宫门路19号',
            city: '北京',
            type: LocationType.attraction,
            arrivalTime: '09:00',
            leaveTime: '13:00',
            stayMinutes: 240,
            openTime: '06:30',
            closeTime: '18:00',
            closedOnDate: false,
            openHoursRaw: '06:30-18:00',
          ),
          _location(
            name: '那家小馆颐和园店',
            address: '北京市海淀区颐和园路附近',
            city: '北京',
            type: LocationType.restaurant,
            arrivalTime: '13:40',
            leaveTime: '15:40',
            stayMinutes: 120,
            transportMinutes: 40,
            transportType: TransportType.transit,
          ),
          _location(
            name: '798艺术区',
            address: '北京市朝阳区酒仙桥路2号',
            city: '北京',
            type: LocationType.attraction,
            arrivalTime: '17:40',
            leaveTime: '18:40',
            stayMinutes: 60,
            transportMinutes: 120,
            transportType: TransportType.transit,
            openTime: '10:00',
            closeTime: '18:00',
            closedOnDate: false,
            openHoursRaw: '10:00-18:00',
          ),
          _location(
            name: '簋街晚餐',
            address: '北京市东城区东直门内大街',
            city: '北京',
            type: LocationType.restaurant,
            arrivalTime: '19:15',
            leaveTime: '00:15',
            stayMinutes: 300,
            transportMinutes: 35,
            transportType: TransportType.transit,
          ),
        ]),
        codes: const {
          ItineraryIssueCode.ch01ShortVisit,
          ItineraryIssueCode.ch04OverMidnight,
          ItineraryIssueCode.ch08LongDay,
        },
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch01ShortVisit,
            IssueSeverity.reminder,
            '798艺术区',
          ),
          _ExpectedIssue(
            ItineraryIssueCode.ch04OverMidnight,
            IssueSeverity.blocking,
            '簋街晚餐',
          ),
          _ExpectedIssue(
            ItineraryIssueCode.ch08LongDay,
            IssueSeverity.reminder,
            '簋街晚餐',
          ),
        ],
        // CH-08 与 CH-04 归责同一地点，展示时由阻塞级 CH-04 去重覆盖。
        blockingCount: 1,
        reminderCount: 1,
        uncheckedAttractionCount: 0,
        classificationRationale: const {
          _Classification.planningLogicError: '17:40才到18:00打烊的798，只剩20分钟可游览。',
          _Classification.userPreferenceModification:
              '用户把晚餐延长为300分钟，使日程排到次日00:15且总跨度15小时15分。',
        },
      ),
      _CorpusCase(
        name: '数据缺失对照·广州老城宽松日（CH-09，交通规则按设计跳过）',
        city: '广州',
        focus: _CorpusFocus.dataGapControl,
        density: _Density.relaxed,
        day: _day(DateTime(2026, 10, 19), [
          _location(
            name: '陈家祠',
            address: '广州市荔湾区中山七路恩龙里34号',
            city: '广州',
            type: LocationType.attraction,
            arrivalTime: '09:00',
            leaveTime: '11:00',
            stayMinutes: 120,
            openTime: '09:00',
            closeTime: '17:30',
            closedOnDate: false,
            openHoursRaw: '09:00-17:30',
          ),
          _location(
            name: '泮溪酒家',
            address: '广州市荔湾区龙津西路151号',
            city: '广州',
            type: LocationType.restaurant,
            arrivalTime: '11:20',
            leaveTime: '12:20',
            stayMinutes: 60,
            // 本段缺 transportMinutes：CH-06/CH-07 必须诚实跳过。
          ),
          _location(
            name: '广东省博物馆',
            address: '广州市天河区珠江东路2号',
            city: '广州',
            type: LocationType.attraction,
            arrivalTime: '12:40',
            leaveTime: '14:40',
            stayMinutes: 120,
            transportMinutes: 30,
            transportType: TransportType.transit,
            // 同时缺该日营业原文和时段，走CH-09中性披露。
          ),
          _location(
            name: '广州白天鹅宾馆',
            address: '广州市荔湾区沙面南街1号',
            city: '广州',
            type: LocationType.hotel,
            arrivalTime: '15:00',
            leaveTime: '08:00',
            stayMinutes: 600,
            transportMinutes: 25,
            transportType: TransportType.taxi,
          ),
        ]),
        codes: const {ItineraryIssueCode.ch09OpenHoursUnknown},
        expectedIssues: const [
          _ExpectedIssue(
            ItineraryIssueCode.ch09OpenHoursUnknown,
            IssueSeverity.neutral,
            null,
          ),
        ],
        blockingCount: 0,
        reminderCount: 0,
        uncheckedAttractionCount: 1,
        classificationRationale: const {
          _Classification.missingData:
              '泮溪酒家入段缺交通耗时，广东省博物馆缺营业依据；前者跳过交通判断，后者以CH-09披露。',
        },
      ),
    ];

String _actualIssueKey(ItineraryIssue issue, TripDay day) {
  final locationName = issue.locationId == null
      ? '<DAY>'
      : day.locations
          .singleWhere((location) => location.id == issue.locationId)
          .name;
  return '${issue.code.name}|${issue.severity.name}|$locationName';
}

String _expectedIssueKey(_ExpectedIssue issue) =>
    '${issue.code.name}|${issue.severity.name}|${issue.locationName ?? '<DAY>'}';

void _expectGold(_CorpusCase corpus) {
  // Arrange：完整行程已经由语料工厂构造。

  // Act
  final result = checkItineraryDay(corpus.day);

  // Assert：全量问题（含展示去重掉的次级问题）逐条比对代码、级别与归责点。
  final actualIssues = result.issues
      .map((issue) => _actualIssueKey(issue, corpus.day))
      .toList()
    ..sort();
  final expectedIssues = corpus.expectedIssues.map(_expectedIssueKey).toList()
    ..sort();

  expect(actualIssues, expectedIssues, reason: corpus.name);
  expect(
    result.issues.map((issue) => issue.code).toSet(),
    corpus.codes,
    reason: '${corpus.name}：检出的CH码集合必须与语料设计一致',
  );
  expect(result.blockingCount, corpus.blockingCount, reason: corpus.name);
  expect(result.reminderCount, corpus.reminderCount, reason: corpus.name);
  expect(
    result.uncheckedAttractionCount,
    corpus.uncheckedAttractionCount,
    reason: corpus.name,
  );
  expect(
    result.blockingCount,
    result.displayIssues
        .where((issue) => issue.severity == IssueSeverity.blocking)
        .length,
    reason: 'blockingCount必须与实际展示口径一致：${corpus.name}',
  );
  expect(
    result.reminderCount,
    result.displayIssues
        .where((issue) => issue.severity == IssueSeverity.reminder)
        .length,
    reason: 'reminderCount必须与实际展示口径一致：${corpus.name}',
  );
  expect(
    result.issues.every((issue) => issue.dayNumber == corpus.day.dayNumber),
    isTrue,
    reason: '问题必须归属当前行程日：${corpus.name}',
  );
}

void main() {
  final corpus = _buildCorpus();

  group('代表性行程金标', () {
    for (final sample in corpus) {
      test(sample.name, () => _expectGold(sample));
    }
  });

  group('语料结构与分类账本', () {
    test('营业时间、交通衔接、停留时间、冲突四类均有语料，后三类各至少2个城市', () {
      // 营业时间类的代表规则是CH-03当日闭馆（评审列的四类之首）。
      final closureSamples = corpus
          .where((sample) => sample.focus == _CorpusFocus.openHoursClosure)
          .toList();
      expect(closureSamples.length, greaterThanOrEqualTo(2));
      expect(
        closureSamples.every(
          (sample) => sample.codes.contains(ItineraryIssueCode.ch03ClosedDate),
        ),
        isTrue,
        reason: '营业时间类语料必须直接验证CH-03',
      );

      const requiredFocuses = {
        _CorpusFocus.transportConnection,
        _CorpusFocus.stayDuration,
        _CorpusFocus.conflict,
      };

      for (final focus in requiredFocuses) {
        final samples =
            corpus.where((sample) => sample.focus == focus).toList();
        expect(samples.length, greaterThanOrEqualTo(2), reason: focus.name);
        expect(
          samples.map((sample) => sample.city).toSet().length,
          greaterThanOrEqualTo(2),
          reason: '${focus.name}必须覆盖至少2个真实城市',
        );
        expect(
          samples.map((sample) => sample.density).toSet(),
          {_Density.compact, _Density.relaxed},
          reason: '${focus.name}必须同时覆盖紧凑型与宽松型',
        );
        final types = samples
            .expand((sample) => sample.day.locations)
            .map((location) => location.type)
            .toSet();
        expect(
          types,
          containsAll({
            LocationType.attraction,
            LocationType.restaurant,
            LocationType.hotel,
          }),
          reason: '${focus.name}语料必须混合景点、餐厅与酒店',
        );
      }
    });

    test('每条交通金标都携带与transport.durationMinutes一致的真实字段形态', () {
      final transportSamples = corpus.where(
        (sample) => sample.focus == _CorpusFocus.transportConnection,
      );

      for (final sample in transportSamples) {
        for (final location in sample.day.locations.skip(1)) {
          expect(location.transportMinutes, isNotNull, reason: location.name);
          expect(location.transport, isNotNull, reason: location.name);
          expect(
            location.transport!.durationMinutes,
            location.transportMinutes,
            reason: '${sample.name}：${location.name}',
          );
        }
      }
    });

    test('规划逻辑错误、数据缺失、用户偏好修改三档均有依据', () {
      final recorded = <_Classification>{};
      for (final sample in corpus) {
        expect(sample.classificationRationale, isNotEmpty, reason: sample.name);
        for (final entry in sample.classificationRationale.entries) {
          expect(entry.value.trim(), isNotEmpty, reason: sample.name);
          recorded.add(entry.key);
        }
      }
      expect(recorded, _Classification.values.toSet());
    });
  });

  group('CH-01…CH-09覆盖度与漏检账本', () {
    test('CH-01…CH-09 全部规则及分支均进入本语料', () {
      // 声明式账本：每条样本自带 `codes`，覆盖度由语料本身声明……
      final covered = <ItineraryIssueCode>{
        for (final sample in corpus) ...sample.codes,
      };

      // ……同时逐条跑一遍实际校验，确保声明与实现一致
      // （`codes` 写错而没人发现 = 账本失真，这里直接红灯）。
      for (final sample in corpus) {
        expect(
          checkItineraryDay(sample.day)
              .issues
              .map((issue) => issue.code)
              .toSet(),
          sample.codes,
          reason: '${sample.name}：声明的CH码与实际检出不一致',
        );
      }

      // 白名单显式列出全部分支：新增规则却不补语料会在这里直接红灯。
      expect(
        covered,
        containsAll({
          ItineraryIssueCode.ch01LateEntry,
          ItineraryIssueCode.ch01ShortVisit,
          ItineraryIssueCode.ch02EarlyArrival,
          ItineraryIssueCode.ch03ClosedDate,
          ItineraryIssueCode.ch04OverMidnight,
          ItineraryIssueCode.ch05InvalidStay,
          ItineraryIssueCode.ch05ShortStay,
          ItineraryIssueCode.ch06InsufficientTransfer,
          ItineraryIssueCode.ch07TightBuffer,
          ItineraryIssueCode.ch08LongDay,
          ItineraryIssueCode.ch09OpenHoursUnknown,
        }),
      );
      expect(covered, ItineraryIssueCode.values.toSet());
      expect(covered.length, ItineraryIssueCode.values.length);
    });

    test('CH-03：非节假日周一闭馆 = 阻塞且归责到该地点，并钉住P0-1修复后的确定结论', () {
      final sample = corpus.singleWhere(
        (item) =>
            item.focus == _CorpusFocus.openHoursClosure && item.city == '苏州',
      );
      final museum = sample.day.locations.first;
      expect(museum.holidayStatus, HolidayStatus.none, reason: '非节假日周一');
      expect(museum.closedOnDate, isTrue);
      expect(museum.openHoursRaw, '周一 不开放');

      final result = checkItineraryDay(sample.day);
      final ch03 = result.issues
          .where((issue) => issue.code == ItineraryIssueCode.ch03ClosedDate)
          .toList();
      expect(ch03.single.severity, IssueSeverity.blocking);
      expect(ch03.single.locationId, museum.id);
      expect(ch03.single.sourceRaw, '周一 不开放', reason: '闭馆结论必须带原文证据');
      expect(primaryIssueForLocation(result, museum.id)!.code,
          ItineraryIssueCode.ch03ClosedDate);
      // 「明确闭馆」是成功解析，不是缺数据 → 不计入CH-09
      expect(isOpenHoursVerified(museum), isTrue);
      expect(result.uncheckedAttractionCount, 0);
    });

    test('CH-03与CH-09并置：地点级与日级各计一条，数量口径不混', () {
      final sample = corpus.singleWhere(
        (item) =>
            item.focus == _CorpusFocus.openHoursClosure && item.city == '北京',
      );
      final result = checkItineraryDay(sample.day);

      final ch03 = result.issues
          .where((issue) => issue.code == ItineraryIssueCode.ch03ClosedDate)
          .toList();
      final ch09 = result.issues
          .where(
              (issue) => issue.code == ItineraryIssueCode.ch09OpenHoursUnknown)
          .toList();

      expect(ch03.length, 1);
      expect(ch03.single.locationId, isNotNull, reason: 'CH-03是地点级');
      expect(ch09.length, 1);
      expect(ch09.single.locationId, isNull, reason: 'CH-09是日级，不归责卡片');
      // 闭馆的馆不计入未校验，未校验只数缺营业依据的景点
      expect(result.uncheckedAttractionCount, 1);
      expect(result.blockingCount, 1);
      // 本样本不含提醒级问题：景山公园缺营业依据不会凭空产出交通/营业提醒
      expect(result.reminderCount, 0);
      expect(
        result.issues.map((issue) => issue.code).toSet(),
        {
          ItineraryIssueCode.ch03ClosedDate,
          ItineraryIssueCode.ch09OpenHoursUnknown,
        },
      );
    });

    test('数据缺失对照：缺交通耗时后CH-06/CH-07按设计跳过，不固化成冲突', () {
      final sample = corpus.singleWhere(
        (item) => item.focus == _CorpusFocus.dataGapControl,
      );
      final result = checkItineraryDay(sample.day);

      expect(result.slots[1].travelMinutes, isNull);
      expect(result.slots[1].timeReliable, isFalse);
      expect(result.slots.skip(1).every((slot) => !slot.timeReliable), isTrue);
      expect(
        result.issues.where(
          (issue) =>
              issue.code == ItineraryIssueCode.ch06InsufficientTransfer ||
              issue.code == ItineraryIssueCode.ch07TightBuffer,
        ),
        isEmpty,
        reason: '交通耗时缺失时没有事实依据判断排不下或缓冲不足，这是设计跳过而非漏检',
      );
      expect(
        result.issues.single.code,
        ItineraryIssueCode.ch09OpenHoursUnknown,
        reason: '同日营业原文缺失仍须单独诚实披露',
      );
    });
  });
}
