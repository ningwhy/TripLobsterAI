import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trip_planner/models/trip_models.dart';
import 'package:trip_planner/pages/trip_members_page.dart';
import 'package:trip_planner/providers/trip_provider.dart';
import 'package:trip_planner/services/storage_service.dart';
import 'package:trip_planner/widgets/timeline/members_bar.dart';

/// 成员管理链路的 widget 层回归测试。
///
/// ## 为什么需要本文件
/// 改动前 `lib/pages/` 与 `members_bar.dart` **零测试覆盖**（既有用例全是
/// models / utils / timeline 纯组件），成员页是「3 个硬编码示例成员 + 一堆空实现」的死页，
/// 改错了没有任何防线。本文件用真实 `TripProvider` + 内存 `StorageService` 跑 widget 环境，
/// 断言全部落在「用户可见的结果」与「落库后的真实数据」上。
///
/// ## 断言纪律
/// - 不写「某函数被调用了」这类恒真断言：回调一律通过界面上真实变化的文本来观测；
/// - 期望值按业务规格独立写出（示例假姓名、真实成员数、真实 trip.id 拼出的链接），
///   不从实现里抄常量；
/// - 存储层每次 `getTrips()` 都重新从 JSON 解析出新对象，
///   因此「Provider 里真的变了」不可能靠原地改引用蒙混过关。

/// 内存版 StorageService：只覆盖成员链路会用到的两个方法，
/// 其余方法仍走 `SharedPreferences`（本文件不会调用），避免引入额外依赖。
class _MemoryStorage extends StorageService {
  final Map<String, Map<String, dynamic>> _raw = <String, Map<String, dynamic>>{};

  @override
  Future<List<Trip>> getTrips() async => _raw.values
      .map((Map<String, dynamic> json) =>
          Trip.fromJson(Map<String, dynamic>.from(json)))
      .toList();

  @override
  Future<void> saveTrip(Trip trip) async {
    _raw[trip.id] = trip.toJson();
  }
}

/// 成员条测试宿主：把 onTap / onInvite 的结果渲染成可见文本，
/// 断言「界面变了」而不是「回调计数器变了」。
class _BarHarness extends StatelessWidget {
  final Trip trip;
  final VoidCallback onInvite;
  final VoidCallback? onTap;
  final ValueListenable<int> opened;
  final ValueListenable<int> invited;

  const _BarHarness({
    required this.trip,
    required this.onInvite,
    required this.opened,
    required this.invited,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: opened,
              builder: (BuildContext context, int value, Widget? child) =>
                  Text('已打开成员页:$value'),
            ),
            ValueListenableBuilder<int>(
              valueListenable: invited,
              builder: (BuildContext context, int value, Widget? child) =>
                  Text('邀请次数:$value'),
            ),
            MembersBar(trip: trip, onInvite: onInvite, onTap: onTap),
          ],
        ),
      ),
    );
  }
}

