import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/utils/itinerary_checker.dart';

/// 真实 payload 回归（T05）：把工程师留的 generate 产物快照喂给**线上同一份**
/// `checkItineraryDay`，验证「宁可少显示，不可显示错」。
///
/// ## 快照来源（git 仓库外，不会误提交）
/// - `deliverables/_fx-arrivaltime-payload.json`     2026-10-01（周四）出发
/// - `deliverables/_fx-arrivaltime-payload-mon.json` 2026-10-05（周一）出发
///
/// ## 判定口径（PRD v1.1 §1.3 / §5）
/// - 未编辑行程：CH-01/02/03/06/07/08 **零假阳性**（唯一合理产物是诚实的 CH-09）；
/// - 周一出发快照：故宫必须产出 **CH-03 阻塞且带原文副行**；
/// - 编辑（改停留时长）后：校验必须按纯加法链**正确重算**（CH-06/CH-01 亮起、还原后熄灭）。
///
/// 快照缺失时 **skip 而非 fail**：本测试是回归证据，不是其他机器的依赖。
const _kBasePath = r'C:/Users/win11/WorkBuddy/AITrip/deliverables/_fx-arrivaltime-payload.json';
const _kMonPath = r'C:/Users/win11/WorkBuddy/AITrip/deliverables/_fx-arrivaltime-payload-mon.json';

List<TripDay> _loadDays(String path) {
  final raw = File(path).readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return (json['days'] as List)
      .map((d) => TripDay.fromJson(Map<String, dynamic>.from(d as Map)))
      .toList();
}

/// 一行证据：`day[N] [severity] CH-xx @地点：message（原文：…）`
String _fmt(List<TripDay> days) {
  final buf = StringBuffer();
  for (final day in days) {
    final r = checkItineraryDay(day);
    if (r.issues.isEmpty) {
      buf.writeln('  day${day.dayNumber} (${day.date.toIso8601String().substring(0, 10)}): 无任何问题');
      continue;
    }
    for (final i in r.issues) {
      final locName = day.locations
          .firstWhere((l) => l.id == i.locationId, orElse: () => day.locations.first)
          .name;
      buf.writeln('  day${day.dayNumber} [${i.severity.name}] ${i.code.label} @$locName：${i.message}'
          '${i.sourceRaw == null ? '' : '（原文：${i.sourceRaw}）'}');
    }
  }
  return buf.toString().trimRight();
}

