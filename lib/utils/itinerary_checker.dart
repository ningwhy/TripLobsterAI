import '../models/trip_models.dart';

/// 行程可执行性校验（CH-01 … CH-09）：**纯函数领域层**。
///
/// ## 边界（硬约束）
/// 1. **零 `BuildContext`**：本文件不 import flutter，不接收 Provider / Repository / 当前时间；
/// 2. **相同输入必须得到相同输出**（不读 `DateTime.now()`、不读随机数）；
/// 3. **派生数据**：`ItinerarySlot / ItineraryIssue / DayCheckResult` 都不落库、不云同步，
///    每次 build 从 `TripDay` 当前值重算；
/// 4. **三铁律**：不估算、不编造、不兜底填充 —— 缺关键输入就**不触发**对应问题
///    （宁可少显示，不可显示错）。
///
/// ## 时间锚（设计 §1.1 难点 D）
/// 以**当日首站**的合法 `arrivalTime`（payload 原时刻）为锚，后续做**纯加法**：
/// ```text
/// arrival[0]   = parse(first.arrivalTime)
/// leave[i]     = arrival[i] + stayMinutes[i]
/// arrival[i+1] = leave[i]   + transportMinutes[i+1]
/// ```
/// ⛔ **不 `% 1440`**：服务端 `fmt()` 已经 mod 过（次日 00:30 会变成 00:30），
/// 客户端再 mod 一次会把「跨午夜」这个事实抹掉 —— 那是本次要检出的 CH-04。
/// 展示时才由 [formatClockMinutes] 决定要不要显示「次日」。
///
/// ⛔ **没有锚就不推算 9:00 起点**：9:00 是编造的起点，违反三铁律。
/// 首站无 `arrivalTime` → 整条时间链 `arrival/leave` 全 null、`timeReliable=false`，
/// 所有依赖时刻的规则（CH-01/02/06/07/08）自动跳过，只留 CH-09 日级披露。

// ---------------------------------------------------------------------------
// 阈值常量
//
// ⚠️ CH-02(15 分钟) / CH-05(景点 15、餐厅 30) / CH-07(10 分钟) / CH-08(12 小时)
//    全部是**产品判断阈值，不是实测结论**。改名、改值都不影响正确性，
//    但代码注释、测试名与文档**不得**把它们包装成行业事实或调研结论。
// ---------------------------------------------------------------------------

/// 一天的总分钟数（跨午夜判据的基准）
const int kMinutesPerDay = 1440;

/// CH-01 提醒阈值：到达距打烊不足该分钟数 → 提醒（产品判断）
const int kCh01ShortVisitMinutes = 30;

/// CH-02 阈值：到达早于开门达到该分钟数 → 提醒（产品判断）
const int kCh02EarlyArrivalMinutes = 15;

/// CH-05 景点停留下限（产品判断）
const int kCh05AttractionMinStay = 15;

/// CH-05 餐厅停留下限（产品判断）
const int kCh05RestaurantMinStay = 30;

/// CH-07 缓冲下限：转场后剩余缓冲少于该分钟数 → 提醒（产品判断）
const int kCh07BufferMinutes = 10;

/// CH-08 日总时长上限：非住宿活动跨度超过该分钟数 → 提醒（产品判断，12 小时）
const int kCh08LongDayMinutes = 720;

/// 问题级别：**只有 blocking 描红边**；reminder 灰底橙字不描边；neutral 只进日级。
enum IssueSeverity { blocking, reminder, neutral }

extension IssueSeverityOrder on IssueSeverity {
  /// 排序用秩：数字越小优先级越高（blocking 最高）。
  ///
  /// 不复用 `enum.index`：声明顺序是偶然的，改声明顺序会静默改变去重结果。
  int get rank => switch (this) {
        IssueSeverity.blocking => 0,
        IssueSeverity.reminder => 1,
        IssueSeverity.neutral => 2,
      };
}

/// 校验规则编号（与设计 §1.3.2 一一对应）
enum ItineraryIssueCode {
  /// CH-01 到达晚于停止入场 / 打烊
  ch01LateEntry,

  /// CH-01 到达距打烊过近
  ch01ShortVisit,

  /// CH-02 早到
  ch02EarlyArrival,

  /// CH-03 当日闭馆
  ch03ClosedDate,

  /// CH-04 排过午夜
  ch04OverMidnight,

  /// CH-05 停留时长非法
  ch05InvalidStay,

  /// CH-05 停留过短
  ch05ShortStay,

  /// CH-06 转场排不下
  ch06InsufficientTransfer,

  /// CH-07 缓冲不足（P1）
  ch07TightBuffer,

  /// CH-08 日总时长过长（P1）
  ch08LongDay,

  /// CH-09 营业时间未校验（**日级**，不进卡片）
  ch09OpenHoursUnknown,
}

extension ItineraryIssueCodeOrder on ItineraryIssueCode {
  /// 同级（同 severity）时的固定优先级，数字越小越优先。
  ///
  /// 顺序来自设计 §1.3.4：`CH-03 > CH-01 > CH-04 > CH-06 > CH-05 > CH-02 > CH-07 > CH-08`。
  /// 先比 severity、再比本值 —— **不依赖列表偶然顺序**（`issues` 的生成顺序是实现的偶然）。
  int get priority => switch (this) {
        ItineraryIssueCode.ch03ClosedDate => 0,
        ItineraryIssueCode.ch01LateEntry => 1,
        ItineraryIssueCode.ch01ShortVisit => 1,
        ItineraryIssueCode.ch04OverMidnight => 2,
        ItineraryIssueCode.ch06InsufficientTransfer => 3,
        ItineraryIssueCode.ch05InvalidStay => 4,
        ItineraryIssueCode.ch05ShortStay => 4,
        ItineraryIssueCode.ch02EarlyArrival => 5,
        ItineraryIssueCode.ch07TightBuffer => 6,
        ItineraryIssueCode.ch08LongDay => 7,
        ItineraryIssueCode.ch09OpenHoursUnknown => 8,
      };

