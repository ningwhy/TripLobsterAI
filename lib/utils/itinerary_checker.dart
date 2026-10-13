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
    if (loc.closedOnDate == true && raw != null && raw.trim().isNotEmpty) {
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
  for (var i = 1; i < slots.length; i++) {
    final next = slots[i];
    final prev = slots[i - 1];
    final srcArrival = next.sourceArrival;
    final prevLeave = prev.leave;
    final travel = next.travelMinutes;
    // 任一缺失跳过：没有 payload 原计划到达、没有前站可靠离开、没有交通耗时 → 不判断
    if (srcArrival == null || prevLeave == null || travel == null) continue;

    final gap = srcArrival - prevLeave;
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

  // ---------------- CH-09：未校验声明（日级）----------------
  var unchecked = 0;
  for (final loc in day.locations) {
    if (loc.type == LocationType.attraction && !isOpenHoursVerified(loc)) {
      unchecked++;
    }
  }
  if (unchecked > 0) {
    issues.add(
      ItineraryIssue(
        code: ItineraryIssueCode.ch09OpenHoursUnknown,
        severity: IssueSeverity.neutral,
        dayNumber: day.dayNumber,
        // ⛔ 日级问题**不归责到任何卡片**：否则用户会以为某个景点出了事
        locationId: null,
        message: '当日 $unchecked 个景点未取到营业时间，未做打烊/闭馆校验',
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
