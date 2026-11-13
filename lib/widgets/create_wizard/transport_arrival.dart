import '../../models/trip_models.dart';
import '../../utils/itinerary_checker.dart';

/// 交通方式确认后重算到达时刻（创建行程页 `_showTransportModal.onConfirm` 的唯一入口）。
///
/// ## 修掉的两个真实 bug
///
/// 1. **跨午夜**：旧实现 `(arrivalMinutes ~/ 60) % 24` 把「次日 00:58」错显示成
///    「00:58」。项目口径是内部保留**未 mod 1440** 的分钟数，只有
///    `formatClockMinutes()` 能表达「次日 HH:mm」。
/// 2. **字段丢失**：旧实现重新 `Transport(...)` 只拷了 8 个字段，
///    丢了 `price` / `isFixed` / `estimated`（`trip_models.dart:565` 完整字段清单
///    含 id / type / scope / flightNumber / departureTime / arrivalTime /
///    durationMinutes / distance / price / isFixed / estimated）。
///    本函数**原地改原对象**的 `arrivalTime`，从根上杜绝重建丢字段。
///
/// ## 三铁律
/// 出发时刻无法解析、是占位符、或时长缺失时**不写到达时间**（不编造）；
/// 弹窗已给出的 `arrivalTime` 原样保留，不覆盖成推算值。
///
/// 返回同一个 [transport] 实例（便于调用方与测试断言对象身份）。
Transport applyTransportArrivalTime(Transport transport) {
  final String? depTime = transport.departureTime;
  final int? duration = transport.durationMinutes;
  if (depTime == null || depTime == '--:--' || duration == null) {
    return transport;
  }
  final int? departureMinutes = parseClockMinutes(depTime);
  if (departureMinutes == null) {
    return transport;
  }
  transport.arrivalTime = formatClockMinutes(departureMinutes + duration);
  return transport;
}