  /// 稳定编号文本（测试比对用，与枚举名解耦）
  String get label => switch (this) {
        ItineraryIssueCode.ch01LateEntry => 'CH-01',
        ItineraryIssueCode.ch01ShortVisit => 'CH-01',
        ItineraryIssueCode.ch02EarlyArrival => 'CH-02',
        ItineraryIssueCode.ch03ClosedDate => 'CH-03',
        ItineraryIssueCode.ch04OverMidnight => 'CH-04',
        ItineraryIssueCode.ch05InvalidStay => 'CH-05',
        ItineraryIssueCode.ch05ShortStay => 'CH-05',
        ItineraryIssueCode.ch06InsufficientTransfer => 'CH-06',
        ItineraryIssueCode.ch07TightBuffer => 'CH-07',
        ItineraryIssueCode.ch08LongDay => 'CH-08',
        ItineraryIssueCode.ch09OpenHoursUnknown => 'CH-09',
      };
}

/// 单条校验问题（运行时派生，**不落库**）
class ItineraryIssue {
  final ItineraryIssueCode code;
  final IssueSeverity severity;

  /// 所属天序号（1 起）
  final int dayNumber;

  /// 归责地点 id；**CH-09 恒为 null**（日级问题不归责到卡片）
  final String? locationId;

  /// 主句：**必须包含可核对的时刻/分钟**；交通类以「按行程安排」开头。
  /// 禁止「可能有问题」「大约」「一般」这类不可核对表述。
  final String message;

  /// 证据原文（**仅营业时间类问题携带**），原样切片、不得改写、不得由结构化值反拼。
  final String? sourceRaw;

  const ItineraryIssue({
    required this.code,
    required this.severity,
    required this.dayNumber,
    required this.message,
    this.locationId,
    this.sourceRaw,
  });

  /// 稳定去重/排序键（设计 §3.3）。
  ///
  /// 用 getter 而非字段：值完全由 `code` 推出，存字段就可能与 code 不一致。
  int get priority => code.priority;
}

/// 一个地点在当日时刻链上的重建结果（**不落库**）
class ItinerarySlot {
  final Location location;

  /// payload 原计划到达时刻（0..1440）；null = 服务端没给或不可解析
  final int? sourceArrival;

  /// payload 原计划离开时刻（0..1440）；null 同上
  final int? sourceLeave;

  /// 从首站锚**纯加法**重建的到达时刻，**不 mod 1440**（可能是 1500 表示次日 01:00）
  final int? arrival;

  /// 重建的离开时刻，同样不 mod 1440
  final int? leave;

  /// 到达本站所需交通分钟数；null = 缺失或 <= 0
  final int? travelMinutes;

  /// 时刻是否可靠：**到该站前所有必要 stay/transport 均存在**且首站有锚。
  ///
  /// false → CH-01/02/06/07 一律跳过（不使用不可靠时刻做判断）。
  final bool timeReliable;

  /// payload 自身已发生绕回：`sourceLeave < sourceArrival`（跨午夜的直接证据）。
  ///
  /// 保留 raw 值是因为服务端 `fmt()` 已 mod 1440，绕回信息**只**存在于这个比较里。
  final bool sourceWrapped;

  const ItinerarySlot({
    required this.location,
    required this.timeReliable,
    required this.sourceWrapped,
    this.sourceArrival,
    this.sourceLeave,
    this.arrival,
    this.leave,
    this.travelMinutes,
  });
}

/// 当日校验结果（**不落库**）
class DayCheckResult {
  final List<ItinerarySlot> slots;

  /// 全量问题（含被去重掉的次级问题，保留给测试与后续 P1 展开）
  final List<ItineraryIssue> issues;

  /// 每个地点**最多一条**主问题（CH-09 不在其中，它 `locationId == null`）
  final Map<String, ItineraryIssue> primaryIssueByLocation;

  /// 阻塞级数量（按**实际展示**口径统计：已去重 + 日级问题）
  final int blockingCount;

  /// 提醒级数量（同上口径）
  final int reminderCount;

  /// 当日「营业结构未知」的景点数（CH-09 的计数）
  final int uncheckedAttractionCount;

  const DayCheckResult({
    required this.slots,
    required this.issues,
    required this.primaryIssueByLocation,
    required this.blockingCount,
    required this.reminderCount,
    required this.uncheckedAttractionCount,
  });

  /// 实际会展示出来的问题列表：每个地点一条 + 日级问题。
  ///
  /// 与 `blockingCount/reminderCount` 严格同一口径，避免出现
  /// 「摘要说 3 条、列表只有 2 条」这类数字对不上的情况。
  List<ItineraryIssue> get displayIssues => [
        ...primaryIssueByLocation.values,
        ...issues.where((i) => i.locationId == null),
      ];

  bool get hasBlocking => blockingCount > 0;

  bool get hasAnyIssue => displayIssues.isNotEmpty;
}

// ---------------------------------------------------------------------------
// 纯函数入口
// ---------------------------------------------------------------------------