void main() {
  final haveSnapshots = File(_kBasePath).existsSync() && File(_kMonPath).existsSync();

  group('真实 payload 回归（T05）', () {
    // -----------------------------------------------------------------------
    // 1. 未编辑行程：CH-01/02/03/06/07/08 零假阳性
    // -----------------------------------------------------------------------
    test('周四出发快照：全 3 天不产出任何阻塞/提醒，唯一产物是诚实的 CH-09', () {
      if (!haveSnapshots) {
        markTestSkipped('快照缺失：$_kBasePath / $_kMonPath（仓库外文件，其他机器正常 skip）');
      }
      final days = _loadDays(_kBasePath);

      // 证据全量打印（报告引用）
      debugPrint('--- 未编辑（周四出发）---\n${_fmt(days)}');

      for (final day in days) {
        final r = checkItineraryDay(day);
        final bad = r.issues
            .where((i) => i.code != ItineraryIssueCode.ch09OpenHoursUnknown)
            .toList();
        expect(bad, isEmpty,
            reason: 'day${day.dayNumber} 未编辑行程出现假阳性：${bad.map((i) => i.code.label).toList()}');
        expect(r.blockingCount, 0, reason: 'day${day.dayNumber} 不得有阻塞');
        expect(r.reminderCount, 0, reason: 'day${day.dayNumber} 不得有提醒');
      }

      // CH-09 必须诚实存在：day1 故宫无营业时间 → 1 个景点未校验
      final d1 = checkItineraryDay(days[0]);
      expect(d1.uncheckedAttractionCount, 1, reason: '故宫 opentime2 探针为空 → CH-09 披露');
      expect(d1.issues.single.code, ItineraryIssueCode.ch09OpenHoursUnknown);
      expect(d1.issues.single.severity, IssueSeverity.neutral);
      expect(d1.issues.single.locationId, isNull, reason: 'CH-09 是日级问题，不归责卡片');

      // day2/day3 全部已校验或无景点 → 无 CH-09、无任何问题
      expect(checkItineraryDay(days[1]).issues, isEmpty);
      expect(checkItineraryDay(days[2]).issues, isEmpty);
    });

    // -----------------------------------------------------------------------
    // 2. 周一出发：CH-03 闭馆必须亮且带原文副行
    // -----------------------------------------------------------------------
    test('周一出发快照：故宫 CH-03 阻塞 + 原文副行，其余天零假阳性', () {
      if (!haveSnapshots) {
        markTestSkipped('快照缺失：$_kMonPath');
      }
      final days = _loadDays(_kMonPath);

      debugPrint('--- 未编辑（周一出发）---\n${_fmt(days)}');

      final d1 = checkItineraryDay(days[0]);
      final ch03 = d1.issues.where((i) => i.code == ItineraryIssueCode.ch03ClosedDate).toList();
      expect(ch03.length, 1, reason: '周一出发故宫必须亮 CH-03');
      expect(ch03.single.severity, IssueSeverity.blocking);
      expect(ch03.single.locationId, days[0].locations.first.id);
      // 副行必须带服务端原文切片（PRD §6.4 来源透明）
      expect(ch03.single.sourceRaw, '周一 不开放');
      expect(d1.blockingCount, 1);
      // 故宫是"成功解析出闭馆"，不计入 CH-09
      expect(d1.uncheckedAttractionCount, 0);

      for (final day in [days[1], days[2]]) {
        final r = checkItineraryDay(day);
        expect(r.issues, isEmpty, reason: 'day${day.dayNumber} 不得有假阳性');
      }
    });

    // -----------------------------------------------------------------------
    // 3. 风险③锁定：fmt() 绕回的酒店到达（00:58 实为 24:58）不得产生
    //    负分钟数 / 荒谬差值（CH-06）或住店误报（CH-04）
    // -----------------------------------------------------------------------
    test('周一快照 day2：酒店 00:58 绕回到达 → CH-06/CH-04 零误报', () {
      if (!haveSnapshots) {
        markTestSkipped('快照缺失：$_kMonPath');
      }
      final days = _loadDays(_kMonPath);
      final day2 = days[1];
      final hotel = day2.locations.last;
      expect(hotel.type, LocationType.hotel);
      expect(hotel.arrivalTime, '00:58'); // fmt() mod 1440 后的绕回值

      final r = checkItineraryDay(day2);
      expect(r.issues.where((i) => i.code == ItineraryIssueCode.ch06InsufficientTransfer), isEmpty,
          reason: '绕回值必须按锚单调展开后再比较');
      expect(r.issues.where((i) => i.code == ItineraryIssueCode.ch07TightBuffer), isEmpty);
      expect(r.issues.where((i) => i.code == ItineraryIssueCode.ch04OverMidnight), isEmpty,
          reason: '正常住店不得误报"排过午夜"');
      // 反断言：没有任何消息包含负分钟差（荒谬结论的指纹）
      for (final i in r.issues) {
        expect(i.message, isNot(contains('-')));
      }
    });

    // -----------------------------------------------------------------------
    // 4. 编辑后重算：改停留时长 → CH-06 亮起；还原 → 熄灭
    // -----------------------------------------------------------------------
    test('编辑重算①：day1 故宫停留 120→420 后，什刹海 CH-06 阻塞亮起（245 分钟）', () {
      if (!haveSnapshots) {
        markTestSkipped('快照缺失：$_kBasePath');
      }
      final days = _loadDays(_kBasePath);
      final day1 = days[0];
      final gugong = day1.locations.first;
      final shichahai = day1.locations[1];

      // 编辑前：服务端零缓冲规划态（gap == travel），无任何转场问题
      expect(checkItineraryDay(day1).issues.where((i) => i.locationId == shichahai.id), isEmpty);

      // 用户把故宫停留从 120 拉到 420：重建离开 = 09:00 + 420min = 16:00，
      // 晚于原计划到达 11:55 共 245 分钟，而交通只需 55 分钟 → CH-06 阻塞
      gugong.stayMinutes = 420;
      final after = checkItineraryDay(day1);
      debugPrint('--- 编辑后（故宫停留 120→420）---\n${_fmt([day1])}');

      final ch06 = after.issues
          .where((i) => i.code == ItineraryIssueCode.ch06InsufficientTransfer && i.locationId == shichahai.id)
          .toList();
      expect(ch06.length, 1, reason: '编辑后必须按纯加法链重算出 CH-06');
      expect(ch06.single.severity, IssueSeverity.blocking);
      expect(ch06.single.message, contains('245 分钟'));
      expect(ch06.single.message, contains('11:55'));
      expect(ch06.single.message, contains('16:00'));
      // 主问题即 CH-06；CH-07 不得同时亮（CH-06 已触发时 CH-07 不评估）
      expect(primaryIssueForLocation(after, shichahai.id)!.code, ItineraryIssueCode.ch06InsufficientTransfer);
      expect(after.issues.where((i) => i.code == ItineraryIssueCode.ch07TightBuffer), isEmpty);

      // 还原 → 立即熄灭（重算不是缓存）
      gugong.stayMinutes = 120;
      expect(checkItineraryDay(day1).issues.where((i) => i.locationId == shichahai.id), isEmpty);
    });

    test('编辑重算②：day3 雁栖湖停留 120→500 后，餐厅 CH-01 打烊阻塞亮起', () {
      if (!haveSnapshots) {
        markTestSkipped('快照缺失：$_kBasePath');
      }
      final days = _loadDays(_kBasePath);
      final day3 = days[2];
      final trail = day3.locations.first;
      final dinner = day3.locations.last;
      expect(dinner.type, LocationType.restaurant);
      expect(dinner.closeTime, '22:00');

      expect(checkItineraryDay(day3).issues, isEmpty);

      // 雁栖湖 13:31(811) + 500min → 21:51 离开；+10min 步行 → 餐厅 22:01 到达，
      // 已过 22:00 打烊 → CH-01 阻塞（同时 CH-06 亮，主问题取优先级更高的 CH-01）
      trail.stayMinutes = 500;
      final after = checkItineraryDay(day3);
      debugPrint('--- 编辑后（雁栖湖停留 120→500）---\n${_fmt([day3])}');

      final ch01 = after.issues
          .where((i) => i.code == ItineraryIssueCode.ch01LateEntry && i.locationId == dinner.id)
          .toList();
      expect(ch01.length, 1, reason: '日终推进到打烊后必须亮 CH-01');
      expect(ch01.single.severity, IssueSeverity.blocking);
      expect(ch01.single.message, contains('22:01'));
      expect(ch01.single.message, contains('22:00'));
      expect(
          after.issues.where((i) => i.code == ItineraryIssueCode.ch06InsufficientTransfer).length, 1,
          reason: '原计划 21:02 到达早于重建离开 21:51 → CH-06 同亮');
      expect(primaryIssueForLocation(after, dinner.id)!.code, ItineraryIssueCode.ch01LateEntry);

      trail.stayMinutes = 120;
      expect(checkItineraryDay(day3).issues, isEmpty, reason: '还原后必须熄灭');
    });
  });

  // ---------------------------------------------------------------------------
  // 5. 老行程降级：SR-OH1 上线前生成的旧 payload 缺全部营业字段
  // ---------------------------------------------------------------------------
  group('老行程降级（T05）', () {
    /// 旧 payload 的地点 JSON：只有 T02 之前的字段（无 openTime/closeTime/
    /// lastEntryTime/closedOnDate/openHoursRaw/openSegments，也无 arrivalTime/leaveTime）。
    Map<String, dynamic> legacyLoc(String name, LocationType type, int stay, int? travel) => {
          'name': name,
          'address': '老地址',
          'type': type.name,
          'stayMinutes': stay,
          'transportMinutes': travel,
        };

    test('旧 payload fromJson 不抛异常，校验器不出阻塞/提醒，走 CH-09 日级披露', () {
      final day = TripDay.fromJson({
        'date': '2026-08-01T00:00:00.000',
        'dayNumber': 1,
        'locations': [
          legacyLoc('老景点A', LocationType.attraction, 120, null),
          legacyLoc('老景点B', LocationType.attraction, 90, 30),
          legacyLoc('老餐厅', LocationType.restaurant, 60, 20),
        ],
      });

      // 缺字段必须解析为 null（不抛、不兜底）
      for (final l in day.locations) {
        expect(l.openTime, isNull);
        expect(l.closeTime, isNull);
        expect(l.lastEntryTime, isNull);
        expect(l.closedOnDate, isNull);
        expect(l.openHoursRaw, isNull);
        expect(l.openSegments, isNull);
        expect(l.arrivalTime, isNull);
        expect(l.leaveTime, isNull);
      }

      final r = checkItineraryDay(day);
      // 无锚 → 时间链整条不可靠 → 所有依赖时刻的规则静默跳过
      expect(r.blockingCount, 0, reason: '老行程不得出阻塞级误报');
      expect(r.reminderCount, 0, reason: '老行程不得出提醒级误报');
      expect(r.primaryIssueByLocation, isEmpty, reason: '任何卡片都不应被亮灯');
      // 唯一产物：CH-09 日级中性披露（2 个景点未校验，餐厅不计入）
      final ch09 = r.issues.where((i) => i.code == ItineraryIssueCode.ch09OpenHoursUnknown).toList();
      expect(ch09.length, 1);
      expect(ch09.single.severity, IssueSeverity.neutral);
      expect(ch09.single.locationId, isNull);
      expect(r.uncheckedAttractionCount, 2);
      expect(r.displayIssues.length, 1, reason: '日级声明是唯一展示物');
    });

    test('旧 payload 带 arrivalTime 但无营业字段：仍只走 CH-09，不猜营业时间', () {
      final day = TripDay.fromJson({
        'date': '2026-08-01T00:00:00.000',
        'dayNumber': 1,
        'locations': [
          {
            'name': '老景点A',
            'address': '老地址',
            'type': 'attraction',
            'stayMinutes': 90,
            'arrivalTime': '21:30', // 看起来很"晚"，但无营业数据 → 不得猜打烊
            'leaveTime': '23:00',
          },
        ],
      });

      final r = checkItineraryDay(day);
      expect(r.blockingCount, 0, reason: '21:30 到达不得被猜成"已打烊"');
      expect(r.reminderCount, 0);
      expect(r.issues.single.code, ItineraryIssueCode.ch09OpenHoursUnknown);
      expect(r.uncheckedAttractionCount, 1);
    });

    test('旧 payload 含非法时刻（25:30）：不抛异常，按不可解析降级', () {
      final day = TripDay.fromJson({
        'date': '2026-08-01T00:00:00.000',
        'dayNumber': 1,
        'locations': [
          {
            'name': '老景点A',
            'address': '老地址',
            'type': 'attraction',
            'stayMinutes': 120,
            'arrivalTime': '23:30',
            'leaveTime': '25:30', // 非法小时 → parseClockMinutes 返回 null
          },
        ],
      });

      final r = checkItineraryDay(day);
      // 23:30 + 120min = 次日 01:30：跨午夜是纯时刻算术事实，CH-04 属正确判定；
      // 但营业类（CH-01/02/03）一条都不许出
      expect(r.issues.where((i) => i.code == ItineraryIssueCode.ch01LateEntry), isEmpty);
      expect(r.issues.where((i) => i.code == ItineraryIssueCode.ch02EarlyArrival), isEmpty);
      expect(r.issues.where((i) => i.code == ItineraryIssueCode.ch03ClosedDate), isEmpty);
      expect(r.uncheckedAttractionCount, 1);
    });
  });
}
