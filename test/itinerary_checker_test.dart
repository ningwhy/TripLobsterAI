import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/utils/itinerary_checker.dart';

/// 行程可执行性校验纯函数测试（T03）
///
/// ## 纪律
/// 1. **完全离线**：不读网络、不读 `DateTime.now()`、不依赖高德配额；
/// 2. **零假阳性**是硬指标：营业/交通字段缺失时必须**不产出**对应问题，
///    而不是产出一条"可能有问题"的模糊提示；
/// 3. 涉及产品阈值的用例，测试名一律写明「阈值=产品判断」，不得包装成实测结论。
void main() {
  // -------------------------------------------------------------------------
  // 工具
  // -------------------------------------------------------------------------

  Location loc({
    required String name,
    LocationType type = LocationType.attraction,
    String? arrivalTime,
    String? leaveTime,
    int? stayMinutes,
    int? transportMinutes,
    String? openTime,
    String? closeTime,
    String? lastEntryTime,
    bool? closedOnDate,
    String? openHoursRaw,
  }) =>
      Location(
        name: name,
        address: '测试地址',
        type: type,
        arrivalTime: arrivalTime,
        leaveTime: leaveTime,
        stayMinutes: stayMinutes,
        transportMinutes: transportMinutes,
        openTime: openTime,
        closeTime: closeTime,
        lastEntryTime: lastEntryTime,
        closedOnDate: closedOnDate,
        openHoursRaw: openHoursRaw,
      );

  TripDay day(List<Location> locations, {int dayNumber = 1}) => TripDay(
        date: DateTime(2026, 10, 13), // 2026-10-13 是周二；本模块不按星期判定，仅作日期锚
        dayNumber: dayNumber,
        locations: locations,
      );

  List<ItineraryIssue> codes(DayCheckResult r, ItineraryIssueCode code) =>
      r.issues.where((i) => i.code == code).toList();

  // -------------------------------------------------------------------------
  // parseClockMinutes
  // -------------------------------------------------------------------------
  group('parseClockMinutes', () {
    test('标准 HH:mm → 分钟', () {
      expect(parseClockMinutes('08:30'), 510);
      expect(parseClockMinutes('00:00'), 0);
      expect(parseClockMinutes('17:00'), 1020);
    });

    test('不要求两位补零（高德原文常见 9:5）', () {
      expect(parseClockMinutes('9:5'), 545);
    });

    test('24:00 合法（24 小时营业的打烊时刻），24:30 非法', () {
      expect(parseClockMinutes('24:00'), 1440);
      expect(parseClockMinutes('24:30'), isNull);
      expect(parseClockMinutes('25:00'), isNull);
    });

    test('null / 空串 / 非法 / 区间串 一律 null', () {
      expect(parseClockMinutes(null), isNull);
      expect(parseClockMinutes(''), isNull);
      expect(parseClockMinutes('   '), isNull);
      expect(parseClockMinutes('09:00-17:00'), isNull); // 不是时刻，是区间
      expect(parseClockMinutes('上午九点'), isNull);
      expect(parseClockMinutes('08:60'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // formatClockMinutes
  // -------------------------------------------------------------------------
  group('formatClockMinutes', () {
    test('当日时刻不显示"次日"', () {
      expect(formatClockMinutes(510), '08:30');
      expect(formatClockMinutes(1080), '18:00');
    });

    test('跨午夜显示"次日 HH:mm"（CH-04 验收点）', () {
      expect(formatClockMinutes(1470), '次日 00:30');
      expect(formatClockMinutes(1440), '次日 00:00');
    });

    test('formatDurationMinutes 中文时长', () {
      expect(formatDurationMinutes(30), '30分钟');
      expect(formatDurationMinutes(90), '1小时30分');
      expect(formatDurationMinutes(120), '2小时');
    });
  });

  // -------------------------------------------------------------------------
  // isOpenHoursVerified（CH-09 判据）
  // -------------------------------------------------------------------------
  group('isOpenHoursVerified', () {
    test('明确闭馆 + 原文 = 已校验（闭馆是成功解析，不是失败）', () {
      expect(
        isOpenHoursVerified(loc(
          name: '国博',
          closedOnDate: true,
          openHoursRaw: '周一闭馆',
        )),
        isTrue,
      );
    });

    test('明确开放段 + 三要素齐全 = 已校验', () {
      expect(
        isOpenHoursVerified(loc(
          name: '故宫',
          closedOnDate: false,
          openTime: '08:30',
          closeTime: '17:00',
          openHoursRaw: '08:30-17:00',
        )),
        isTrue,
      );
    });

    test('closedOnDate == null（未知）→ 未校验：null 绝不当 false', () {
      expect(
        isOpenHoursVerified(loc(
          name: '老景点',
          openTime: '08:00',
          closeTime: '18:00',
          openHoursRaw: '08:00-18:00',
        )),
        isFalse,
      );
    });

    test('部分字段存在不算已校验（缺原文 / 缺 openTime / 缺 closeTime）', () {
      expect(
        isOpenHoursVerified(loc(name: 'a', closedOnDate: false, openTime: '08:00', closeTime: '17:00')),
        isFalse,
      );
      expect(
        isOpenHoursVerified(loc(name: 'a', closedOnDate: false, openTime: '08:00', openHoursRaw: 'x')),
        isFalse,
      );
      expect(
        isOpenHoursVerified(loc(name: 'a', closedOnDate: true)),
        isFalse,
      );
    });

    test('open >= close 的不一致数据不可信', () {
      expect(
        isOpenHoursVerified(loc(
          name: 'a',
          closedOnDate: false,
          openTime: '17:00',
          closeTime: '08:30',
          openHoursRaw: '17:00-08:30',
        )),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // rebuildItinerarySlots
  // -------------------------------------------------------------------------
  group('rebuildItinerarySlots', () {
    test('纯加法、不 mod 1440：22:00 起排到次日 02:00 仍记为 1560', () {
      final slots = rebuildItinerarySlots(day([
        loc(name: '夜场A', arrivalTime: '22:00', stayMinutes: 180),
        loc(name: '夜场B', transportMinutes: 60, stayMinutes: 60),
      ]));

      expect(slots[0].arrival, 1320);
      expect(slots[0].leave, 1500); // 22:00 + 3h = 次日 01:00（**不**绕回 60）
      expect(slots[1].arrival, 1560); // + 1h 交通（**不**绕回 120）
      expect(slots[1].leave, 1620);
    });

    test('首站无 arrivalTime → 整链不可靠，不编造 9:00 起点', () {
      final slots = rebuildItinerarySlots(day([
        loc(name: 'A', stayMinutes: 60),
        loc(name: 'B', transportMinutes: 30, stayMinutes: 60),
      ]));

      expect(slots.every((s) => s.arrival == null), isTrue);
      expect(slots.every((s) => s.leave == null), isTrue);
      expect(slots.every((s) => !s.timeReliable), isTrue);
    });

    test('前站 stay 缺失 → 后续到达时刻不可靠', () {
      final slots = rebuildItinerarySlots(day([
        loc(name: 'A', arrivalTime: '09:00'), // stay 缺失
        loc(name: 'B', transportMinutes: 30, stayMinutes: 60),
      ]));

      expect(slots[0].arrival, 540);
      expect(slots[0].leave, isNull);
      expect(slots[1].arrival, isNull);
      expect(slots[1].timeReliable, isFalse);
    });

    test('本站 transport 缺失 → 该站到达不可靠', () {
      final slots = rebuildItinerarySlots(day([
        loc(name: 'A', arrivalTime: '09:00', stayMinutes: 60),
        loc(name: 'B', stayMinutes: 60), // transport 缺失
      ]));

      expect(slots[0].timeReliable, isTrue);
      expect(slots[1].timeReliable, isFalse);
    });

    test('sourceWrapped：payload 的 leave < arrival（服务端 fmt 已 mod）', () {
      final slots = rebuildItinerarySlots(day([
        loc(name: 'A', arrivalTime: '18:00', leaveTime: '00:30', stayMinutes: 600),
      ]));

      expect(slots[0].sourceWrapped, isTrue);
      expect(slots[0].sourceArrival, 1080);
      expect(slots[0].sourceLeave, 30);
    });

    test('空日 → 空 slots，不抛', () {
      expect(rebuildItinerarySlots(day([])), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // CH-01 停止入场 / 打烊
  // -------------------------------------------------------------------------
  group('CH-01', () {
    test('16:50 到达、16:00 停止检票 → 阻塞，主句含两个时刻，副行含原文', () {
      final r = checkItineraryDay(day([
        loc(
          name: '故宫',
          arrivalTime: '16:50',
          stayMinutes: 60,
          openTime: '08:30',
          closeTime: '17:00',
          lastEntryTime: '16:00',
          closedOnDate: false,
          openHoursRaw: '08:30-17:00，16:00 停止检票',
        ),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch01LateEntry);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.blocking);
      expect(issues.first.message, contains('16:50'));
      expect(issues.first.message, contains('16:00'));
      expect(issues.first.sourceRaw, '08:30-17:00，16:00 停止检票');
    });

    test('无 lastEntryTime 时退到 close：到达 >= 打烊 → 阻塞', () {
      final r = checkItineraryDay(day([
        loc(
          name: '拙政园',
          arrivalTime: '17:30',
          stayMinutes: 60,
          openTime: '07:30',
          closeTime: '17:30',
          closedOnDate: false,
          openHoursRaw: '07:30-17:30',
        ),
      ]));

      expect(codes(r, ItineraryIssueCode.ch01LateEntry).length, 1);
    });

    test('距打烊 20 分钟 → 提醒（阈值 30 分钟=产品判断）', () {
      final r = checkItineraryDay(day([
        loc(
          name: '拙政园',
          arrivalTime: '17:10',
          stayMinutes: 60,
          openTime: '07:30',
          closeTime: '17:30',
          closedOnDate: false,
          openHoursRaw: '07:30-17:30',
        ),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch01ShortVisit);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.reminder);
      expect(issues.first.message, contains('20'));
      expect(codes(r, ItineraryIssueCode.ch01LateEntry), isEmpty);
    });

    test('零假阳性：只有 openTime/closeTime 但无原文（老数据）→ CH-01/02/03 全为 0', () {
      final r = checkItineraryDay(day([
        loc(
          name: '老景点',
          arrivalTime: '23:00', // 远晚于 18:00
          stayMinutes: 60,
          openTime: '08:00',
          closeTime: '18:00',
          // closedOnDate / openHoursRaw 全缺 → 未校验
        ),
      ]));

      expect(codes(r, ItineraryIssueCode.ch01LateEntry), isEmpty);
      expect(codes(r, ItineraryIssueCode.ch01ShortVisit), isEmpty);
      expect(codes(r, ItineraryIssueCode.ch02EarlyArrival), isEmpty);
      expect(codes(r, ItineraryIssueCode.ch03ClosedDate), isEmpty);
      // 但必须诚实披露"没校验"
      expect(r.uncheckedAttractionCount, 1);
    });

    test('零假阳性：时间链不可靠（首站无锚）→ 不判营业问题', () {
      final r = checkItineraryDay(day([
        loc(
          name: '故宫',
          stayMinutes: 60, // 无 arrivalTime
          openTime: '08:30',
          closeTime: '17:00',
          lastEntryTime: '16:00',
          closedOnDate: false,
          openHoursRaw: '08:30-17:00',
        ),
      ]));

      expect(codes(r, ItineraryIssueCode.ch01LateEntry), isEmpty);
      expect(codes(r, ItineraryIssueCode.ch02EarlyArrival), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // CH-02 早到
  // -------------------------------------------------------------------------
  group('CH-02', () {
    test('08:05 到达、08:30 开门 → 提醒"需等 25 分钟"', () {
      final r = checkItineraryDay(day([
        loc(
          name: '上博',
          arrivalTime: '08:05',
          stayMinutes: 120,
          openTime: '08:30',
          closeTime: '17:00',
          closedOnDate: false,
          openHoursRaw: '08:30-17:00',
        ),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch02EarlyArrival);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.reminder);
      expect(issues.first.message, contains('需等 25 分钟'));
    });

    test('早到 14 分钟不触发（阈值 15 分钟=产品判断）', () {
      final r = checkItineraryDay(day([
        loc(
          name: '上博',
          arrivalTime: '08:16',
          stayMinutes: 120,
          openTime: '08:30',
          closeTime: '17:00',
          closedOnDate: false,
          openHoursRaw: '08:30-17:00',
        ),
      ]));

      expect(codes(r, ItineraryIssueCode.ch02EarlyArrival), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // CH-03 闭馆日
  // -------------------------------------------------------------------------
  group('CH-03', () {
    test('closedOnDate=true 且有原文 → 阻塞', () {
      final r = checkItineraryDay(day([
        loc(
          name: '故宫',
          arrivalTime: '09:00',
          stayMinutes: 120,
          closedOnDate: true,
          openHoursRaw: '周一闭馆',
        ),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch03ClosedDate);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.blocking);
      expect(issues.first.sourceRaw, '周一闭馆');
    });

    test('零假阳性：closedOnDate=null（未知）绝不推断闭馆', () {
      final r = checkItineraryDay(day([
        loc(name: '某馆', arrivalTime: '09:00', stayMinutes: 120),
      ]));

      expect(codes(r, ItineraryIssueCode.ch03ClosedDate), isEmpty);
    });

    test('零假阳性：closedOnDate=true 但无原文 → 不展示无证据结论', () {
      final r = checkItineraryDay(day([
        loc(name: '某馆', arrivalTime: '09:00', stayMinutes: 120, closedOnDate: true),
      ]));

      expect(codes(r, ItineraryIssueCode.ch03ClosedDate), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // CH-04 跨午夜
  // -------------------------------------------------------------------------
  group('CH-04', () {
    test('非酒店末站累计到 1470 → 阻塞并显示"次日 00:30"', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', type: LocationType.attraction, arrivalTime: '08:00', stayMinutes: 480),
        loc(
          name: 'B',
          type: LocationType.attraction,
          transportMinutes: 30,
          stayMinutes: 480,
        ),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch04OverMidnight);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.blocking);
      expect(issues.first.message, contains('次日 00:30'));
      expect(issues.first.locationId, isNotNull);
    });

    test('酒店过夜豁免：18:00 入住 stay 600 不触发（A-2）', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', type: LocationType.attraction, arrivalTime: '09:00', stayMinutes: 300),
        loc(
          name: '酒店',
          type: LocationType.hotel,
          transportMinutes: 30,
          stayMinutes: 600,
        ),
      ]));

      // 纯加法保留住宿时长（leave 确实越过 1440），但不判"当日活动排过午夜"
      expect(r.slots[1].leave, 1470);
      expect(codes(r, ItineraryIssueCode.ch04OverMidnight), isEmpty);
    });

    test('payload 自身绕回（18:00 到达、次日 00:30 离开）→ 阻塞', () {
      final r = checkItineraryDay(day([
        loc(
          name: '夜游项目',
          arrivalTime: '18:00',
          leaveTime: '00:30',
          stayMinutes: 600,
        ),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch04OverMidnight);
      expect(issues.length, 1); // 规则 a 与规则 b 不重复产出
      expect(issues.first.message, contains('18:00'));
      expect(issues.first.message, contains('次日 00:30'));
    });

    test('酒店自身绕回被忽略，但酒店到达已过 24:00 仍触发', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', type: LocationType.attraction, arrivalTime: '23:00', stayMinutes: 90),
        loc(
          name: '酒店',
          type: LocationType.hotel,
          arrivalTime: '01:00',
          leaveTime: '00:30', // sourceWrapped，但酒店豁免
          transportMinutes: 30,
          stayMinutes: 600,
        ),
      ]));

      // 酒店到达 = 23:00(1380) + 90 + 30 = 1500（即次日 01:00）> 1440，由累计日终触发
      expect(r.slots[1].arrival, 1500);
      final issues = codes(r, ItineraryIssueCode.ch04OverMidnight);
      expect(issues.length, 1);
      expect(issues.first.locationId, r.slots[1].location.id);
    });
  });

  // -------------------------------------------------------------------------
  // CH-05 停留异常（P1，阈值为产品判断）
  // -------------------------------------------------------------------------
  group('CH-05', () {
    test('stay <= 0 → 阻塞', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00', stayMinutes: 0),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch05InvalidStay);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.blocking);
    });

    test('景点停留 10 分钟 → 提醒（阈值 15 分钟=产品判断）', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', type: LocationType.attraction, arrivalTime: '09:00', stayMinutes: 10),
      ]));
      expect(codes(r, ItineraryIssueCode.ch05ShortStay).length, 1);

      final ok = checkItineraryDay(day([
        loc(name: 'A', type: LocationType.attraction, arrivalTime: '09:00', stayMinutes: 20),
      ]));
      expect(codes(ok, ItineraryIssueCode.ch05ShortStay), isEmpty);
    });

    test('餐厅停留 20 分钟 → 提醒（阈值 30 分钟=产品判断）；stay=null 跳过', () {
      final r = checkItineraryDay(day([
        loc(name: '饭馆', type: LocationType.restaurant, arrivalTime: '12:00', stayMinutes: 20),
      ]));
      expect(codes(r, ItineraryIssueCode.ch05ShortStay).length, 1);

      final skip = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00'), // stay 缺失
      ]));
      expect(codes(skip, ItineraryIssueCode.ch05InvalidStay), isEmpty);
      expect(codes(skip, ItineraryIssueCode.ch05ShortStay), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // CH-06 / CH-07 转场
  // -------------------------------------------------------------------------
  group('CH-06 / CH-07', () {
    test('原计划只留 15 分钟、交通需 40 分钟 → 阻塞，文案以"按行程安排"开头', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00', stayMinutes: 60),
        loc(name: 'B', arrivalTime: '10:15', transportMinutes: 40, stayMinutes: 60),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch06InsufficientTransfer);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.blocking);
      expect(issues.first.message, startsWith('按行程安排'));
      expect(issues.first.message, contains('15 分钟'));
      expect(issues.first.message, contains('40 分钟'));
      expect(issues.first.locationId, r.slots[1].location.id);
    });

    test('转场后仅剩 3 分钟缓冲 → CH-07 提醒（阈值 10 分钟=产品判断）', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00', stayMinutes: 60),
        loc(name: 'B', arrivalTime: '10:43', transportMinutes: 40, stayMinutes: 60),
      ]));

      expect(codes(r, ItineraryIssueCode.ch06InsufficientTransfer), isEmpty);
      final issues = codes(r, ItineraryIssueCode.ch07TightBuffer);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.reminder);
      expect(issues.first.message, startsWith('按行程安排'));
      expect(issues.first.message, contains('仅剩 3 分钟缓冲'));
    });

    test('零假阳性：缺 transportMinutes / 缺 sourceArrival / 前站 leave 未知 → 全跳过', () {
      // 缺 transport
      final noTransport = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00', stayMinutes: 60),
        loc(name: 'B', arrivalTime: '10:15', stayMinutes: 60),
      ]));
      expect(codes(noTransport, ItineraryIssueCode.ch06InsufficientTransfer), isEmpty);
      expect(codes(noTransport, ItineraryIssueCode.ch07TightBuffer), isEmpty);

      // 缺下站 sourceArrival
      final noSource = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00', stayMinutes: 60),
        loc(name: 'B', transportMinutes: 40, stayMinutes: 60),
      ]));
      expect(codes(noSource, ItineraryIssueCode.ch06InsufficientTransfer), isEmpty);

      // 前站 stay 缺失 → leave 未知
      final noLeave = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00'),
        loc(name: 'B', arrivalTime: '10:15', transportMinutes: 40, stayMinutes: 60),
      ]));
      expect(codes(noLeave, ItineraryIssueCode.ch06InsufficientTransfer), isEmpty);
    });

    // -------------------------------------------------------------------------
    // 下面三例锁定**真实 generate 产物**上暴露的两个假阳性（2026-10 实测）。
    //
    // 它们不是构造出来的边角料：拿 `generateTrip` 的真实 payload 喂 checker，
    // 修复前每天都会亮 1~2 条，其中一条是**阻塞级**。构造用的时刻链
    // 与真实产物逐站一致（见 deliverables/_fx-arrivaltime-payload.json）。
    // -------------------------------------------------------------------------

    test('真实产物①：服务端「零缓冲」规划态不误报 CH-07', () {
      // 服务端 pushLoc 就是按 arrival[i+1] = leave[i] + travel[i+1] 累加的，
      // 所以每一对的 gap 恒等于 travel —— 这是规划常态，不是缓冲不足。
      final r = checkItineraryDay(day([
        loc(name: '故宫', arrivalTime: '09:00', stayMinutes: 120),
        loc(name: '什刹海', arrivalTime: '11:55', stayMinutes: 120, transportMinutes: 55),
        loc(name: '餐厅', type: LocationType.restaurant, arrivalTime: '13:55', stayMinutes: 75),
        loc(name: '雍和宫', arrivalTime: '16:08', stayMinutes: 45, transportMinutes: 58),
        loc(name: '酒店', type: LocationType.hotel, arrivalTime: '18:52', stayMinutes: 600, transportMinutes: 119),
      ]));

      expect(codes(r, ItineraryIssueCode.ch07TightBuffer), isEmpty,
          reason: '未编辑的规划器产物零缓冲是常态，渲染成提醒即假阳性工厂');
      expect(codes(r, ItineraryIssueCode.ch06InsufficientTransfer), isEmpty);
      expect(codes(r, ItineraryIssueCode.ch04OverMidnight), isEmpty);
    });

    test('真实产物②：fmt() 把跨午夜站绕回成 00:58，不误报 CH-06', () {
      // 真实产物第 2 天：… 22:00 →(103min)→ 24:58，payload 里酒店 arr=00:58。
      // 不先按锚展开就会得到「00:58 早于前站 23:15 离开 1337 分钟」→ 阻塞级假阳性。
      final r = checkItineraryDay(day([
        loc(name: '午餐', type: LocationType.restaurant, arrivalTime: '14:58', stayMinutes: 75),
        loc(name: '晚餐', type: LocationType.restaurant, arrivalTime: '22:00', stayMinutes: 75, transportMinutes: 10),
        loc(name: '酒店', type: LocationType.hotel, arrivalTime: '00:58', stayMinutes: 600, transportMinutes: 103),
      ]));

      expect(codes(r, ItineraryIssueCode.ch06InsufficientTransfer), isEmpty,
          reason: '绕回值必须按锚单调展开后再比较');
      expect(codes(r, ItineraryIssueCode.ch07TightBuffer), isEmpty);
      // 酒店是过夜边界：24:58 到达也不判"当日排过午夜"
      expect(codes(r, ItineraryIssueCode.ch04OverMidnight), isEmpty);
    });

    test('真实产物③：砍站留下的空档不误报（gap 远大于 travel）', () {
      // 真实产物第 2 天两个餐厅之间差了 337 分钟（中间的景点被服务端超时裁剪砍掉了），
      // 纯加法重建补不出这个空洞 —— 但 gap > travel 时既不是排不下也不是缓冲不足。
      final r = checkItineraryDay(day([
        loc(name: '午餐', type: LocationType.restaurant, arrivalTime: '14:58', stayMinutes: 75),
        loc(name: '晚餐', type: LocationType.restaurant, arrivalTime: '22:00', stayMinutes: 75, transportMinutes: 10),
      ]));

      expect(codes(r, ItineraryIssueCode.ch06InsufficientTransfer), isEmpty);
      expect(codes(r, ItineraryIssueCode.ch07TightBuffer), isEmpty);
    });

    test('用户编辑后 CH-06 真的亮起（证明通路不是死逻辑）', () {
      final locations = [
        loc(name: '故宫', arrivalTime: '09:00', stayMinutes: 120),
        loc(name: '什刹海', arrivalTime: '11:55', stayMinutes: 120, transportMinutes: 55),
      ];
      expect(codes(checkItineraryDay(day(locations)), ItineraryIssueCode.ch06InsufficientTransfer), isEmpty);

      // 用户把首站停留从 120 拉到 420 → 重建离开变成 16:00，晚于原计划到达 11:55
      locations[0].stayMinutes = 420;
      final after = checkItineraryDay(day(locations));
      final issues = codes(after, ItineraryIssueCode.ch06InsufficientTransfer);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.blocking);
      expect(issues.first.locationId, after.slots[1].location.id);
      expect(issues.first.message, contains('245 分钟'));
    });
  });

  // -------------------------------------------------------------------------
  // CH-08 日总时长（P1）
  // -------------------------------------------------------------------------
  group('CH-08', () {
    test('非住宿活动跨度 13 小时30分 → 提醒（阈值 12 小时=产品判断）', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '08:00', stayMinutes: 300),
        loc(name: 'B', transportMinutes: 30, stayMinutes: 480),
      ]));

      final issues = codes(r, ItineraryIssueCode.ch08LongDay);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.reminder);
      expect(issues.first.message, contains('08:00'));
      expect(issues.first.message, contains('21:30'));
      expect(issues.first.message, contains('13小时30分'));
    });

    test('跨度不足 12 小时不触发；时间链不可靠也不触发', () {
      final short = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '09:00', stayMinutes: 240),
        loc(name: 'B', transportMinutes: 30, stayMinutes: 120),
      ]));
      expect(codes(short, ItineraryIssueCode.ch08LongDay), isEmpty);

      final unreliable = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '08:00', stayMinutes: 300),
        loc(name: 'B', transportMinutes: 30), // stay 缺失 → 该站不可靠
      ]));
      expect(codes(unreliable, ItineraryIssueCode.ch08LongDay), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // CH-09 未校验声明
  // -------------------------------------------------------------------------
  group('CH-09', () {
    test('老行程景点缺营业字段 → 日级中性披露一处，不归责到卡片', () {
      final r = checkItineraryDay(day([
        loc(name: '老景点A', arrivalTime: '09:00', stayMinutes: 120),
        loc(name: '餐厅', type: LocationType.restaurant, arrivalTime: '12:00', stayMinutes: 60),
      ]));

      expect(r.uncheckedAttractionCount, 1); // 餐厅不计入
      final issues = codes(r, ItineraryIssueCode.ch09OpenHoursUnknown);
      expect(issues.length, 1);
      expect(issues.first.severity, IssueSeverity.neutral);
      expect(issues.first.locationId, isNull);
      expect(issues.first.message, contains('1 个景点'));
      // 卡片上一条提示都没有
      expect(r.primaryIssueByLocation, isEmpty);
    });

    test('已校验景点不计入 CH-09；多时段（open/close 全 null）仍计入', () {
      final verified = checkItineraryDay(day([
        loc(
          name: '故宫',
          arrivalTime: '09:00',
          stayMinutes: 120,
          openTime: '08:30',
          closeTime: '17:00',
          closedOnDate: false,
          openHoursRaw: '08:30-17:00',
        ),
      ]));
      expect(verified.uncheckedAttractionCount, 0);
      expect(codes(verified, ItineraryIssueCode.ch09OpenHoursUnknown), isEmpty);

      // 多时段：服务端五字段全 null，只留 segments → 客户端无从校验，诚实披露
      final multi = checkItineraryDay(day([
        Location(
          name: '多时段餐厅',
          address: 'x',
          type: LocationType.attraction,
          arrivalTime: '09:00',
          stayMinutes: 120,
          openSegments: const [
            OpenSegment(open: '11:00', close: '14:00'),
            OpenSegment(open: '16:00', close: '22:00'),
          ],
        ),
      ]));
      expect(multi.uncheckedAttractionCount, 1);
      expect(codes(multi, ItineraryIssueCode.ch01LateEntry), isEmpty);
    });

    test('明确闭馆的景点不算"未校验"（它是成功解析）', () {
      final r = checkItineraryDay(day([
        loc(name: '苏博', arrivalTime: '09:00', stayMinutes: 120, closedOnDate: true, openHoursRaw: '周一闭馆'),
      ]));

      expect(r.uncheckedAttractionCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  // 去重 / 主问题
  // -------------------------------------------------------------------------
  group('同地点最多一条', () {
    test('同地点同时闭馆 + 停留为 0 → 只显示 CH-03（CH-03 优先级更高）', () {
      final r = checkItineraryDay(day([
        loc(
          name: '苏博',
          arrivalTime: '09:00',
          stayMinutes: 0,
          closedOnDate: true,
          openHoursRaw: '周一闭馆',
        ),
      ]));

      expect(r.issues.length, 2); // 全量保留两条
      final primary = primaryIssueForLocation(r, r.slots.first.location.id);
      expect(primary, isNotNull);
      expect(primary!.code, ItineraryIssueCode.ch03ClosedDate);
      expect(r.primaryIssueByLocation.length, 1);
    });

    test('阻塞优先于提醒：CH-01 阻塞 + CH-05 停留过短 → 取阻塞', () {
      final r = checkItineraryDay(day([
        loc(
          name: '故宫',
          arrivalTime: '16:50',
          stayMinutes: 10,
          openTime: '08:30',
          closeTime: '17:00',
          lastEntryTime: '16:00',
          closedOnDate: false,
          openHoursRaw: '08:30-17:00，16:00 停止检票',
        ),
      ]));

      final primary = primaryIssueForLocation(r, r.slots.first.location.id);
      expect(primary!.severity, IssueSeverity.blocking);
      expect(primary.code, ItineraryIssueCode.ch01LateEntry);
    });

    test('计数与展示口径一致：摘要说几条就有几条', () {
      final r = checkItineraryDay(day([
        loc(name: 'A', arrivalTime: '08:00', stayMinutes: 480),
        loc(name: 'B', transportMinutes: 30, stayMinutes: 480), // 跨午夜
        loc(name: 'C', arrivalTime: '08:00', stayMinutes: 5), // 停留过短
      ]));

      expect(r.blockingCount, r.displayIssues.where((i) => i.severity == IssueSeverity.blocking).length);
      expect(r.reminderCount, r.displayIssues.where((i) => i.severity == IssueSeverity.reminder).length);
      expect(r.blockingCount, 1);
    });

    test('primaryIssueForLocation 对未知地点返回 null', () {
      final r = checkItineraryDay(day([loc(name: 'A', arrivalTime: '09:00', stayMinutes: 60)]));
      expect(primaryIssueForLocation(r, 'not-exist'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 纯函数性 / 编辑重算
  // -------------------------------------------------------------------------
  group('纯函数性', () {
    test('相同输入两次调用结果完全一致（不依赖时间/随机）', () {
      final d = day([
        loc(
          name: '故宫',
          arrivalTime: '16:50',
          stayMinutes: 60,
          openTime: '08:30',
          closeTime: '17:00',
          lastEntryTime: '16:00',
          closedOnDate: false,
          openHoursRaw: '08:30-17:00，16:00 停止检票',
        ),
      ]);

      final a = checkItineraryDay(d);
      final b = checkItineraryDay(d);

      expect(a.issues.length, b.issues.length);
      expect(a.blockingCount, b.blockingCount);
      for (var i = 0; i < a.issues.length; i++) {
        expect(a.issues[i].code, b.issues[i].code);
        expect(a.issues[i].message, b.issues[i].message);
      }
    });

    test('编辑重算：停留 60 → 180 后跨午夜结果立即变化', () {
      final locations = [
        loc(name: 'A', arrivalTime: '20:00', stayMinutes: 60),
        loc(name: 'B', transportMinutes: 30, stayMinutes: 60),
      ];
      final before = checkItineraryDay(day(locations));
      expect(codes(before, ItineraryIssueCode.ch04OverMidnight), isEmpty); // 日终 1350

      // 用户把 A 的停留从 60 改到 180 → 日终 20:00(1200)+180+30+60 = 1470 > 1440
      locations[0].stayMinutes = 180;
      final after = checkItineraryDay(day(locations));
      expect(codes(after, ItineraryIssueCode.ch04OverMidnight).length, 1);
    });

    test('日期变化清空营业事实后走 CH-09，不再产出旧日期的营业结论', () {
      final poi = loc(
        name: '故宫',
        arrivalTime: '16:50',
        stayMinutes: 60,
        openTime: '08:30',
        closeTime: '17:00',
        lastEntryTime: '16:00',
        closedOnDate: false,
        openHoursRaw: '08:30-17:00，16:00 停止检票',
      );
      final before = checkItineraryDay(day([poi]));
      expect(codes(before, ItineraryIssueCode.ch01LateEntry).length, 1);

      poi.clearOpenHoursFacts();
      final after = checkItineraryDay(day([poi]));
      expect(codes(after, ItineraryIssueCode.ch01LateEntry), isEmpty);
      expect(after.uncheckedAttractionCount, 1);
    });

    test('全规则通过时不产出任何问题（页面不得渲染"已校验通过"）', () {
      final r = checkItineraryDay(day([
        loc(
          name: '上博',
          arrivalTime: '09:30',
          stayMinutes: 120,
          openTime: '09:00',
          closeTime: '17:00',
          closedOnDate: false,
          openHoursRaw: '09:00-17:00',
        ),
        loc(
          name: '餐厅',
          type: LocationType.restaurant,
          arrivalTime: '12:00',
          transportMinutes: 20,
          stayMinutes: 60,
        ),
      ]));

      expect(r.displayIssues, isEmpty);
      expect(r.hasAnyIssue, isFalse);
      expect(r.hasBlocking, isFalse);
      expect(r.uncheckedAttractionCount, 0);
    });
  });
}