/// `HH:mm` → 从 0:00 起的分钟数；无法解析返回 null。
///
/// 严格性说明（都是真实脏数据形态）：
/// - `"24:00"` → 1440 **合法**：服务端对 24 小时营业产出 `00:00-24:00`；
///   但 `"24:30"` → null（24 只能作打烊整点）；
/// - `"9:5"` → 545（不要求两位补零，高德原文常见 `9:00`）；
/// - `"09:00-17:00"` → null（**不是**时刻，调用方不该把它传进来）。
int? parseClockMinutes(String? hhmm) {
  if (hhmm == null) return null;
  final text = hhmm.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null) return null;
  if (m < 0 || m > 59) return null;
  if (h == 24) return m == 0 ? kMinutesPerDay : null;
  if (h < 0 || h > 23) return null;
  return h * 60 + m;
}

/// 分钟数 → 展示文本：**跨天时显示「次日 HH:mm」**。
///
/// 这里是唯一允许表达「次日」的地方 —— 内部比较一律用未 mod 的整数分钟。
/// ⛔ 不要把它改成 `% 1440` 后显示：那会把 1500 分钟（次日 01:00）显示成 01:00，
///    用户会以为当天凌晨 1 点就结束了。
String formatClockMinutes(int minutes) {
  final days = minutes ~/ kMinutesPerDay;
  final within = minutes - days * kMinutesPerDay;
  final hh = (within ~/ 60).toString().padLeft(2, '0');
  final mm = (within % 60).toString().padLeft(2, '0');
  return days >= 1 ? '次日 $hh:$mm' : '$hh:$mm';
}

/// 分钟数 → 时长文本（"1小时30分" / "30分钟"）
String formatDurationMinutes(int minutes) {
  final abs = minutes.abs();
  final h = abs ~/ 60;
  final m = abs % 60;
  if (h == 0) return '$m分钟';
  return m == 0 ? '$h小时' : '$h小时$m分';
}

/// 营业结构是否「已校验」（设计 §1.3.3，CH-09 的唯一判据）。
///
/// 满足其一才算已校验：
/// 1. `closedOnDate == true` 且 `openHoursRaw` 非空（明确闭馆是**成功解析**）；
/// 2. `closedOnDate == false` 且 `openTime/closeTime/openHoursRaw` 均合法非空
///    （`lastEntryTime` 可空）。
///
/// ⛔ 「部分字段存在」不算已校验 —— 只给个 `openTime` 无法支撑任何打烊判断。
/// ⛔ `closedOnDate == null`（未知）**一定返回 false**：未知就是未校验，
///    这正是三态语义存在的意义（null ≠ false）。
bool isOpenHoursVerified(Location loc) {
  // 【T04 红线 / T05 收窄】除外型闭馆条款**在节假日失效**（`holiday_excluded_close`）：
  // 当服务端在该态下**没有**给出开放结论（`closedOnDate != false`）时，
  // 那条 `closedOnDate=true` 在节假日不可信 → **不算已校验**。
  //
  // 不这么做会"两头落空"：CH-03 因红线被抑制、又因为"已校验"不进 CH-09，
  // 用户什么提示都看不到 —— 等于把"不确定"渲染成"没问题"。
  //
  // ⚠️ 判据必须带 `closedOnDate != false`（T05 修正）：
  //    `holiday_excluded_close` **与具体时段可以并存** ——
  //    `finalHolidayStatus()` 优先返回该态，只要原文同时含「除外型闭馆」与
  //    「节假日 09:00-17:00」这类排班（实测：src 含两句、日期 2026-05-04 →
  //    reason=ok, openTime=09:00, holidayStatus='holiday_excluded_close'）。
  //    此时服务端**确实**给出了可核对时段，若一律判"未校验"就会：
  //      ① 卡片显示 09:00-17:00、日级却说"未取到营业时间"（旧措辞，T05 已废弃；
  //         现措辞为"该日营业时间无原文依据…"，自相矛盾的问题是同一类）；
  //      ② CH-01/02 被静默跳过（有数据却不校验 = 假阴性）。
  if (loc.holidayStatus == HolidayStatus.holidayExcludedClose &&
      loc.closedOnDate != false) {
    return false;
  }
  final raw = loc.openHoursRaw;
  if (raw == null || raw.trim().isEmpty) return false;
  if (loc.closedOnDate == true) return true;
  if (loc.closedOnDate != false) return false;
  final open = parseClockMinutes(loc.openTime);
  final close = parseClockMinutes(loc.closeTime);
  if (open == null || close == null) return false;
  // 一致性兜底：open < close 才可信（服务端解析时已校验，客户端不信任跨进程数据）
  return open < close;
}

/// 营业时间提示的三种情形（T04，设计 §0.5）。
///
/// 判据来自服务端 `toLocation()` 下发的 `holidayStatus` + 时段字段；
/// 文案三选一，**不混合**：同一个地点只会命中其中一种。
enum OpenHoursHintKind {
  /// ① 已解析出具体时段（含多时段）：正常展示时段；`holidayName` 有值时附在前面。
  specific,

  /// ② 当天是法定节假日，但**没有**可用时段：
  ///    除外型闭馆条款在节假日失效（服务端 reason `holiday_excluded_open`），
  ///    或只有「节假日正常开放」的明示却无时段（`holiday_open_no_hours`）。
  ///
  /// ⛔ 本态**禁止**显示「已闭馆 / 不开放」，也**禁止**编造时段。
  holidayNoHours,

