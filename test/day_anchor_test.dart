import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/utils/day_anchor.dart';
import 'package:trip_planner/widgets/timeline/day_anchor_table.dart';

/// 「滚动联动 / 日期切换」防线的纯逻辑测试（T01 纯函数层）。
///
/// ## 被测对象
/// `trip/lib/utils/day_anchor.dart` 的 [DayAnchor] 静态类 —— 三个**零 Flutter 依赖**
/// 的纯函数：滚动位置 → 属于第几天、点选某天 → 目标滚动位置、横滚模式 → 选中格居中。
///
/// 这段逻辑历史上出过 **208dp 过度下滚**的真 bug（见 `deliverables/P1-真机验证清单`），
/// 却长期没有任何自动化防线。本文件就是它的长期防线。
///
/// ## 期望值怎么来的（本文件的硬纪律）
/// **不抄源码、不从运行结果倒推**。每条期望值都按下面的规格语义**独立手算**：
///
/// 1. `activeIndexFor(offsets, y)` = 「最后一个满足 `offset <= y` 的下标」；
///    若没有任何 `offset <= y`，取 0。`<=` 含等号。
/// 2. `targetOffset(offset, epsilon)` = `max(offset - epsilon, 0)`。
/// 3. `centeredScrollOffset(...)` = `clamp(index*cellWidth - (viewportWidth-cellWidth)/2, 0, maxScroll)`。
///
/// 3. 里 `count` 参数**不参与计算**，因此本文件不对它编造行为断言，
///    只守住「传 0 / 负数不得抛异常」这条契约。
///
/// ## 前提声明
/// `activeIndexFor` 的契约前提是 offsets **升序**（源码注释：「各分组头相对列表内容
/// 顶部的偏移（升序）」）。本文件所有用例都满足该前提。
///
/// `centeredScrollOffset` 的契约前提是 `maxScroll >= 0`（真实来源是
/// `ScrollPosition.maxScrollExtent`，内容短于视口时为 0，不会为负）。
/// `viewportWidth >= cellWidth`（真实来源是屏幕宽 vs 44dp 格宽）。
/// 这两条前提之外的组合本文件不写金标 —— 那是**契约外**，不是防线。
void main() {
  // ===========================================================================
  // ① activeIndexFor —— 判定「当前滚动位置属于第几天」
  // ===========================================================================
  group('① activeIndexFor：取最后一个 offset <= y 的下标', () {
    test('正常落段：offsets=[0,500,1000]，y=600 → 1', () {
      // 手算：0<=600 ✓(下标0)、500<=600 ✓(下标1)、1000<=600 ✗ → 最后一个满足的是下标1。
      expect(DayAnchor.activeIndexFor([0, 500, 1000], 600), 1);
    });

    test('边界相等：offsets=[0,500,1000]，y=500 → 1（<= 含等号，不是 <）', () {
      // 手算：0<=500 ✓、500<=500 ✓、1000<=500 ✗ → 下标1。
      // 若实现写成 `<`，这里会得 0 —— 这条用例正是守住 `<=`。
      expect(DayAnchor.activeIndexFor([0, 500, 1000], 500), 1);
    });

    test('未到任何一天：offsets=[100,200,300]，y=50 → 0', () {
      // 手算：没有任何 offset <= 50 → 取兜底 0。
      expect(DayAnchor.activeIndexFor([100, 200, 300], 50), 0);
    });

    test('y 正好等于最后一天起点：offsets=[0,500,1000]，y=1000 → 2', () {
      // 手算：三个都 <= 1000 → 最后一个是下标2。
      expect(DayAnchor.activeIndexFor([0, 500, 1000], 1000), 2);
    });

    test('超出末尾：offsets=[0,500,1000]，y=5000 → 2（不越界）', () {
      // 手算：仍取最后一个满足者 = 2，不得越界成 3。
      expect(DayAnchor.activeIndexFor([0, 500, 1000], 5000), 2);
    });

    test('空列表 → 0（不抛异常）', () {
      expect(DayAnchor.activeIndexFor([], 0), 0);
      expect(DayAnchor.activeIndexFor([], 123.45), 0);
    });

    test('单元素：[0]，y=0 → 0；[0]，y=999 → 0', () {
      // 手算：只有下标0，无论 y 多大都落在下标0。
      expect(DayAnchor.activeIndexFor([0], 0), 0);
      expect(DayAnchor.activeIndexFor([0], 999), 0);
    });

    test('紧贴上一段末尾：offsets=[0,500,1000]，y=499 → 0', () {
      // 手算：0<=499 ✓、500<=499 ✗ → 最后一个满足的是下标0。
      expect(DayAnchor.activeIndexFor([0, 500, 1000], 499), 0);
    });

    test('紧贴下一段起点前一格：offsets=[0,500,1000]，y=999 → 1', () {
      // 手算：0<=999 ✓、500<=999 ✓、1000<=999 ✗ → 下标1。
      expect(DayAnchor.activeIndexFor([0, 500, 1000], 999), 1);
    });

    test('y 为负（内容坐标还没到第一段）：offsets=[0,500,1000]，y=-100 → 0', () {
      // 手算：0<=-100 ✗，其余更大 ✗ → 无满足者 → 兜底 0。
      expect(DayAnchor.activeIndexFor([0, 500, 1000], -100), 0);
    });

    test('分段常量：对升序 offsets，每段 [offsets[i], offsets[i+1]) 上结果恒为 i', () {
      // 手算：对每个 i，y 取段左端与右端前一格都应落在 i；
      //      y 取右端（下一段起点）应落到 i+1。
      const offsets = [0.0, 120.0, 480.0, 900.0];
      for (var i = 0; i < offsets.length; i++) {
        final left = offsets[i];
        final right = i + 1 < offsets.length ? offsets[i + 1] : left + 1000;
        expect(DayAnchor.activeIndexFor(offsets, left), i,
            reason: '段左端 $left 应属于第 $i 天');
        expect(
          DayAnchor.activeIndexFor(offsets, right - 0.01),
          i,
          reason: '段内 $right 前一格应属于第 $i 天',
        );
        if (i + 1 < offsets.length) {
          expect(
            DayAnchor.activeIndexFor(offsets, right),
            i + 1,
            reason: '段右端 $right 是第 ${i + 1} 天的起点',
          );
        }
      }
    });
  });

  // ===========================================================================
  // ② targetOffset —— 点选某天时的目标滚动位置
  // ===========================================================================
  group('② targetOffset：max(offset - epsilon, 0)', () {
    test('正常扣减：offset=500, epsilon=4 → 496', () {
      // 手算：500-4 = 496，不为负 → 496。
      expect(DayAnchor.targetOffset(500), 496);
    });

    test('扣减后为负 → 钳制 0：offset=3, epsilon=4 → 0（不是 -1）', () {
      // 手算：3-4 = -1 < 0 → 钳制 0。
      // 若漏掉钳制，这里会得 -1，滚动到负偏移 = 208dp 过度下滚那类事故的同源问题。
      expect(DayAnchor.targetOffset(3, epsilon: 4), 0);
    });

    test('恰好为 0：offset=4, epsilon=4 → 0', () {
      // 手算：4-4 = 0，0 不 < 0 → 0。
      expect(DayAnchor.targetOffset(4, epsilon: 4), 0);
    });

    test('epsilon 自定义：offset=100, epsilon=10 → 90', () {
      // 手算：100-10 = 90。
      expect(DayAnchor.targetOffset(100, epsilon: 10), 90);
    });

    test('offset=0 → 0（0-4 = -4，钳制后为 0）', () {
      // 手算：0-4 = -4 < 0 → 0。
      expect(DayAnchor.targetOffset(0), 0);
    });

    test('默认 epsilon 是 4：offset=10 → 6', () {
      // 手算：默认 epsilon=4 → 10-4 = 6。
      // 调用方 `DayAnchorTable.targetFor` 与页面 `activeIndex` 都用默认值，
      // 所以默认值本身就是契约的一部分。
      expect(DayAnchor.targetOffset(10), 6);
      expect(DayAnchor.targetOffset(10, epsilon: 4), 6);
    });

    test('小数偏移：offset=4.5, epsilon=4 → 0.5', () {
      // 手算：4.5-4 = 0.5 > 0 → 0.5（不做取整）。
      expect(DayAnchor.targetOffset(4.5), 0.5);
    });

    test('自定义 epsilon 且为负：offset=100, epsilon=-10 → 110', () {
      // 手算：100-(-10) = 110，不为负 → 110（epsilon 只做减法，不做绝对值）。
      expect(DayAnchor.targetOffset(100, epsilon: -10), 110);
    });
  });

  // ===========================================================================
  // ③ centeredScrollOffset —— ">7 天横滚模式"把选中格居中
  // ===========================================================================
  group(
      '③ centeredScrollOffset：clamp(index*cellWidth - (viewportWidth-cellWidth)/2, 0, maxScroll)',
      () {
    // 格宽 44.0 取自 `DayStrip.cellWidth`（lib/widgets/timeline/day_strip.dart:36）。
    const double cellWidth = 44.0;
    // 视口宽 220 = 5 格，符合「>7 天横滚」时一屏能放下 5 格的典型手机宽度。
    const double viewportWidth = 220.0;

    test('中间格居中：index=5, cellWidth=44, viewportWidth=220 → 132', () {
      // 手算：5*44 = 220；(220-44)/2 = 88；220-88 = 132。
      // 132 < maxScroll(=300) 且 > 0 → 不触发任何钳制。
      expect(
        DayAnchor.centeredScrollOffset(
          index: 5,
          count: 14,
          cellWidth: cellWidth,
          viewportWidth: viewportWidth,
          maxScroll: 300,
        ),
        132,
      );
    });

    test('首格钳制：index=0 → 0（target 本来就是负数）', () {
      // 手算：0*44 = 0；0-88 = -88 < 0 → 0。
      expect(
        DayAnchor.centeredScrollOffset(
          index: 0,
          count: 14,
          cellWidth: cellWidth,
          viewportWidth: viewportWidth,
          maxScroll: 300,
        ),
        0,
      );
    });

    test('末格钳制：index=13, maxScroll=100 → 100（不超过 maxScroll、不为负）', () {
      // 手算：13*44 = 572；572-88 = 484 > 100 → 钳到 maxScroll=100。
      expect(
        DayAnchor.centeredScrollOffset(
          index: 13,
          count: 14,
          cellWidth: cellWidth,
          viewportWidth: viewportWidth,
          maxScroll: 100,
        ),
        100,
      );
    });

    test('恰好落在 maxScroll 上：index=3, maxScroll=44 → 44（严格大于才钳制，等于原样返回）', () {
      // 手算：要让 target 恰等于 maxScroll=44，需要 index*44-88 = 44 → index*44 = 132 → index=3。
      // 此时 target == maxScroll，实现走 `target > maxScroll` 的严格大于 → 原样返回 44。
      expect(
        DayAnchor.centeredScrollOffset(
          index: 3,
          count: 14,
          cellWidth: cellWidth,
          viewportWidth: viewportWidth,
          maxScroll: 44,
        ),
        44,
      );
    });

    test('不变量：对一组 index，结果恒在 [0, maxScroll] 内', () {
      const maxScroll = 137.0;
      for (var index = 0; index <= 20; index++) {
        final offset = DayAnchor.centeredScrollOffset(
          index: index,
          count: 21,
          cellWidth: cellWidth,
          viewportWidth: viewportWidth,
          maxScroll: maxScroll,
        );
        expect(offset, greaterThanOrEqualTo(0), reason: 'index=$index 不得为负');
        expect(offset, lessThanOrEqualTo(maxScroll),
            reason: 'index=$index 不得超过 maxScroll');
      }
    });

    test('不变量：结果随 index 单调不减（选中格右移，滚动位置不得回退）', () {
      // 手算依据：target(index) = index*44-88，每步 +44 严格递增；
      // 钳制函数 clamp(·,0,maxScroll) 是单调不减的，两者复合仍单调不减。
      const maxScroll = 300.0;
      var previous = double.negativeInfinity;
      for (var index = 0; index <= 13; index++) {
        final offset = DayAnchor.centeredScrollOffset(
          index: index,
          count: 14,
          cellWidth: cellWidth,
          viewportWidth: viewportWidth,
          maxScroll: maxScroll,
        );
        expect(offset, greaterThanOrEqualTo(previous),
            reason: 'index=$index 出现回退');
        previous = offset;
      }
    });

    test('内容不足一屏（maxScroll=0）→ 恒为 0，不产生横向滚动', () {
      // 手算：target>0 时被钳到 0；target<0 时也返回 0 → 任何 index 都是 0。
      for (final index in [0, 1, 5, 13]) {
        expect(
          DayAnchor.centeredScrollOffset(
            index: index,
            count: 14,
            cellWidth: cellWidth,
            viewportWidth: viewportWidth,
            maxScroll: 0,
          ),
          0,
          reason: 'index=$index',
        );
      }
    });

    test('count 传 0 或负数不得抛异常（count 不参与计算）', () {
      // 契约：count 不参与计算，故无论取何值都不得崩。
      for (final count in [0, -1, -100]) {
        expect(
          () => DayAnchor.centeredScrollOffset(
            index: 5,
            count: count,
            cellWidth: cellWidth,
            viewportWidth: viewportWidth,
            maxScroll: 300,
          ),
          returnsNormally,
          reason: 'count=$count',
        );
      }
    });
  });

  // ===========================================================================
  // ④ 边界与不变量总表
  // ===========================================================================
  group('④ 边界与不变量总表', () {
    test('activeIndexFor 结果恒在 [0, offsets.length-1]（空列表除外返回 0）', () {
      const cases = <List<double>>[
        [0, 500, 1000],
        [100, 200, 300],
        [0],
        [0, 1, 2, 3, 4, 5],
      ];
      for (final offsets in cases) {
        for (final y in [
          -100.0,
          0.0,
          0.5,
          1.0,
          2.5,
          100.0,
          499.0,
          500.0,
          999.0,
          1000.0,
          5000.0
        ]) {
          final index = DayAnchor.activeIndexFor(offsets, y);
          expect(index, greaterThanOrEqualTo(0),
              reason: 'offsets=$offsets y=$y');
          expect(index, lessThanOrEqualTo(offsets.length - 1),
              reason: 'offsets=$offsets y=$y');
        }
      }
      expect(DayAnchor.activeIndexFor([], 0), 0);
    });

    test('targetOffset 结果恒 >= 0（永不返回负数）', () {
      for (final offset in [
        0.0,
        0.5,
        1.0,
        3.0,
        4.0,
        4.5,
        10.0,
        100.0,
        5000.0
      ]) {
        for (final epsilon in [0.0, 1.0, 4.0, 10.0]) {
          expect(
            DayAnchor.targetOffset(offset, epsilon: epsilon),
            greaterThanOrEqualTo(0),
            reason: 'offset=$offset epsilon=$epsilon',
          );
        }
      }
    });

    test('centeredScrollOffset 结果恒在 [0, maxScroll]（maxScroll >= 0 的契约域内）', () {
      for (final maxScroll in [0.0, 1.0, 44.0, 137.0, 1000.0]) {
        for (var index = 0; index <= 20; index++) {
          final offset = DayAnchor.centeredScrollOffset(
            index: index,
            count: 21,
            cellWidth: 44.0,
            viewportWidth: 220.0,
            maxScroll: maxScroll,
          );
          expect(offset, greaterThanOrEqualTo(0),
              reason: 'maxScroll=$maxScroll index=$index');
          expect(offset, lessThanOrEqualTo(maxScroll),
              reason: 'maxScroll=$maxScroll index=$index');
        }
      }
    });

    test('联动闭环：点选第 i 天 → targetOffset → 再判定仍回到第 i 天（epsilon 的意义）', () {
      // 推导：点选第 i 天时目标 = offsets[i] - epsilon；滚动到位后判定用的
      // 视口坐标是 target + epsilon = offsets[i]，而 activeIndexFor 取
      // 「最后一个 offset <= y」→ 正好命中 i（前提：相邻段间距 > epsilon）。
      // 手算核对：offsets[i]=500 → target=496 → 496+4=500 <= 500 且 1000>500 → 下标1 ✓
      const offsets = [0.0, 500.0, 1000.0, 1500.0];
      const epsilon = 4.0;
      for (var i = 0; i < offsets.length; i++) {
        final target = DayAnchor.targetOffset(offsets[i], epsilon: epsilon);
        final back = DayAnchor.activeIndexFor(offsets, target + epsilon);
        expect(back, i, reason: '第 $i 天点选后应回到第 $i 天');
      }
    });

    test('联动闭环：偏移量小于 epsilon 时钳制到 0，判定仍落在首段', () {
      // 手算：offsets[0]=0 → target = max(0-4,0) = 0；0+4 = 4，
      // 而 offsets[1]=500 > 4 → 最后一个 <= 4 的是下标0 ✓
      const offsets = [0.0, 500.0, 1000.0];
      final target = DayAnchor.targetOffset(offsets.first);
      expect(target, 0);
      expect(DayAnchor.activeIndexFor(offsets, target + 4), 0);
    });
  });

  // ===========================================================================
  // ⑤ DayAnchorTable —— 真正承载「滚动联动」运行时状态的一层
  // ===========================================================================
  //
  // 上面测的是 [DayAnchor] 的三个**纯函数**；但滚动联动在运行时真正被持有的是
  // [DayAnchorTable]：它缓存各分组头的测量偏移、持有「测全才置干净」的脏标记、
  // 以及程序化滚动抑制标志。
  //
  // `day_anchor_table.dart:54-69` 锁着一个**已修复**的真 bug：
  // 原实现无条件 `_dirty = false`，长行程首帧只构建视口内的 item →
  // `keys[i].currentContext == null` → `offsets` 留下 null → `activeIndex` 因
  // `known.length != dayCount` 恒返回 0（所有天都不高亮）→ 而重测入口
  // `_onScroll: if (isDirty) _scheduleMeasure()` 已不再触发 → **高亮永久卡在
  // Day 1，滚动联动彻底失灵**。修复是"测全才置干净"。
  //
  // ⚠️ 这个修复此前**没有任何测试锁住**：谁把 `_dirty = false` 改回去，
  //    全量测试照样绿，产品静默失灵。本组就是那道锁。
  group('⑤ DayAnchorTable：滚动联动的运行时状态层', () {
    test('A1. 未测量（offsets 为空）→ activeIndex 恒返回 0，不抢高亮', () {
      // 推导（对照 day_anchor_table.dart:79-83 的守卫）：
      //   源码 `final List<double?> offsets = <double?>[];` —— 初始是**空列表**，
      //   只有 measure() 里才会 addAll(List.filled(dayCount, null))。
      //   → `known = offsets.whereType<double>().toList()` = []，长度 0 != dayCount(3)
      //   → 守卫 `if (known.length != dayCount) return 0;` 命中 → 恒 0。
      //   含义：还没测全时**不允许**用陈旧/缺失偏移去抢高亮（否则会乱跳）。
      final table = DayAnchorTable(dayCount: 3);
      expect(table.offsets, isEmpty, reason: 'measure() 之前 offsets 是空列表');
      expect(table.activeIndex(0), 0);
      expect(table.activeIndex(500), 0);
      expect(table.activeIndex(100000), 0);
      expect(table.activeIndex(-100), 0);
    });

    test('A2. 未测量 → targetFor 恒返回 null（页面据此下一帧重试）', () {
      // 推导：targetFor(i) 先取 offsetOf(i)；offsets 为空时
      // `if (i < 0 || i >= offsets.length) return null;` → 0 >= 0 → null
      // → targetFor 直接返回 null（不是 0）。
      // 语义：null = "还没量到"，页面会等下一帧再试；返回 0 会被误当成"滚到顶"。
      final table = DayAnchorTable(dayCount: 3);
      expect(table.targetFor(0), isNull);
      expect(table.targetFor(1), isNull);
      expect(table.targetFor(2), isNull);
      expect(table.targetFor(-1), isNull);
    });

    test('B. offsetOf：未测量 → null；越界（负数 / 等于 dayCount）→ null', () {
      // 推导：offsetOf 的守卫是 `i < 0 || i >= offsets.length` → null。
      // 未测量时 offsets.length == 0 → 任何下标（含 0）都是 null。
      final table = DayAnchorTable(dayCount: 3);
      expect(table.offsetOf(0), isNull, reason: '未测量');
      expect(table.offsetOf(2), isNull, reason: '未测量');
      expect(table.offsetOf(-1), isNull, reason: '越界：负数');
      expect(table.offsetOf(3), isNull, reason: '越界：等于 dayCount');
      expect(table.offsetOf(999), isNull, reason: '越界：远超 dayCount');
    });

    test('C. isDirty：新建即为 true；markDirty() 后仍为 true', () {
      // 推导：源码 `bool _dirty = true;` → 新建就是脏的（首帧必须测）。
      // markDirty() 只做 `_dirty = true`（内容变化后要求下一帧重测）。
      // ⛔ 本组**不**断言"测全后为 false" —— 那需要真实 RenderBox（见 E 组说明）。
      final table = DayAnchorTable(dayCount: 3);
      expect(table.isDirty, isTrue, reason: '新建即脏：首帧必须测');
      table.markDirty();
      expect(table.isDirty, isTrue, reason: 'markDirty 后仍为 true');
    });

    test('D. isProgrammatic：初始 false，可置 true 再复位（程序化滚动抑制 spy）', () {
      // 推导：源码 `bool isProgrammatic = false;` → 初始 false；
      // 置位/复位由页面在 animateTo 前后控制（day_anchor_table.dart:9-12 防抖三要点）。
      final table = DayAnchorTable(dayCount: 3);
      expect(table.isProgrammatic, isFalse);
      table.isProgrammatic = true;
      expect(table.isProgrammatic, isTrue);
      table.isProgrammatic = false;
      expect(table.isProgrammatic, isFalse);
    });

    test('E0. 结构契约：keys 长度 == dayCount，dayCount 透传', () {
      final table = DayAnchorTable(dayCount: 5);
      expect(table.dayCount, 5);
      expect(table.keys.length, 5);
      // keys 必须是互不相同的 GlobalKey（否则测量会串到别的天）
      expect(table.keys.toSet().length, 5);
    });

    testWidgets('E1. 构造性验证：内容短于视口 → 全部挂载 → isDirty 变 false',
        (tester) async {
      // ⚠️ **代表性边界（探针实测结论，勿删此注释）**：
      //   本用例的"测全"是靠 **item 总高 120×3 = 360px < 视口 600px**
      //   （内容比视口矮 → 全部挂载）实现的，**与 shrinkWrap 无关**。
      //   探针实测：生产同构的 `ListView(children:)` 与 `shrinkWrap:true` 的 ListView，
      //   在 10 个高 300 的 item / 400px 视口下**都是 7/10 未挂载**。
      //   → 决定 key 是否挂载的是「内容总高 vs 视口高」，不是 shrinkWrap 属性。
      //
      //   且「滚动到底让全部 key 同时挂载」在长列表里**不可达**：
      //   探针实测 6 个 300px item / 400px 视口，滚动到底后变成 day0-2 回收(NULL)、
      //   day3-5 挂载 —— 始终只有 3/6 挂载，视口外的会被回收。
      //
      //   ⇒ **生产长行程中"全部天同时挂载"不会发生**。本用例的价值在于锁定
      //      「测全 → `_dirty` 转 false、`offsets` 全非 null、`activeIndex` 允许按偏移判定」
      //      这条**分支逻辑本身**，不代表生产路径。
      //      生产路径由 E3「交替挂载 + 逐帧重测」覆盖（那才是长行程的真实形态）。
      final table = DayAnchorTable(dayCount: 3);
      final listKey = GlobalKey();
      final controller = ScrollController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: ListView(
              key: listKey,
              controller: controller,
              children: [
                for (var i = 0; i < 3; i++)
                  SizedBox(
                      key: table.keys[i], height: 120, child: Text('day$i')),
              ],
            ),
          ),
        ),
      ));

      final listBox = listKey.currentContext!.findRenderObject()! as RenderBox;
      table.measure(listBox, controller.position);

      expect(table.offsets.length, 3, reason: 'measure 后长度补齐到 dayCount');
      expect(table.offsets.every((o) => o != null), isTrue, reason: '测全则全部有偏移');
      expect(table.isDirty, isFalse, reason: '测全才置干净：这是被修过的那个 bug 的锁');
      expect(table.activeIndex(0), 0, reason: '测全后才允许按偏移判定');
      expect(table.offsetOf(0), isNotNull);
      controller.dispose();
    });

    testWidgets('E3. 生产等价：长列表交替挂载 → 重测补全偏移表 → 判定出靠后的天',
        (tester) async {
      // 这才是长行程的**真实形态**（探针实测：6 个 300px item / 400px 视口，
      // 任一时刻都是 3/6 挂载，滚动时前 3 与后 3 交替挂载/回收）：
      //   首帧   → day0-2 mounted，day3-5 NULL
      //   滚到底 → day0-2 NULL，day3-5 mounted
      //
      // ⛔ **别被 `measure()` 的实现骗了**：`measure()` 遇到 `ctx == null` 只 `continue`，
      //    **不清空**该槽位已有的旧值 ⇒ `offsets` 是**累积缓存**。
      //    所以「滚到底再测一次」会把 day3-5 补上，而 day0-2 保留首帧测到的旧值
      //    ⇒ 六天全部有偏移 ⇒ `isDirty` 转 false、`activeIndex` 开始正常判定。
      //    这正是 `_dirty` 机制的设计意图：未测全时保持脏、每帧继续测，直到测全。
      final table = DayAnchorTable(dayCount: 6);
      final listKey = GlobalKey();
      final controller = ScrollController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView(
              key: listKey,
              controller: controller,
              children: [
                for (var i = 0; i < 6; i++)
                  SizedBox(
                      key: table.keys[i], height: 300, child: Text('day$i')),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();

      final listBox = listKey.currentContext!.findRenderObject()! as RenderBox;

      // ① 首帧：只有前 3 天挂载 → 未测全 → 必须保持脏（否则没有重测路径，高亮永久卡 Day 1）
      table.measure(listBox, controller.position);
      expect(table.isDirty, isTrue,
          reason: '首帧只挂载前 3 天 → 未测全 → 必须保持脏');
      expect(table.offsets.whereType<double>().length, 3,
          reason: '首帧只测到 3 天，另外 3 天留 null');

      // ② 滚到底：后 3 天挂载、前 3 天被回收 → 重测后**累积补全**为 6 天
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      table.measure(listBox, controller.position);
      expect(table.offsets.whereType<double>().length, 6,
          reason: '重测补齐后 6 天都测到了（前 3 天沿用首帧旧值，后 3 天新测）');
      expect(table.isDirty, isFalse,
          reason: '六天全测到 → 此时才置干净，不再每帧重测');

      // ③ 关键：能判定出**靠后的天**（不是恒 0、也不是恒 Day 1）
      //
      // 手算：内容总高 6×300 = 1800，视口 400 ⇒ maxScrollExtent = 1400。
      // 滚到底时视口顶部对应内容坐标 1400；day5 的偏移是 5×300 = 1500 > 1400，
      // ⇒ 视口顶部**还没到**第 6 天的起点，落在 day4（偏移 1200 ≤ 1400）⇒ 下标 **4**。
      // （这不是 bug：最后一天只露出 100px 还没滚到它的起点，判定为第 5 天是正确的。）
      final tailIndex = table.activeIndex(controller.position.maxScrollExtent);
      expect(tailIndex, 4,
          reason: '滚到底时视口顶部对应 day4（1400 < day5 的 1500）→ 应判定为下标 4');
      expect(tailIndex, greaterThan(0),
          reason: '关键性质：不是恒 0、也不是恒 Day 1');
      controller.dispose();
    });

    testWidgets('E2. 真实 measure()：未测全 → isDirty 仍为 true，activeIndex 恒 0',
        (tester) async {
      // 用**懒构建**的 ListView.builder + 大 itemExtent + 小视口：
      // 首帧只构建视口内的 item，其余 `keys[i].currentContext == null`
      // → measure 里 `continue` → offsets 留下 null → 未测全。
      // 这正是真 bug 的触发场景：若 `_dirty` 被无条件置 false，
      // 后续就没有重测路径，高亮永久卡在 Day 1。
      final table = DayAnchorTable(dayCount: 5);
      final listKey = GlobalKey();
      final controller = ScrollController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ListView.builder(
              key: listKey,
              controller: controller,
              itemExtent: 1000,
              itemCount: 5,
              itemBuilder: (context, i) => SizedBox(
                  key: table.keys[i], height: 1000, child: Text('day$i')),
            ),
          ),
        ),
      ));

      final listBox = listKey.currentContext!.findRenderObject()! as RenderBox;
      table.measure(listBox, controller.position);

      expect(table.offsets.length, 5, reason: 'measure 后长度补齐到 dayCount');
      expect(
        table.offsets.any((o) => o == null),
        isTrue,
        reason: '懒构建下必然有分组头没挂上 → 存在未测量的 null',
      );
      expect(table.isDirty, isTrue, reason: '未测全必须保持脏，否则滚动联动彻底失灵');
      expect(
        table.activeIndex(0),
        0,
        reason: '未测全时守卫生效：恒 0，不抢高亮',
      );
      expect(
        table.targetFor(4),
        isNull,
        reason: '未挂载的那一天没有目标位置（offsetOf → null → targetFor → null）',
      );
      // 顺带钉住已测到的那一天：day0 在视口顶部，偏移 0 → 目标 max(0-4,0) = 0。
      expect(table.offsetOf(0), isNotNull);
      expect(table.targetFor(0), 0);
      controller.dispose();
    });

    test('E4. 部分测全（known 非空但未齐）→ activeIndex 恒 0，即使像素已越过已测天的起点',
        () {
      // ⛔ 这是 #16 独立复核指出的**必补项**：此前删掉 day_anchor_table.dart:81 的
      //    守卫 `if (known.length != dayCount) return 0;` 后，全量 41 例仍全绿
      //    （W2/W16 存活）—— 守卫没有任何"杀伤力"，等于裸奔。
      //
      // 杀伤逻辑（手算核对）：
      //   dayCount=3；measured 状态为 offsets=[0.0, 500.0, null]
      //   （day0/day1 已挂上、day2 还没挂上 —— 正是长行程首帧 measure() 的典型产物）。
      //   known = [0.0, 500.0]，长度 2 != dayCount(3) → 守卫生效。
      //   调用 activeIndex(600)：pixels=600, epsilon=4 → y=604。
      //     · 守卫生效（现状）：直接 return 0 —— 未测全绝不抢高亮。
      //     · 删掉守卫（变异）：activeIndexFor([0.0, 500.0], 604)
      //         = 0<=604 ✓(0)、500<=604 ✓(1) → 返回 **1**。
      //   ⇒ 期望 0 与变异后的 1 冲突 → 变异被打红 → 守卫确有杀伤力。
      //
      // 语义：day2 还没量到，若此时已根据 day0/day1 的偏移把高亮跳到第 2 天，
      //      就是"用残缺偏移抢高亮"的旧 bug。守卫正是拦这个。
      final table = DayAnchorTable(dayCount: 3);
      // 直接构造 measure() 在"部分挂载"时产出的 offsets 状态（不依赖真实 RenderBox：
      // 本用例只验证 activeIndex 的守卫契约，measure 本身由 E1/E2/E3 覆盖）。
      table.offsets
        ..clear()
        ..addAll(<double?>[0.0, 500.0, null]);
      expect(table.offsets.whereType<double>().length, 2,
          reason: '已知偏移 2 个，未测全（dayCount=3）');

      // 像素已越过 day1 起点（500），按已知偏移本该判定为第 2 天（下标 1）；
      // 但因未测全，守卫强制返回 0。
      expect(table.activeIndex(600), 0,
          reason: '未测全 → 不抢高亮，恒 0（守卫的杀伤点）');
      // 更极端：像素远超所有已知偏移，仍必须 0。
      expect(table.activeIndex(100000), 0,
          reason: '即使像素远超已知偏移，未测全也不得抢高亮');
      // 反方向：像素在 day0 起点之前（负），守卫同样压制为 0。
      expect(table.activeIndex(-100), 0,
          reason: '像素在已知偏移之前，未测全仍不得抢高亮');
    });
  });
}
