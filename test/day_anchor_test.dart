import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/utils/day_anchor.dart';

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

    test('activeIndexFor 对同一个 y 多次调用结果稳定（幂等）', () {
      const offsets = [0.0, 500.0, 1000.0];
      for (final y in [-10.0, 0.0, 250.0, 500.0, 750.0, 1000.0, 3000.0]) {
        final first = DayAnchor.activeIndexFor(offsets, y);
        for (var i = 0; i < 5; i++) {
          expect(DayAnchor.activeIndexFor(offsets, y), first, reason: 'y=$y');
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
}