  /// ③ 无可用时段、且客户端拿不到任何"官方通知 / 日历不可得"的专属信号。
  ///
  /// 【为什么 ③ 只能是"兜底兜不住"的合并态】
  /// 服务端 `reason`（`official_notice` / `holiday_needs_calendar` / `no_matching_clause`）
  /// 是**诊断字段，不进 payload** —— 已核对 `planner.js:1528-1585` 的 `toLocation()`，
  /// 它逐个显式列出下发的键，其中**没有** `reason`；五类"无时段"原因在客户端
  /// 落到完全相同的字段组合（时刻全 null、`closedOnDate` null、`openSegments` `[]`）。
  /// 故 ③ 与「老行程 / 未解析」在客户端**不可区分**，只能合并披露。
  officialNotice,
}

/// 某地点营业时间的展示用结论（**派生数据，不落库**）。
class OpenHoursHint {
  final OpenHoursHintKind kind;

  /// 展示文案（三选一，调用方直接渲染，不要再二次加工）
  final String text;

  /// 节日名（① ② 可能有值；③ 恒 null）
  final String? holidayName;

  const OpenHoursHint({
    required this.kind,
    required this.text,
    this.holidayName,
  });
}

/// 可用时段文本：`HH:mm-HH:mm`；多时段用「、」连接；无可用时段 → null。
///
/// 取数顺序与既有 UI 一致（`location_card._metaText`）：先看 `openTime/closeTime`
/// （单时段的既有形态），再看 `openSegments`（多时段时前两者恒 null）。
/// ⛔ 半个时段（只有 open 没有 close）**不算**可用时段：返回 null 由调用方降级。
String? openHoursSegmentsText(Location loc) {
  final open = loc.openTime;
  final close = loc.closeTime;
  if (open != null && close != null && open.isNotEmpty && close.isNotEmpty) {
    return '$open-$close';
  }
  final segments = loc.openSegments;
  if (segments == null || segments.isEmpty) return null;
  final parts = segments
      .where((s) => s.open.isNotEmpty && s.close.isNotEmpty)
      .map((s) => '${s.open}-${s.close}')
      .toList();
  if (parts.isEmpty) return null;
  return parts.join('、');
}

/// 营业时间提示（T04 三类文案的唯一入口，纯函数）。
///
/// | 情形 | 判据 | 文案 |
/// |---|---|---|
/// | ① 有具体时段 | `openHoursSegmentsText != null` | `劳动节 09:00-17:00` |
/// | ② 节假日无时段 | `holidayStatus` 为 `'holiday_excluded_close'` 或 `'holiday'` | `逢劳动节，开放时间可能与常规不同，请以官方公告为准` |
/// | ③ 其余 | 无时段且无节假日结论 | `该日营业时间无原文依据，请以官方公告为准` |
///
/// ⛔ ② 与「闭馆」是互斥的：`holiday_excluded_close` 的含义恰恰是
///    「除外型闭馆条款**在节假日失效**」，此时说闭馆 = 阻塞级假阳性。
///    本函数在任何分支都**不产出**"闭馆 / 不开放"字样。
OpenHoursHint openHoursHintOf(Location loc) {
  final segments = openHoursSegmentsText(loc);
  final holidayName = _nonEmpty(loc.holidayName);

  // ① 有具体时段 → 正常展示（节假日只是前缀，不改变时段本身）
  if (segments != null) {
    return OpenHoursHint(
      kind: OpenHoursHintKind.specific,
      text: holidayName == null ? segments : '$holidayName $segments',
      holidayName: holidayName,
    );
  }

  // ② 逢法定节假日但无时段：'holiday_excluded_close'（除外型失效）或
  //    'holiday'（有"正常开放"明示却没解析出时段，服务端 reason holiday_open_no_hours）。
  //    两者都**没有**依据给出时段，也**没有**依据判闭馆。
  final status = loc.holidayStatus;
  final isHolidayNoHours =
      status == HolidayStatus.holidayExcludedClose || status == HolidayStatus.holiday;
  if (isHolidayNoHours) {
    final prefix = holidayName == null ? '逢法定节假日' : '逢$holidayName';
    return OpenHoursHint(
      kind: OpenHoursHintKind.holidayNoHours,
      text: '$prefix，开放时间可能与常规不同，请以官方公告为准',
      holidayName: holidayName,
    );
  }

  // ③ 其余（含 `holidayStatus` 为 null / 'none'，以及客户端不可分辨的
  //    official_notice / holiday_needs_calendar / no_matching_clause ——
  //    reason 不进 payload，见本枚举注释）
  //
  // 措辞口径（T05，QA 提的 UX 风险）：这是"原文**没有依据**给出时段"的诚实返回，
  // **不是**"数据没抓到" → 不写"暂无/未取到营业时间"这类像故障的措辞
  // （这两句是**旧措辞、T05 已废弃**，此处只作反面示例，勿照抄回代码），
  // 也不写任何时刻、不说闭馆。
  return const OpenHoursHint(
    kind: OpenHoursHintKind.officialNotice,
    text: '该日营业时间无原文依据，请以官方公告为准',
  );
}

