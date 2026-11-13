import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/utils/itinerary_checker.dart';
import 'package:trip_planner/widgets/create_wizard/transport_arrival.dart';

/// `trip_create_page.dart:730` / `:734-743` 两处真实 bug 的回归锁。
///
/// bug A：跨午夜 `% 24` 把「次日 00:58」错显示成「00:58」。
/// bug B：重建 `Transport` 时丢了 price / isFixed / estimated。
void main() {
  Transport mkTransport({
    String? dep,
    int? duration,
    String? arrival,
  }) =>
      Transport(
        id: 'fixed-id-1515',
        type: TransportType.flight,
        scope: TransportScope.intercity,
        flightNumber: 'CA1515',
        departureTime: dep,
        arrivalTime: arrival,
        durationMinutes: duration,
        distance: 2200.0,
        price: 1280,
        isFixed: true,
        estimated: false,
      );

  test('跨午夜：23:30 + 88 分钟 → 次日 00:58（且原地改同一对象）', () {
    final Transport t = mkTransport(dep: '23:30', duration: 88);
    final Transport returned = applyTransportArrivalTime(t);
    expect(t.arrivalTime, '次日 00:58');
    expect(identical(returned, t), isTrue,
        reason: '不得重建 Transport，否则 price/isFixed/estimated 会丢');
  });

  test('当天到达不带「次日」：08:00 + 150 分钟 → 10:30', () {
    final Transport t = mkTransport(dep: '08:00', duration: 150);
    applyTransportArrivalTime(t);
    expect(t.arrivalTime, '10:30');
  });

  test('24:00 出发（服务端合法脏数据）+ 30 分钟 → 次日 00:30', () {
    final Transport t = mkTransport(dep: '24:00', duration: 30);
    applyTransportArrivalTime(t);
    expect(t.arrivalTime, '次日 00:30');
  });

  test('出发时刻无法解析 / 占位符 / 时长缺失 → 不写到达时间（不编造）', () {
    for (final String? dep in <String?>[
      '--:--',
      '9:5x',
      '25:00',
      '09:00-17:00',
      null,
      '',
    ]) {
      final Transport t = mkTransport(dep: dep, duration: 60);
      applyTransportArrivalTime(t);
      expect(t.arrivalTime, isNull, reason: 'dep=$dep 时不得推算到达时间');
    }

    final Transport noDuration = mkTransport(dep: '23:30');
    applyTransportArrivalTime(noDuration);
    expect(noDuration.arrivalTime, isNull);
  });

  test('弹窗已给出的到达时刻在无法推算时原样保留（不编造、不误删）', () {
    final Transport t =
        mkTransport(dep: '--:--', duration: 60, arrival: '10:30');
    applyTransportArrivalTime(t);
    expect(t.arrivalTime, '10:30');
  });

  test('重算后 Transport 全部字段不丢（字段清单逐字核对 trip_models.dart:565）', () {
    final Transport t = mkTransport(dep: '23:30', duration: 88);
    applyTransportArrivalTime(t);

    expect(t.id, 'fixed-id-1515');
    expect(t.type, TransportType.flight);
    expect(t.scope, TransportScope.intercity);
    expect(t.flightNumber, 'CA1515');
    expect(t.departureTime, '23:30');
    expect(t.arrivalTime, '次日 00:58');
    expect(t.durationMinutes, 88);
    expect(t.distance, 2200.0);
    expect(t.price, 1280);
    expect(t.isFixed, isTrue);
    expect(t.estimated, isFalse);

    // 云同步契约：三字段必须随 toJson 走
    final Map<String, dynamic> json = t.toJson();
    expect(json['price'], 1280);
    expect(json['isFixed'], isTrue);
    expect(json['estimated'], isFalse);
    expect(json['arrivalTime'], '次日 00:58');

    final Transport roundTrip = Transport.fromJson(json);
    expect(roundTrip.price, 1280);
    expect(roundTrip.isFixed, isTrue);
    expect(roundTrip.estimated, isFalse);
  });

  test('口径锚：parseClockMinutes / formatClockMinutes 未 mod 1440', () {
    expect(parseClockMinutes('23:30'), 1410);
    expect(formatClockMinutes(1410 + 88), '次日 00:58');
    expect(formatClockMinutes(630), '10:30');
    expect(parseClockMinutes('--:--'), isNull);
    expect(parseClockMinutes('09:00-17:00'), isNull);
  });
}
