import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/utils/wizard_step.dart';

/// 四步引导纯函数层回归测试。
///
/// 期望值全部按原型规格手算（4 个 `.step-pane`、:380 第 1 步禁用上一步、
/// :383 最后一步「生成行程 ›」），**不从实现里抄式子**；
/// 也不写「同输入结果稳定」这类恒真断言。
void main() {
  group('nextIndex', () {
    test('四步推进：0→1→2→3，末步保持 3', () {
      expect(nextIndex(0, 4), 1);
      expect(nextIndex(1, 4), 2);
      expect(nextIndex(2, 4), 3);
      expect(nextIndex(3, 4), 3);
    });

    test('越界夹到合法区间', () {
      expect(nextIndex(-1, 4), 0);
      expect(nextIndex(9, 4), 3);
      expect(nextIndex(0, 0), 0);
      expect(nextIndex(0, 1), 0);
      expect(nextIndex(0, 2), 1);
    });
  });

  group('prevIndex', () {
    test('四步回退：3→2→1→0，第 1 步保持 0', () {
      expect(prevIndex(3), 2);
      expect(prevIndex(2), 1);
      expect(prevIndex(1), 0);
      expect(prevIndex(0), 0);
      expect(prevIndex(-5), 0);
    });
  });

  group('actionLabel', () {
    test('前 3 步「下一步 ›」，第 4 步「生成行程 ›」', () {
      expect(actionLabel(0, 4), '下一步 ›');
      expect(actionLabel(1, 4), '下一步 ›');
      expect(actionLabel(2, 4), '下一步 ›');
      expect(actionLabel(3, 4), '生成行程 ›');
    });

    test('总步数变化时最后一步仍是「生成行程 ›」', () {
      expect(actionLabel(1, 2), '生成行程 ›');
      expect(actionLabel(0, 1), '生成行程 ›');
      expect(actionLabel(4, 4), '生成行程 ›');
      expect(actionLabel(0, 0), '下一步 ›');
    });
  });

  group('areValidTripDates', () {
    test('结束日早于开始日 → 非法', () {
      expect(areValidTripDates(DateTime(2026, 2, 23), DateTime(2026, 2, 21)),
          isFalse);
    });

    test('同日 / 晚于开始日 → 合法', () {
      expect(areValidTripDates(DateTime(2026, 2, 21), DateTime(2026, 2, 21)),
          isTrue);
      expect(areValidTripDates(DateTime(2026, 2, 21), DateTime(2026, 2, 23)),
          isTrue);
      expect(areValidTripDates(DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
          isTrue);
    });

    test('只比年月日：同日不同时刻不算非法', () {
      expect(
          areValidTripDates(DateTime(2026, 2, 21, 23, 59),
              DateTime(2026, 2, 21, 0, 1)),
          isTrue);
    });
  });

  group('canAdvance', () {
    final DateTime start = DateTime(2026, 2, 21);
    final DateTime end = DateTime(2026, 2, 23);

    test('第 1 步必填拦截：名称为空 false，非空 true', () {
      expect(
          canAdvance(0, 4, name: '', startDate: start, endDate: end), isFalse);
      expect(
          canAdvance(0, 4, name: '北京3日游', startDate: start, endDate: end),
          isTrue);
      // 口径沿用 _saveTrip 的 text.isEmpty：纯空格也算已填（不新增臆测规则）
      expect(
          canAdvance(0, 4, name: ' ', startDate: start, endDate: end), isTrue);
    });

    test('第 2 步日期拦截：结束日早于开始日 false', () {
      expect(
          canAdvance(1, 4,
              name: '北京3日游', startDate: end, endDate: start),
          isFalse);
      expect(
          canAdvance(1, 4,
              name: '北京3日游', startDate: start, endDate: start),
          isTrue);
      expect(
          canAdvance(1, 4, name: '北京3日游', startDate: start, endDate: end),
          isTrue);
    });

    test('第 3 步无额外必填项：恒 true（不新增臆测规则）', () {
      expect(canAdvance(2, 4, name: '', startDate: start, endDate: end),
          isTrue);
      expect(
          canAdvance(2, 4,
              name: '北京3日游', startDate: start, endDate: end),
          isTrue);
    });

    test('最后一步没有「下一步」：恒 false', () {
      expect(
          canAdvance(3, 4,
              name: '北京3日游', startDate: start, endDate: end),
          isFalse);
    });

    test('索引 / 总步数越界一律 false', () {
      expect(
          canAdvance(-1, 4, name: 't', startDate: start, endDate: end),
          isFalse);
      expect(canAdvance(4, 4, name: 't', startDate: start, endDate: end),
          isFalse);
      expect(canAdvance(0, 0, name: 't', startDate: start, endDate: end),
          isFalse);
      expect(canAdvance(0, 1, name: 't', startDate: start, endDate: end),
          isFalse);
    });
  });

  test('步数常量与枚举一致', () {
    expect(kWizardStepCount, 4);
    expect(WizardStep.values.length, kWizardStepCount);
    expect(WizardStep.basics.index, 0);
    expect(WizardStep.dates.index, 1);
    expect(WizardStep.transport.index, 2);
    expect(WizardStep.confirm.index, 3);
    expect(kPrevLabel, '‹ 上一步');
    expect(kNextLabel, '下一步 ›');
    expect(kGenerateLabel, '生成行程 ›');
  });
}