/// 去空白后的非空串；null / 空串 / 纯空白 → null。
String? _nonEmpty(String? v) {
  if (v == null) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// 从首站 `arrivalTime` 锚重建当日时刻链（纯函数、不做任何网络/时间读取）。
///
/// 缺失处理：`stayMinutes/transportMinutes` 缺失按 **0** 累加，仅用于给出
/// **「最低已知日终」**（设计明定，服务 CH-04），**不是**估算到达时刻 ——
/// 其他规则靠 `timeReliable=false` 自动跳过。
List<ItinerarySlot> rebuildItinerarySlots(TripDay day) {
  final locations = day.locations;
  if (locations.isEmpty) return const <ItinerarySlot>[];

  final anchor = parseClockMinutes(locations.first.arrivalTime);
  final hasAnchor = anchor != null;
  var clock = anchor ?? 0;
  var chainReliable = hasAnchor;

  final slots = <ItinerarySlot>[];
  for (var i = 0; i < locations.length; i++) {
    final loc = locations[i];
    final travel = _travelMinutesOf(loc);

    if (i > 0) {
      // 到达本站 = 前站离开 + 到本站的交通。交通缺失 → 到达时刻不可靠（按 0 继续累计）
      if (travel == null) chainReliable = false;
      clock += travel ?? 0;
    }

    final arrival = chainReliable ? clock : null;
    final stay = loc.stayMinutes;
    final leave = (arrival != null && stay != null) ? arrival + stay : null;

    final sourceArrival = parseClockMinutes(loc.arrivalTime);
    final sourceLeave = parseClockMinutes(loc.leaveTime);

    slots.add(
      ItinerarySlot(
        location: loc,
        sourceArrival: sourceArrival,
        sourceLeave: sourceLeave,
        arrival: arrival,
        leave: leave,
        travelMinutes: travel,
        timeReliable: arrival != null,
        sourceWrapped:
            sourceArrival != null && sourceLeave != null && sourceLeave < sourceArrival,
      ),
    );

    // 下一站的到达依赖本站 stay 已知；缺失则整条后续链不可靠
    if (stay == null) chainReliable = false;
    clock += stay ?? 0;
  }
  return slots;
}

/// 当日完整校验：一次调用产出 slots + 全量 issues + 每地点主问题 + 计数。
///
/// 页面应**每天只调一次**并把结果传给卡片，避免 build 内重复 O(n²)。
DayCheckResult checkItineraryDay(TripDay day) {
  final slots = rebuildItinerarySlots(day);
  final issues = <ItineraryIssue>[];

  // ---------------- 逐站规则 ----------------
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    final loc = slot.location;

    // CH-03 闭馆日：必须有原文片段（无证据不展示结构化结论）
    final raw = loc.openHoursRaw;
    // 【T04 红线】`holiday_excluded_close` = 「周一闭馆（法定节假日除外）」这类
    // **除外型闭馆条款在节假日失效**：原文没有"节假日正常开放"的明示，
    // 服务端既给不出时段，也不该由它得出"闭馆"。此时说闭馆就是**阻塞级假阳性**
    // （用户会在节假日被错误告知博物馆关门）。
    //
    // 宁可少显示，不可显示错：本态一律**不产出** CH-03，改由 CH-09 的 ② 类文案披露。
    // ⚠️ 这是**防御性保险，不是在补一个活 bug**（主理人 2026 全年穷举实测：
    //    9 个真实 POI × 365 天 = 3285 次解析，`holidayStatus='holiday_excluded_close'`
    //    与 `closedOnThisDate=true` **并置 0 例** —— 当前实现下不可达）。
    //    不可达的原因只是 `planner.js` `entries.length === 0` 分支的**判序**：
    //    先 `if (excludedCloseTriggered)` 返回 `closed=false`，只有它为 false 才可能
    //    走到 `excludedByClose` 那条 `closed=true`，而那时 `finalHolidayStatus()`
    //    不会返回 `holiday_excluded_close`。
    //
    //    判序这么脆、语义又这么微妙：一旦有人调整那个分支的顺序，这个组合会
    //    **立刻**变成阻塞级假阳性。故客户端显式拦截，**不要按"当前不可达"把它优化掉**。
    //    同理，[isOpenHoursVerified] 在本态下也必须返回 false（否则两头落空）。
    final closedSuppressed =
        loc.holidayStatus == HolidayStatus.holidayExcludedClose;
    if (!closedSuppressed &&
        loc.closedOnDate == true &&
        raw != null &&
        raw.trim().isNotEmpty) {
      issues.add(
        ItineraryIssue(
          code: ItineraryIssueCode.ch03ClosedDate,
          severity: IssueSeverity.blocking,
          dayNumber: day.dayNumber,
          locationId: loc.id,
          message: '当日明确闭馆，该日不开放',
          sourceRaw: raw,
        ),
      );
    }

    // CH-01 / CH-02：需要「已校验的营业结构」+「可靠到达时刻」
    final arrival = slot.arrival;
    final canCheckHours =
        slot.timeReliable && loc.closedOnDate == false && isOpenHoursVerified(loc);
    if (canCheckHours && arrival != null) {
      final close = parseClockMinutes(loc.closeTime);
      final lastEntry = parseClockMinutes(loc.lastEntryTime);
      final open = parseClockMinutes(loc.openTime);

      if (close != null) {
        if (lastEntry != null) {
          // 有停止入场时刻：只判「晚于停止入场」
          if (arrival > lastEntry) {
            issues.add(
              ItineraryIssue(
                code: ItineraryIssueCode.ch01LateEntry,
                severity: IssueSeverity.blocking,
                dayNumber: day.dayNumber,
                locationId: loc.id,
                message:
                    '${formatClockMinutes(arrival)} 到达晚于停止入场 ${formatClockMinutes(lastEntry)}，无法入园',
                sourceRaw: raw,
              ),
            );
          }
        } else if (arrival >= close) {
          issues.add(
            ItineraryIssue(
              code: ItineraryIssueCode.ch01LateEntry,
              severity: IssueSeverity.blocking,
              dayNumber: day.dayNumber,
              locationId: loc.id,
              message:
                  '${formatClockMinutes(arrival)} 到达已过打烊 ${formatClockMinutes(close)}，无法游览',
              sourceRaw: raw,
            ),
          );
        } else if (close - arrival < kCh01ShortVisitMinutes) {
          issues.add(
            ItineraryIssue(
              code: ItineraryIssueCode.ch01ShortVisit,
              severity: IssueSeverity.reminder,
              dayNumber: day.dayNumber,
              locationId: loc.id,
                // 同时给出「剩余分钟」与两个时刻：任一项都可由用户自行核对
                message:
                    '${formatClockMinutes(arrival)} 到达距 ${formatClockMinutes(close)} 打烊仅剩 ${close - arrival} 分钟',
              sourceRaw: raw,
            ),
          );
        }
      }

      // CH-02 早到
      if (open != null && open - arrival >= kCh02EarlyArrivalMinutes) {
        issues.add(
          ItineraryIssue(
            code: ItineraryIssueCode.ch02EarlyArrival,
            severity: IssueSeverity.reminder,
            dayNumber: day.dayNumber,
            locationId: loc.id,
            message:
                '${formatClockMinutes(arrival)} 到达早于 ${formatClockMinutes(open)} 开门，需等 ${open - arrival} 分钟',
            sourceRaw: raw,
          ),
        );
      }
    }

    // CH-05 停留异常（P1，阈值为产品判断）
    final stay = loc.stayMinutes;
    if (stay != null) {
      if (stay <= 0) {
        issues.add(
          ItineraryIssue(
            code: ItineraryIssueCode.ch05InvalidStay,
            severity: IssueSeverity.blocking,
            dayNumber: day.dayNumber,
            locationId: loc.id,
            message: '停留时长 $stay 分钟无效，需大于 0',
          ),
        );
      } else {
        final minStay = switch (loc.type) {
          LocationType.attraction => kCh05AttractionMinStay,
          LocationType.restaurant => kCh05RestaurantMinStay,
          _ => null,
        };
        if (minStay != null && stay < minStay) {
          issues.add(
            ItineraryIssue(
              code: ItineraryIssueCode.ch05ShortStay,
              severity: IssueSeverity.reminder,
              dayNumber: day.dayNumber,
              locationId: loc.id,
              message: '${_typeLabel(loc.type)}停留 $stay 分钟，短于建议下限 $minStay 分钟',
            ),
          );
        }
      }
    }

    // CH-04 规则 a：payload 自身绕回（**酒店豁免**，见 _isOvernightBoundary）
    if (!_isOvernightBoundary(loc) && slot.sourceWrapped) {
      final srcArrival = slot.sourceArrival!;
      final srcLeave = slot.sourceLeave!;
      issues.add(
        ItineraryIssue(
          code: ItineraryIssueCode.ch04OverMidnight,
          severity: IssueSeverity.blocking,
          dayNumber: day.dayNumber,
          locationId: loc.id,
          message:
              '${formatClockMinutes(srcArrival)} 到达、${formatClockMinutes(srcLeave + kMinutesPerDay)} 离开，已跨午夜',
        ),
      );
    }
  }

  // ---------------- CH-04 规则 b：最低已知累计日终 > 1440 ----------------
  final dayEnd = _dayEnd(slots);
  if (dayEnd != null && dayEnd.endMinutes > kMinutesPerDay) {
    final responsible = dayEnd.slot;
    // 规则 a 已给该地点产出过 CH-04 就不再重复（否则同地点两条 CH-04，去重也只能留一条）
    final alreadyFlagged = issues.any((i) =>
        i.locationId == responsible.location.id &&
        i.code == ItineraryIssueCode.ch04OverMidnight);
    if (!alreadyFlagged) {
      issues.add(
        ItineraryIssue(
          code: ItineraryIssueCode.ch04OverMidnight,
          severity: IssueSeverity.blocking,
          dayNumber: day.dayNumber,
          locationId: responsible.location.id,
          message: '当日安排排到${formatClockMinutes(dayEnd.endMinutes)}，已跨午夜',
        ),
      );
    }
  }

  // ---------------- CH-06 / CH-07：转场 ----------------
  //
  // ⚠️ 两处都必须处理，否则真实 payload 上会变成**假阳性工厂**
  // （2026-10 用真实 generate 产物验证过，见 test/itinerary_checker_test.dart
  //   「CH-06/07 服务端零缓冲不误报」与「跨午夜绕回不误报」两例）：
  //
  // ① `sourceArrival` 必须**先按锚单调展开**再比。
  //    服务端 `fmt()` 做了 `% 1440`（planner.js:642），排过午夜的站会被绕回成
  //    次日凌晨（真实产物里酒店 `arr=00:58` 实际是 24:58）。
  //    直接拿绕回值比，会得到「00:58 到达早于前站 17:38 离开 1000 分钟」
  //    这种 nonsense，并升级成**阻塞级假阳性**。
  //
  // ② 必须跳过 `gap == travel` 的**规划器零缓冲**态。
  //    服务端 `pushLoc` 就是按 `arrival[i+1] = leave[i] + travel[i+1]` 累加的
  //    （planner.js:1292-1309），未编辑时两者恒等：
  //      · CH-06 的 `gap < travel` 永不成立（死逻辑）；
  //      · CH-07 的 `gap - travel < 10` **恒成立** → 每条相邻站都亮一遍。
  //    「零缓冲」是规划的常态而不是异常，把它渲染成提醒就是假阳性。
  //    只有二者分离时（插餐留下的空档、砍站留下的空洞、用户改过停留）才评估。
  final sourceArrivals = _unwrapSourceArrivals(slots);
  for (var i = 1; i < slots.length; i++) {
    final next = slots[i];
    final prev = slots[i - 1];
    final srcArrival = sourceArrivals[i];
    final prevLeave = prev.leave;
    final travel = next.travelMinutes;
    // 任一缺失跳过：没有 payload 原计划到达、没有前站可靠离开、没有交通耗时 → 不判断
    if (srcArrival == null || prevLeave == null || travel == null) continue;

    final gap = srcArrival - prevLeave;
    if (gap == travel) continue; // ② 规划器精确排满：既不是排不下，也不是缓冲不足
    if (gap < travel) {
      issues.add(
        ItineraryIssue(
          code: ItineraryIssueCode.ch06InsufficientTransfer,
          severity: IssueSeverity.blocking,
          dayNumber: day.dayNumber,
          locationId: next.location.id,
          message: gap >= 0
              ? '按行程安排只留 $gap 分钟转场，交通需要 $travel 分钟'
              : '按行程安排 ${formatClockMinutes(srcArrival)} 到达早于前站 ${formatClockMinutes(prevLeave)} 离开 ${-gap} 分钟，交通还需要 $travel 分钟',
        ),
      );
    } else if (gap - travel < kCh07BufferMinutes) {
      // CH-07 只在 CH-06 未触发时评估；缓冲下限 10 分钟是**产品判断**
      issues.add(
        ItineraryIssue(
          code: ItineraryIssueCode.ch07TightBuffer,
          severity: IssueSeverity.reminder,
          dayNumber: day.dayNumber,
          locationId: next.location.id,
          message:
              '按行程安排转场需 $travel 分钟，仅剩 ${gap - travel} 分钟缓冲',
        ),
      );
    }
  }

  // ---------------- CH-08：日总时长 ----------------
  if (slots.isNotEmpty && dayEnd != null) {
    final anchor = slots.first.arrival;
    final responsible = dayEnd.slot;
    if (anchor != null &&
        !_isOvernightBoundary(responsible.location) &&
        responsible.timeReliable) {
      final span = dayEnd.endMinutes - anchor;
      if (span > kCh08LongDayMinutes) {
        issues.add(
          ItineraryIssue(
            code: ItineraryIssueCode.ch08LongDay,
            severity: IssueSeverity.reminder,
            dayNumber: day.dayNumber,
            locationId: responsible.location.id,
            message:
                '当日活动从 ${formatClockMinutes(anchor)} 到 ${formatClockMinutes(dayEnd.endMinutes)}，跨度 ${formatDurationMinutes(span)}',
          ),
        );
      }
    }
  }

  // ---------------- CH-09：营业时间未校验（日级，T04 三类文案）----------------
  //
  // 三档判据见 [openHoursHintOf]：①有具体时段（不计入）②节假日无时段 ③其余。
  // ②③ 都**不归责到卡片**（日级问题），与既有设计一致。
  var unchecked = 0;
  var holidayNoHours = 0;
  String? holidayLabel;
  for (final loc in day.locations) {
    if (loc.type != LocationType.attraction || isOpenHoursVerified(loc)) continue;
    unchecked++;
    final hint = openHoursHintOf(loc);
    if (hint.kind == OpenHoursHintKind.holidayNoHours) {
      holidayNoHours++;
      // 多个景点跨不同节日名时只取第一个，避免把两个节日名拼成一句谣言
      holidayLabel ??= hint.holidayName;
    }
  }

  // ② 逢法定节假日但无具体时段 → **提醒**级（不确定，但比"完全没数据"更值得提示），
  //    绝不升级为阻塞：我们没有依据说它闭馆，也没有依据说它几点开。
  if (holidayNoHours > 0) {
    final prefix = holidayLabel == null ? '逢法定节假日' : '逢$holidayLabel';
    issues.add(
      ItineraryIssue(
        code: ItineraryIssueCode.ch09OpenHoursUnknown,
        severity: IssueSeverity.reminder,
        dayNumber: day.dayNumber,
        locationId: null,
        message: '当日 $holidayNoHours 个景点$prefix，开放时间可能与常规不同，请以官方公告为准',
      ),
    );
  }

  // ③ 其余未校验（含客户端无从分辨的 official_notice / holiday_needs_calendar
  //    —— reason 不进 payload，见 [OpenHoursHintKind.officialNotice] 注释）
  //    → 维持**中性**（与既有分级一致）：老行程 / 真实 payload 的每一天都落在这里，
  //    升级成提醒会让"没拿到营业时间"变成满屏警告，那是另一种假阳性。
  final restUnchecked = unchecked - holidayNoHours;
  if (restUnchecked > 0) {
    issues.add(
      ItineraryIssue(
        code: ItineraryIssueCode.ch09OpenHoursUnknown,
        severity: IssueSeverity.neutral,
        dayNumber: day.dayNumber,
        // ⛔ 日级问题**不归责到任何卡片**：否则用户会以为某个景点出了事
        locationId: null,
        // 措辞口径（T05）：「无原文依据」而非「未取到营业时间」（旧措辞，已废弃）——
        // 本档的真实语义是"原文没给出可核对依据"（含 official_notice /
        // holiday_needs_calendar / 老行程缺字段），不是抓取失败，
        // 不能让用户以为是我们坏了。
        //
        // ⛔ 同时**不**给出任何时刻、**不**出现"闭馆"二字（连"未做闭馆校验"
        //    这种否定式也不写：用户扫读只会看到"闭馆"两字，等于自己造噪声）。
        message:
            '当日 $restUnchecked 个景点：该日营业时间无原文依据，请以官方公告为准（未做营业时间校验）',
      ),
    );
  }

  // ---------------- 同地点最多一条 ----------------
  final primary = <String, ItineraryIssue>{};
  for (final issue in issues) {
    final id = issue.locationId;
    if (id == null) continue;
    final current = primary[id];
    if (current == null || _isHigherPriority(issue, current)) {
      primary[id] = issue;
    }
  }

  final shown = <ItineraryIssue>[
    ...primary.values,
    ...issues.where((i) => i.locationId == null),
  ];

  return DayCheckResult(
    slots: slots,
    issues: issues,
    primaryIssueByLocation: primary,
    blockingCount: shown.where((i) => i.severity == IssueSeverity.blocking).length,
    reminderCount: shown.where((i) => i.severity == IssueSeverity.reminder).length,
    uncheckedAttractionCount: unchecked,
  );
}

