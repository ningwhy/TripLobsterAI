/// 创建行程「四步引导」的纯函数层。
///
/// 对齐定稿原型 `trip/ui-trip-create.html` 的 4 个 `.step-pane`
/// （:129 / :157 / :185 / :218）与 `.step-dots`（:119-124）。
///
/// 边界：**零 Flutter 依赖**（只依赖 Dart core，不 import material / widgets /
/// foundation），因此可以在纯 `flutter_test` 里逐条断言，不需要 pump 任何 Widget。
/// 所有函数都是「相同输入 → 相同输出」，不读时钟、不读随机数。
library;

/// 四步语义（0-based 索引与 [kWizardStepCount] 一一对应）。
///
/// - [basics]：行程名称 + 行程类型
/// - [dates]：起止日期
/// - [transport]：交通偏好 / 跨城同城选项 + 地点时间线
/// - [confirm]：确认摘要 + 生成行程
enum WizardStep { basics, dates, transport, confirm }

/// 步骤总数。刻意写成常量而非 `WizardStep.values.length`：
/// 后者不是编译期常量，无法用于 const 表达式与默认参数。
const int kWizardStepCount = 4;

/// 底部左按钮文案（原型 :309 `< 上一步`）。
const String kPrevLabel = '‹ 上一步';

/// 前 3 步底部右按钮文案（原型 :310 `下一步 >`）。
const String kNextLabel = '下一步 ›';

/// 最后一步底部右按钮文案（原型 :383 `生成行程 >`）。
const String kGenerateLabel = '生成行程 ›';

/// 前进一步；到末步后保持不变，越界一并夹到合法区间。
///
/// 手算边界：`total == 4` 时 `0→1→2→3→3`；`total <= 0` 时恒为 0。
int nextIndex(int current, int total) {
  if (total <= 0) return 0;
  final int next = current + 1;
  if (next < 0) return 0;
  if (next >= total) return total - 1;
  return next;
}

/// 回退一步；第 1 步（index 0）保持不变。
///
/// 无 `total` 参数（原型 :443 `showStep(step - 1)` 只做下界钳制），
/// 因此只钳制下界，不臆测上界。
int prevIndex(int current) => current <= 0 ? 0 : current - 1;

/// 起止日期是否合法：**只比年月日**，结束日不得早于开始日。
///
/// 为什么不用 `DateTime.isBefore` 直接比：`DateTime` 带时分秒，
/// 「同一天 23:59 开始、00:01 结束」在日历语义上仍是合法的单日行程。
/// 现有页面显示的是 `${date.month}/${date.day}`，这也是 `_isSameYmd` 的既有口径。
///
/// ⛔ 不新增任何臆测规则（不校验最早/最晚可选日期、不校验天数上限）——
///    原型与现有页面都没有这些约束，凭空加一条就是编造业务规则。
bool areValidTripDates(DateTime start, DateTime end) {
  final int startDay = start.year * 10000 + start.month * 100 + start.day;
  final int endDay = end.year * 10000 + end.month * 100 + end.day;
  return endDay >= startDay;
}

/// 能否从 [step] 前进一步。
///
/// 校验口径严格沿用现有 `_saveTrip()` / 日期选择器的真实约束，不新增臆测规则：
/// - 第 1 步 [basics]：名称非空（`_saveTrip` 的 `_nameController.text.isEmpty`）；
/// - 第 2 步 [dates]：日期合法且 `end >= start`（开始日期选择器既有纠正口径）；
/// - 第 3 步 [transport]：现有页面无其他必填项 → 恒 true；
/// - 最后一步没有「下一步」，恒 false（生成动作由 `_saveTrip()` 自己校验）。
bool canAdvance(
  int step,
  int total, {
  required String name,
  required DateTime startDate,
  required DateTime endDate,
}) {
  if (total <= 0 || step < 0 || step >= total - 1) return false;
  // 不用 `case WizardStep.xxx.index`：Dart 3.11 里 enum.index 不是常量表达式，
  // 不能用于 switch case（const_eval_property_access）。
  if (step == WizardStep.basics.index) return name.isNotEmpty;
  if (step == WizardStep.dates.index) {
    return areValidTripDates(startDate, endDate);
  }
  return true;
}

/// 底部右按钮文案：最后一步「生成行程 ›」，其余「下一步 ›」。
///
/// 对齐原型 :382-390：`step === TOTAL` 时换成主按钮文案并换成紫色实心样式。
String actionLabel(int step, int total) =>
    (total > 0 && step >= total - 1) ? kGenerateLabel : kNextLabel;
