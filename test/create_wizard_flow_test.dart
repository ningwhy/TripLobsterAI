import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/pages/trip_create_page.dart';
import 'package:trip_planner/providers/trip_provider.dart';
import 'package:trip_planner/services/storage_service.dart';
import 'package:trip_planner/utils/wizard_step.dart';
import 'package:trip_planner/widgets/create_wizard/step_option_card.dart';

/// 创建行程四步引导的 widget 层回归测试。
///
/// 既有测试完全不 import `pages/*`，本批首次为 `TripCreatePage` 补防线：
/// 四步推进/回退、圆点跳步、跨步数据不丢、最后一步文案、生成后 Provider 落库、
/// 以及 T04 的 `clearOpenHoursFacts()` 日期变更防线。
///
/// 宿主页额外 push 一层路由，是为了让 `_saveTrip()` 里的 `Navigator.pop(context)`
/// 有真实可退栈（widget 测试里直接把页面当 home 会 pop 到空 Navigator）。
class _HostPage extends StatelessWidget {
  const _HostPage({this.trip});

  final Trip? trip;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => TripCreatePage(trip: trip),
                ),
              );
            },
            child: const Text('打开创建行程'),
          ),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late TripProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    provider = TripProvider(storage);
  });

  Widget buildApp({Trip? trip}) => ChangeNotifierProvider<TripProvider>.value(
        value: provider,
        child: MaterialApp(home: _HostPage(trip: trip)),
      );

  Future<void> openWizard(WidgetTester tester, {Trip? trip}) async {
    await tester.pumpWidget(buildApp(trip: trip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开创建行程'));
    await tester.pumpAndSettle();
  }

  Finder nextButton() => find.byKey(const Key('wizardNextButton'));
  Finder prevButton() => find.byKey(const Key('wizardPrevButton'));
  Finder dot(int index) => find.byKey(Key('wizardStepDot$index'));
  Finder pane(int index) => find.byKey(Key('wizardPane$index'));
  Finder nameField() => find.byKey(const Key('tripNameField'));

  Future<void> goNext(WidgetTester tester) async {
    await tester.tap(nextButton());
    await tester.pumpAndSettle();
  }

  Future<void> goPrev(WidgetTester tester) async {
    await tester.tap(prevButton());
    await tester.pumpAndSettle();
  }

  testWidgets('四步推进与回退：第 1 步上一步禁用，回退后名称不丢', (tester) async {
    await openWizard(tester);

    expect(pane(0), findsOneWidget);
    expect(find.text('行程类型'), findsOneWidget);
    expect(find.text(kNextLabel), findsOneWidget);
    expect(find.text(kPrevLabel), findsOneWidget);
    expect(tester.widget<OutlinedButton>(prevButton()).onPressed, isNull);

    await tester.enterText(nameField(), '跨步测试行程');
    await tester.pumpAndSettle();

    await goNext(tester);
    expect(pane(1), findsOneWidget);
    expect(find.text('开始日期'), findsOneWidget);
    expect(find.text('结束日期'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(prevButton()).onPressed, isNotNull);
    expect(find.text(kNextLabel), findsOneWidget);

    await goNext(tester);
    expect(pane(2), findsOneWidget);
    expect(find.text('行程时间线'), findsOneWidget);
    expect(find.text(kNextLabel), findsOneWidget);

    await goNext(tester);
    expect(pane(3), findsOneWidget);
    expect(find.text(kGenerateLabel), findsOneWidget);
    expect(find.text(kNextLabel), findsNothing);

    for (var i = 0; i < 3; i++) {
      await goPrev(tester);
    }
    expect(pane(0), findsOneWidget);
    expect(find.text('跨步测试行程'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(prevButton()).onPressed, isNull);
  });

  testWidgets('步骤圆点可直接跳步，且切步不清空已填数据', (tester) async {
    await openWizard(tester);
    await tester.enterText(nameField(), '圆点跳步行程');
    await tester.pumpAndSettle();

    await tester.tap(dot(3));
    await tester.pumpAndSettle();
    expect(pane(3), findsOneWidget);
    expect(find.text(kGenerateLabel), findsOneWidget);

    await tester.tap(dot(1));
    await tester.pumpAndSettle();
    expect(pane(1), findsOneWidget);
    expect(find.text('开始日期'), findsOneWidget);

    await tester.tap(dot(0));
    await tester.pumpAndSettle();
    expect(pane(0), findsOneWidget);
    expect(find.text('圆点跳步行程'), findsOneWidget);

    await tester.tap(dot(2));
    await tester.pumpAndSettle();
    expect(pane(2), findsOneWidget);
    expect(find.text('行程时间线'), findsOneWidget);
  });

  testWidgets('跨步选项不丢：第 1 步选纯自驾，第 3 步显示纯自驾提示', (tester) async {
    await openWizard(tester);
    await tester.tap(find.byKey(const Key('tripTypeOption0')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<StepOptionCard>(find.byKey(const Key('tripTypeOption0')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<StepOptionCard>(find.byKey(const Key('tripTypeOption1')))
          .selected,
      isFalse,
    );

    await tester.tap(dot(2));
    await tester.pumpAndSettle();
    expect(find.text('纯自驾行程无交通枢纽，长距离将自动提示服务区'),
        findsOneWidget);
    expect(find.text('跨城: '), findsNothing);

    await tester.tap(dot(0));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StepOptionCard>(find.byKey(const Key('tripTypeOption0')))
          .selected,
      isTrue,
    );
  });

  testWidgets('空名称挡住「下一步」并沿用原有提示文案', (tester) async {
    await openWizard(tester);
    await goNext(tester);
    expect(pane(0), findsOneWidget);
    // 名称输入框的 hint 与 SnackBar 文案同名，必须限定在 SnackBar 子树里断言
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('请输入行程名称'),
      ),
      findsOneWidget,
    );

    await tester.enterText(nameField(), '补上名称');
    await tester.pumpAndSettle();
    // SnackBar 覆盖在底部按钮上，先走完它的 4s 停留计时再点「下一步」
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await goNext(tester);
    expect(pane(1), findsOneWidget);
  });

  testWidgets('第 4 步「生成行程 ›」把新 Trip 写入 Provider 并退出页面',
      (tester) async {
    await openWizard(tester);
    await tester.enterText(nameField(), '春节出游');
    await tester.pumpAndSettle();

    await tester.tap(dot(3));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ElevatedButton, kGenerateLabel), findsOneWidget);
    expect(find.text('春节出游'), findsWidgets); // 第 4 步摘要也回显名称

    await tester.tap(nextButton());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(provider.trips.length, 1);
    expect(provider.trips.first.name, '春节出游');
    expect(provider.trips.first.days, isNotEmpty);
    expect(provider.trips.first.tripMode, TripMode.pureTransit);
    expect(find.text('打开创建行程'), findsOneWidget); // 已 pop 回宿主
  });

  testWidgets('编辑模式改出发日 → clearOpenHoursFacts() 真的清空营业事实',
      (tester) async {
    final DateTime now = DateTime.now();
    // 两个月后的 20 号：showDatePicker 的 firstDate=now、lastDate=now+365d，
    // 当月所有日期都可选；初始日 20 ≠ 目标日 15，15 号不会与相邻月补位日重号。
    final DateTime start = DateTime(now.year, now.month + 2, 20);
    final Location loc = Location(
      name: '测试景点',
      address: '测试地址',
      type: LocationType.attraction,
      openTime: '09:00',
      closeTime: '17:00',
      lastEntryTime: '16:30',
      closedOnDate: false,
      openHoursRaw: '09:00-17:00',
      // 第 8 个字段必须播种：否则 `expect(openSegments, isNull)` 是恒真断言，
      // 生产代码删掉 clearOpenHoursFacts() 里的 openSegments = null 也测不出来。
      openSegments: const [OpenSegment(open: '09:00', close: '17:00')],
      holidayName: '劳动节',
      holidayStatus: 'holiday',
    );
    final Trip trip = Trip(
      name: '原行程',
      startDate: start,
      endDate: start,
      days: [
        TripDay(date: start, dayNumber: 1, locations: [loc]),
      ],
    );

    await openWizard(tester, trip: trip);
    expect(loc.openTime, '09:00'); // 前置条件：营业事实确实存在
    expect(loc.openSegments, isNotNull); // 8 个字段全部播种，杜绝恒真断言

    await tester.tap(dot(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startDatePicker')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    final Finder dayCell = find.text('15');
    expect(dayCell, findsOneWidget);
    await tester.tap(dayCell);
    await tester.pumpAndSettle();

    final Finder confirm = find.byWidgetPredicate(
      (Widget w) =>
          w is Text &&
          (w.data == 'OK' || w.data == 'Ok' || w.data == '确定'),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    await tester.tap(dot(3));
    await tester.pumpAndSettle();
    await tester.tap(nextButton());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // T04 防线：出发日变化后，旧日期的营业结论必须整体清空
    expect(loc.openTime, isNull);
    expect(loc.closeTime, isNull);
    expect(loc.lastEntryTime, isNull);
    expect(loc.closedOnDate, isNull);
    expect(loc.openHoursRaw, isNull);
    expect(loc.openSegments, isNull);
    expect(loc.holidayName, isNull);
    expect(loc.holidayStatus, isNull);

    expect(provider.trips.length, 1);
    expect(provider.trips.first.name, '原行程');
    expect(find.text('打开创建行程'), findsOneWidget);
  });

  testWidgets('编辑模式不改日期 → 营业事实不被误清空', (tester) async {
    final DateTime now = DateTime.now();
    final DateTime start = DateTime(now.year, now.month + 2, 20);
    final Location loc = Location(
      name: '测试景点',
      address: '测试地址',
      type: LocationType.attraction,
      openTime: '09:00',
      closeTime: '17:00',
      openHoursRaw: '09:00-17:00',
      closedOnDate: false,
      // 反向用例同样播种第 8 个字段，验证「不被误清空」对它一样生效
      openSegments: const [OpenSegment(open: '09:00', close: '17:00')],
    );
    final Trip trip = Trip(
      name: '原行程',
      startDate: start,
      endDate: start,
      days: [
        TripDay(date: start, dayNumber: 1, locations: [loc]),
      ],
    );

    await openWizard(tester, trip: trip);
    expect(loc.openSegments, isNotNull); // 前置条件
    await tester.tap(dot(3));
    await tester.pumpAndSettle();
    await tester.tap(nextButton());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(loc.openTime, '09:00');
    expect(loc.closeTime, '17:00');
    expect(loc.openHoursRaw, '09:00-17:00');
    expect(loc.closedOnDate, isFalse);
    expect(loc.openSegments, isNotNull); // 第 8 个字段同样未被误清空
    expect(provider.trips.length, 1);
  });
}