/// 取某地点的主问题（页面给卡片用）。无则 null。
ItineraryIssue? primaryIssueForLocation(DayCheckResult result, String locationId) =>
    result.primaryIssueByLocation[locationId];

// ---------------------------------------------------------------------------
// 内部工具
// ---------------------------------------------------------------------------

/// 到该地点的交通分钟数；缺失或 <= 0 视为「没有可用交通耗时」→ null。
int? _travelMinutesOf(Location loc) {
  final t = loc.transportMinutes;
  if (t == null || t <= 0) return null;
  return t;
}

/// 把 payload 原计划到达链按锚**单调展开**，撤销 `fmt()` 的 `% 1440` 绕回。
///
/// ## 为什么需要
/// 服务端 `fmt()` 会 mod 1440（planner.js:642），所以排过午夜的站在 payload 里
/// 长这样：酒店真实到达 24:58（1498 分钟），下发成 `"00:58"`（58 分钟）。
/// 直接拿 58 去比「前站 23:15 离开（1395）」会得到 −1337 分钟的荒谬差值，
/// 并升级成阻塞级假阳性。
///
/// ## 展开规则（确定性，不猜）
/// 以第一个非 null 的 `sourceArrival` 为基准，向后逐站：只要比上一站小就补 1440，
/// 直到不小于上一站。行程时刻在同一天内单调不减，这是**结构性事实**而非估算。
///
/// 返回数组与 `slots` 等长；payload 缺 `arrivalTime` 的位置为 null（该处规则自动跳过）。
List<int?> _unwrapSourceArrivals(List<ItinerarySlot> slots) {
  final out = <int?>[];
  var previous = 0;
  var started = false;
  for (final slot in slots) {
    final raw = slot.sourceArrival;
    if (raw == null) {
      out.add(null);
      continue;
    }
    var value = raw;
    if (started) {
      while (value < previous) {
        value += kMinutesPerDay;
      }
    } else {
      started = true;
    }
    previous = value;
    out.add(value);
  }
  return out;
}