void main() {
  const String adminId = 'm-admin';
  const String guestId = 'm-guest';
  const String secondAdminId = 'm-admin-2';
  const String tripId = 'trip-members-1';

  /// 真实成员（含真实照片 id），⛔ 与页面旧示例「张明/李雪/王强」完全不同。
  List<Member> defaultMembers() => <Member>[
        Member(
          id: adminId,
          name: '赵敏',
          role: MemberRole.admin,
          photoIds: const <String>['p1', 'p2'],
        ),
        Member(
          id: guestId,
          name: '周杰',
          role: MemberRole.member,
          photoIds: const <String>['p3'],
        ),
      ];

  Trip mkTrip({List<Member>? members}) => Trip(
        id: tripId,
        name: '云南六日',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 5, 6),
        adults: 3,
        children: 0,
        rooms: 1,
        members: members ?? defaultMembers(),
      );

  Future<TripProvider> makeProvider(Trip seed) async {
    final TripProvider provider = TripProvider(_MemoryStorage());
    await provider.createTrip(seed);
    return provider;
  }

  Widget wrapPage(TripProvider provider, String id) =>
      ChangeNotifierProvider<TripProvider>.value(
        value: provider,
        child: MaterialApp(home: TripMembersPage(tripId: id)),
      );

  /// 成员页是个长 ListView；默认 800x600 测试画布下方内容不会被 build，
  /// 所以统一放大画布，让「复制 / 邀请 / 示意链接」都在树里。
  Future<void> pumpPage(WidgetTester tester, TripProvider provider, String id) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapPage(provider, id));
    await tester.pumpAndSettle();
  }

  Trip storedTrip(TripProvider provider) =>
      provider.trips.firstWhere((Trip t) => t.id == tripId);

  Member storedMember(TripProvider provider, String memberId) =>
      storedTrip(provider).members.firstWhere((Member m) => m.id == memberId);

  /// 精确定位某个成员行的「更多」按钮（避免命中其它成员的按钮）。
  Finder optionsFor(String memberName) => find.descendant(
        of: find.ancestor(
          of: find.text(memberName),
          matching: find.byType(ListTile),
        ),
        matching: find.byIcon(Icons.more_vert),
      );

  /// 精确判定某一行是否带「管理员」角标（权限说明区也有「管理员」三字，不能全局找）。
  Finder adminBadgeFor(String memberName) => find.descendant(
        of: find.ancestor(
          of: find.text(memberName),
          matching: find.byType(ListTile),
        ),
        matching: find.text('管理员'),
      );

  Future<void> openOptions(WidgetTester tester, String memberName) async {
    await tester.tap(optionsFor(memberName));
    await tester.pumpAndSettle();
  }

  // ==================================================================
  group('MembersBar 可选 onTap', () {
    testWidgets('onTap 为 null：不插入整条手势层，布局与文案保持不变', (tester) async {
      final ValueNotifier<int> opened = ValueNotifier<int>(0);
      final ValueNotifier<int> invited = ValueNotifier<int>(0);
      await tester.pumpWidget(_BarHarness(
        trip: mkTrip(),
        onInvite: () => invited.value++,
        opened: opened,
        invited: invited,
      ));

      // 树里只剩原来那个「+」头像的手势层，且其 child 是 CircleAvatar。
      final Iterable<GestureDetector> detectors =
          tester.widgetList<GestureDetector>(find.byType(GestureDetector));
      expect(detectors, hasLength(1));
      expect(detectors.single.child, isA<CircleAvatar>());
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is GestureDetector && w.child is Container,
        ),
        findsNothing,
      );

      // 可见文案与数值不变（3 人 = adults 3 + children 0）。
      expect(find.text('共 3 人 · 1 间房'), findsOneWidget);
      expect(find.text('已打开成员页:0'), findsOneWidget);
      expect(find.text('邀请次数:0'), findsOneWidget);

      // 点击人数文案（整条区域）不会触发任何新回调。
      await tester.tap(find.text('共 3 人 · 1 间房'));
      await tester.pump();
      expect(find.text('已打开成员页:0'), findsOneWidget);
    });

    testWidgets('onTap 非 null：点击整条触发，且 "+" 仍走原有 onInvite', (tester) async {
      final ValueNotifier<int> opened = ValueNotifier<int>(0);
      final ValueNotifier<int> invited = ValueNotifier<int>(0);
      await tester.pumpWidget(_BarHarness(
        trip: mkTrip(),
        onInvite: () => invited.value++,
        onTap: () => opened.value++,
        opened: opened,
        invited: invited,
      ));

      expect(
        find.byWidgetPredicate(
          (Widget w) => w is GestureDetector && w.child is Container,
        ),
        findsOneWidget,
      );

      // 点人数文案（非 "+" 区域）→ 整条回调生效，界面文本真的变化。
      await tester.tap(find.text('共 3 人 · 1 间房'));
      await tester.pump();
      expect(find.text('已打开成员页:1'), findsOneWidget);
      expect(find.text('邀请次数:0'), findsOneWidget);

      // 点 "+" → 子组件优先命中，仍只走原有的邀请回调。
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('邀请次数:1'), findsOneWidget);
    });

    testWidgets('members 为空：即使传了 onTap，整条依旧隐藏', (tester) async {
      final ValueNotifier<int> opened = ValueNotifier<int>(0);
      final ValueNotifier<int> invited = ValueNotifier<int>(0);
      await tester.pumpWidget(_BarHarness(
        trip: mkTrip(members: <Member>[]),
        onInvite: () => invited.value++,
        onTap: () => opened.value++,
        opened: opened,
        invited: invited,
      ));

      expect(find.byType(MembersBar), findsOneWidget);
      expect(find.byType(Container), findsNothing);
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.text('共 3 人 · 1 间房'), findsNothing);
      expect(find.text('已打开成员页:0'), findsOneWidget);
    });
  });

  // ==================================================================
  group('成员页：真实数据与诚实空态', () {
    testWidgets('渲染真实 members，示例假姓名与写死的 55 张照片不再出现', (tester) async {
      final Trip seed = mkTrip();
      final TripProvider provider = await makeProvider(seed);
      await pumpPage(tester, provider, tripId);

      // 规格：页面只显示 Provider 里的真实成员
      expect(find.text('赵敏'), findsOneWidget);
      expect(find.text('周杰'), findsOneWidget);
      expect(find.text('云南六日'), findsOneWidget);
      expect(find.text('2张照片'), findsOneWidget);
      expect(find.text('1张照片'), findsOneWidget);

      // 规格：旧的 3 个示例成员、写死的照片统计必须彻底消失
      for (final String fakeName in <String>['张明', '李雪', '王强']) {
        expect(find.text(fakeName), findsNothing);
      }
      expect(find.text('55'), findsNothing);
      expect(find.text('abc123'), findsNothing);

      // 统计数字来自真实数据：2 个成员、共 3 张照片。
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsWidgets);

      // 真实 admin 才有角标，普通成员没有。
      expect(adminBadgeFor('赵敏'), findsOneWidget);
      expect(adminBadgeFor('周杰'), findsNothing);
    });

    testWidgets('按 id 找不到行程：显示明确空态，不编造成员', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, 'not-exist-id');

      expect(find.text('未找到该行程，无法查看成员'), findsOneWidget);
      expect(find.text('赵敏'), findsNothing);
      expect(find.text('周杰'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('members 为空：如实显示「当前行程没有成员」，不补示例人', (tester) async {
      final TripProvider provider =
          await makeProvider(mkTrip(members: <Member>[]));
      await pumpPage(tester, provider, tripId);

      expect(find.text('当前行程没有成员'), findsOneWidget);
      expect(find.text('张明'), findsNothing);
      expect(find.text('李雪'), findsNothing);
      expect(find.text('王强'), findsNothing);
    });
  });

  // ==================================================================
  group('成员页：角色切换与移除（写回 Provider）', () {
    testWidgets('把普通成员设为管理员后，Provider 里的 role 真的变成 admin', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await openOptions(tester, '周杰');
      expect(find.text('设为管理员'), findsOneWidget);
      await tester.tap(find.text('设为管理员'));
      await tester.pumpAndSettle();

      expect(storedMember(provider, guestId).role, MemberRole.admin);
      expect(storedMember(provider, guestId).isAdmin, isTrue);
      expect(
        storedTrip(provider).members.where((Member m) => m.isAdmin).length,
        2,
      );
      expect(adminBadgeFor('周杰'), findsOneWidget);
      // 原有 admin 不受影响，人数也没被悄悄改动。
      expect(storedMember(provider, adminId).isAdmin, isTrue);
      expect(storedTrip(provider).members.length, 2);
    });

    testWidgets('存在第二名管理员时，可把管理员降级为普通成员', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip(
        members: <Member>[
          ...defaultMembers(),
          Member(id: secondAdminId, name: '钱多多', role: MemberRole.admin),
        ],
      ));
      await pumpPage(tester, provider, tripId);

      await openOptions(tester, '赵敏');
      expect(find.text('设为普通成员'), findsOneWidget);
      await tester.tap(find.text('设为普通成员'));
      await tester.pumpAndSettle();

      expect(storedMember(provider, adminId).role, MemberRole.member);
      expect(storedMember(provider, adminId).isAdmin, isFalse);
      expect(adminBadgeFor('赵敏'), findsNothing);
      // 另一名 admin 仍在，行程不会变成无管理员。
      expect(storedMember(provider, secondAdminId).isAdmin, isTrue);
    });

    testWidgets('移除成员：点「取消」不写回，成员不减少', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await openOptions(tester, '周杰');
      await tester.tap(find.text('移除成员'));
      await tester.pumpAndSettle();

      expect(find.text('确定移除「周杰」吗？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('周杰'), findsOneWidget);
      expect(storedTrip(provider).members.length, 2);
    });

    testWidgets('移除成员：二次确认后 Provider 与界面都真的少一个人', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await openOptions(tester, '周杰');
      await tester.tap(find.text('移除成员'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();

      expect(storedTrip(provider).members.length, 1);
      expect(
        storedTrip(provider).members.where((Member m) => m.id == guestId),
        isEmpty,
      );
      expect(find.text('周杰'), findsNothing);
      expect(find.text('赵敏'), findsOneWidget);
    });

    testWidgets('唯一管理员不可移除：给出明确提示且不弹确认框、成员不减少', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await openOptions(tester, '赵敏');
      expect(find.text('唯一管理员不可移除，行程需保留至少一名管理员'), findsOneWidget);
      await tester.tap(find.text('移除成员'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('行程需保留至少一名管理员，无法移除唯一管理员'), findsOneWidget);
      expect(storedTrip(provider).members.length, 2);
      expect(storedMember(provider, adminId).isAdmin, isTrue);
    });

    testWidgets('唯一管理员不可降级：给出明确提示且角色不变', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await openOptions(tester, '赵敏');
      await tester.tap(find.text('设为普通成员'));
      await tester.pumpAndSettle();

      expect(find.text('行程需保留至少一名管理员，无法将唯一管理员降级'), findsOneWidget);
      expect(storedMember(provider, adminId).role, MemberRole.admin);
      expect(storedTrip(provider).members.length, 2);
    });
  });

  // ==================================================================
  group('成员页：新增成员与邀请链接', () {
    testWidgets('新增成员：只写入用户输入的昵称，不生成假头像/照片/角色以外的数据', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await tester.tap(find.text('新增成员'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  孙悦  ');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(storedTrip(provider).members.length, 3);
      final Member added = storedTrip(provider).members
          .firstWhere((Member m) => m.name == '孙悦');
      expect(added.role, MemberRole.member);
      expect(added.avatarUrl, isNull);
      expect(added.photoIds, isEmpty);
      expect(added.lastActiveAt, isNull);
      expect(find.text('孙悦'), findsOneWidget);
      // 昵称两端空白被去掉，没有把 '  孙悦  ' 原样塞进数据。
      expect(
        storedTrip(provider).members.where((Member m) => m.name == '  孙悦  '),
        isEmpty,
      );
    });

    testWidgets('新增成员：昵称为空白时如实提示，不写入任何成员', (tester) async {
      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await tester.tap(find.text('新增成员'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('昵称不能为空，未添加成员'), findsOneWidget);
      expect(storedTrip(provider).members.length, 2);
    });

    testWidgets('复制邀请链接：确实写入剪贴板并如实反馈「示意链接」', (tester) async {
      final List<String> copied = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            final Object? args = call.arguments;
            if (args is Map && args['text'] is String) {
              copied.add(args['text'] as String);
            }
          }
          return null;
        },
      );
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final Trip seed = mkTrip();
      final TripProvider provider = await makeProvider(seed);
      await pumpPage(tester, provider, tripId);

      // 规格：项目没有真实邀请服务，页面必须明确标注示意性质。
      expect(find.text('示意链接，实际项目需接入邀请服务'), findsOneWidget);
      expect(find.text('https://trip.app/invite/abc123'), findsNothing);

      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();

      // 规格：写「已复制」就必须真有一次 Clipboard.setData。
      expect(copied, hasLength(1));
      expect(copied.single, startsWith('https://trip.app/invite/'));
      expect(copied.single, contains(seed.id));
      expect(copied.single, isNot(contains('abc123')));
      expect(find.textContaining('邀请链接已复制'), findsOneWidget);
      expect(find.textContaining('示意链接，实际项目需接入邀请服务'), findsWidgets);

      // 顶部「邀请」按钮走的是同一个真实复制动作。
      await tester.tap(find.text('邀请'));
      await tester.pumpAndSettle();
      expect(copied, hasLength(2));
      expect(copied.last, contains(seed.id));
    });

    testWidgets('分享：调起系统分享且内容用真实行程名+链接，不宣称「分享成功」', (tester) async {
      const MethodChannel shareChannel =
          MethodChannel('dev.fluttercommunity.plus/share');
      final List<String> sharedTexts = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        shareChannel,
        (MethodCall call) async {
          if (call.method == 'share') {
            final Object? args = call.arguments;
            if (args is Map && args['text'] is String) {
              sharedTexts.add(args['text'] as String);
            }
          }
          // 非空且非 unavailable → ShareResultStatus.success
          return 'dev.fluttercommunity.plus/share/success';
        },
      );
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));

      final Trip seed = mkTrip();
      final TripProvider provider = await makeProvider(seed);
      await pumpPage(tester, provider, tripId);

      // 规格：没有二维码生成能力就必须明说，不能让按钮文案误导用户。
      expect(find.textContaining('未生成二维码'), findsOneWidget);

      await tester.tap(find.text('微信'));
      await tester.pumpAndSettle();

      expect(sharedTexts, hasLength(1));
      expect(sharedTexts.single, contains(seed.name));
      expect(sharedTexts.single, contains(seed.id));
      expect(sharedTexts.single, contains('示意链接，实际项目需接入邀请服务'));
      // 系统分享面板被调起 ≠ 真的分享出去，反馈里绝不出现成功结论。
      expect(find.text('已调起系统分享，是否发送由所选应用决定'), findsOneWidget);
      expect(find.textContaining('分享成功'), findsNothing);
    });

    testWidgets('分享：平台抛异常时如实说明「不可用，未分享」', (tester) async {
      const MethodChannel shareChannel =
          MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        shareChannel,
        (MethodCall call) async => throw PlatformException(code: 'unavailable'),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));

      final TripProvider provider = await makeProvider(mkTrip());
      await pumpPage(tester, provider, tripId);

      await tester.tap(find.text('朋友圈'));
      await tester.pumpAndSettle();

      expect(find.text('系统分享不可用，未分享'), findsOneWidget);
      expect(find.textContaining('分享成功'), findsNothing);
    });
  });
}