/// 住宿是否构成「过夜边界」（设计 A-2）。
///
/// 酒店 `stayMinutes` 是**过夜时长**，不是当日活动时长：
/// 把它计入「当日排过午夜」会让正常住店天天误报（服务端给酒店 stay=600 且 `fmt()` 已绕回）。
///
/// 因此：忽略酒店自身的 `sourceWrapped`，也不把酒店停留计入累计日终；
/// 但酒店**到达时刻**若已超过 24:00，仍会由累计日终触发 CH-04。
bool _isOvernightBoundary(Location loc) => loc.type == LocationType.hotel;

String _typeLabel(LocationType type) => switch (type) {
      LocationType.attraction => '景点',
      LocationType.restaurant => '餐厅',
      LocationType.hotel => '酒店',
      LocationType.shopping => '购物',
      LocationType.transport => '枢纽',
      LocationType.home => '出发地',
      LocationType.other => '该点',
    };

/// 累计日终结算（住宿时长不计，见 [_isOvernightBoundary]）
class _DayEnd {
  final int endMinutes;
  final ItinerarySlot slot;
  const _DayEnd(this.endMinutes, this.slot);
}

_DayEnd? _dayEnd(List<ItinerarySlot> slots) {
  if (slots.isEmpty) return null;
  if (slots.first.arrival == null) return null; // 无锚 → 没有可信日终
  var best = 0;
  ItinerarySlot? bestSlot;
  for (final slot in slots) {
    final arrival = slot.arrival;
    if (arrival == null) continue;
    final stay = _isOvernightBoundary(slot.location) ? 0 : (slot.location.stayMinutes ?? 0);
    final end = arrival + stay;
    if (bestSlot == null || end > best) {
      best = end;
      bestSlot = slot;
    }
  }
  if (bestSlot == null) return null;
  return _DayEnd(best, bestSlot);
}

/// 稳定排序：`severity` 优先，同级比 `code.priority`。
bool _isHigherPriority(ItineraryIssue a, ItineraryIssue b) {
  final bySeverity = a.severity.rank.compareTo(b.severity.rank);
  if (bySeverity != 0) return bySeverity < 0;
  return a.priority < b.priority;
}
