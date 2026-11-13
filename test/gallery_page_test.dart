import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner/models/photo_entry.dart';
import 'package:trip_planner/pages/gallery_page.dart';
import 'package:trip_planner/services/photo_source.dart';
import 'package:trip_planner/services/storage_service.dart';

/// 相册页 widget 测试。
///
/// 数据源全部用 [FakePhotoSource] 注入，**不真读设备相册**；
/// `SharedPreferences.setMockInitialValues({})` 验证「完成」确实持久化。
/// 覆盖：三模式切换、勾选跨模式保留、实时计数、看图打开/上一张/下一张/关闭、
/// 权限 denied 空态、信息列表真实时间、原型示意按钮、以及完成后的读回。
class FakePhotoSource extends PhotoSource {
  FakePhotoSource({
    this.state = PhotoPermissionState.granted,
    this.entries = const <PhotoEntry>[],
    this.bytes,
    this.loadError,
  });

  PhotoPermissionState state;
  List<PhotoEntry> entries;
  Uint8List? bytes;
  String? loadError;
  int permissionCalls = 0;
  int loadCalls = 0;
  final List<String> thumbnailRequests = <String>[];

  @override
  Future<PhotoPermissionState> permission() async {
    permissionCalls += 1;
    return state;
  }

  @override
  Future<List<PhotoEntry>> load() async {
    loadCalls += 1;
    if (loadError != null) {
      throw PhotoSourceException(loadError!);
    }
    return List<PhotoEntry>.from(entries);
  }

  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 300}) async {
    thumbnailRequests.add(assetId);
    return bytes;
  }
}

/// 一个真实可解码的 1×1 PNG（测试里代替设备返回的真实字节，不是渐变占位）。
final Uint8List _tinyPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8DwHwAFAAH/VscvDQAAAABJRU5ErkJggg==',
  ),
);

List<PhotoEntry> _fourPhotos() => <PhotoEntry>[
      PhotoEntry(
        assetId: 'a',
        createdAt: DateTime(2024, 6, 1, 9, 32),
        width: 4032,
        height: 3024,
      ),
      PhotoEntry(
        assetId: 'b',
        createdAt: DateTime(2024, 6, 1, 18, 5),
        width: 0,
        height: 0,
      ),
      PhotoEntry(
        assetId: 'c',
        createdAt: DateTime(2024, 6, 3, 8, 0),
        width: 3024,
        height: 4032,
        latitude: 30.2591,
        longitude: 120.1551,
      ),
      PhotoEntry(
        assetId: 'd',
        createdAt: DateTime(2023, 12, 31, 23, 59),
        width: 1920,
        height: 1080,
      ),
    ];

FakePhotoSource _grantedSource({bool withBytes = true}) => FakePhotoSource(
      entries: _fourPhotos(),
      bytes: withBytes ? _tinyPng : null,
    );

Future<void> _pumpPage(
  WidgetTester tester,
  FakePhotoSource source, {
  StorageService? storage,
  Key? pageKey,
}) async {
  // 放大测试画布，保证 3 个日期分组的格子都在可视区内，可直接 tap。
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GalleryPage(
          key: pageKey,
          photoSource: source,
          storage: storage,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 读取带 key 控件的文案：key 可能直接挂在 Text 上，也可能挂在按钮上
/// （如 `manage-button` 是 TextButton），后者取它的后代 Text。
String? _textData(WidgetTester tester, String key) {
  final Finder finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    return null;
  }
  final Widget keyed = tester.widget<Widget>(finder);
  if (keyed is Text) {
    return keyed.data;
  }
  final Finder textFinder = find.descendant(
    of: finder,
    matching: find.byType(Text),
  );
  if (textFinder.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<Text>(textFinder.first).data;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('初始 granted：4 个真实照片格 + 3 个真实日期分组，无占位文案',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());

    for (final String id in <String>['a', 'b', 'c', 'd']) {
      expect(find.byKey(Key('photo-cell-$id')), findsOneWidget);
    }
    expect(find.text('2024-06-03'), findsOneWidget);
    expect(find.text('2024-06-01'), findsOneWidget);
    expect(find.text('2023-12-31'), findsOneWidget);
    expect(find.text('2 张'), findsOneWidget);
    expect(find.text('1 张'), findsNWidgets(2));
    expect(_textData(tester, 'manage-button'), '管理');
    // 绝不能出现原型里的假照片 / 假地点 / 未知占位
    expect(find.textContaining('示意占位'), findsNothing);
    expect(find.textContaining('未知'), findsNothing);
    expect(find.textContaining('旅行地图'), findsNothing);
  });

  testWidgets('三模式切换：chips 直达 + manage 循环',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());

    expect(find.byKey(const Key('photo-cell-a')), findsOneWidget);
    await _tapKey(tester, 'mode-select');
    expect(find.byKey(const Key('select-tray')), findsOneWidget);
    expect(_textData(tester, 'manage-button'), '信息列表');

    await _tapKey(tester, 'mode-list');
    expect(find.byKey(const Key('photo-row-a')), findsOneWidget);
    expect(find.byKey(const Key('photo-cell-a')), findsNothing);
    expect(_textData(tester, 'manage-button'), '完成');

    await _tapKey(tester, 'mode-browse');
    expect(find.byKey(const Key('photo-cell-a')), findsOneWidget);
    expect(find.byKey(const Key('photo-row-a')), findsNothing);
    expect(_textData(tester, 'manage-button'), '管理');

    // manage 按钮按原型语义：浏览 → 多选 → 信息列表
    await _tapKey(tester, 'manage-button');
    expect(_textData(tester, 'manage-button'), '信息列表');
    await _tapKey(tester, 'manage-button');
    expect(_textData(tester, 'manage-button'), '完成');
  });

  testWidgets('多选：勾选切换 + 计数实时更新 + 底部缩略图栏',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());
    await _tapKey(tester, 'mode-select');

    expect(_textData(tester, 'tray-count'), '未选择照片');
    expect(_textData(tester, 'selection-count'), '未选择照片');
    expect(find.byKey(const Key('tray-thumb-a')), findsNothing);

    await _tapKey(tester, 'photo-cell-a');
    expect(_textData(tester, 'tray-count'), '已选 1 张');
    expect(_textData(tester, 'selection-count'), '已选 1 张');
    expect(find.byKey(const Key('tray-thumb-a')), findsOneWidget);

    await _tapKey(tester, 'photo-cell-c');
    expect(_textData(tester, 'tray-count'), '已选 2 张');
    expect(_textData(tester, 'selection-count'), '已选 2 张');
    expect(find.byKey(const Key('tray-thumb-c')), findsOneWidget);

    // 再点一次 a → 取消勾选（幂等切换）
    await _tapKey(tester, 'photo-cell-a');
    expect(_textData(tester, 'tray-count'), '已选 1 张');
    expect(find.byKey(const Key('tray-thumb-a')), findsNothing);
    expect(find.byKey(const Key('tray-thumb-c')), findsOneWidget);
  });

  testWidgets('勾选跨模式保留（多选 → 信息列表 → 浏览 → 多选）',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());
    await _tapKey(tester, 'mode-select');
    await _tapKey(tester, 'photo-cell-a');
    await _tapKey(tester, 'photo-cell-c');

    await _tapKey(tester, 'mode-list');
    expect(_textData(tester, 'selection-count'), '已选 2 张');
    expect(find.byKey(const Key('selected-mark-a')), findsOneWidget);
    expect(find.byKey(const Key('selected-mark-c')), findsOneWidget);
    expect(find.byKey(const Key('unselected-mark-b')), findsOneWidget);

    await _tapKey(tester, 'mode-browse');
    expect(find.byKey(const Key('photo-cell-a')), findsOneWidget);

    await _tapKey(tester, 'mode-select');
    expect(_textData(tester, 'tray-count'), '已选 2 张');
    expect(_textData(tester, 'selection-count'), '已选 2 张');
    expect(find.byKey(const Key('tray-thumb-a')), findsOneWidget);
    expect(find.byKey(const Key('tray-thumb-c')), findsOneWidget);
  });

  testWidgets('看图：打开 / 下一张 / 上一张 / 循环 / 返回关闭',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());
    // 日期降序后 flat 顺序为 [c, a, b, d]，c 是第 1 张
    await _tapKey(tester, 'photo-cell-c');

    expect(find.byKey(const Key('photo-viewer')), findsOneWidget);
    expect(_textData(tester, 'viewer-count'), '1 / 4');

    await _tapKey(tester, 'viewer-next');
    expect(_textData(tester, 'viewer-count'), '2 / 4');

    await _tapKey(tester, 'viewer-prev');
    expect(_textData(tester, 'viewer-count'), '1 / 4');

    await _tapKey(tester, 'viewer-prev');
    expect(_textData(tester, 'viewer-count'), '4 / 4');

    await _tapKey(tester, 'viewer-next');
    expect(_textData(tester, 'viewer-count'), '1 / 4');

    await _tapKey(tester, 'viewer-close');
    expect(find.byKey(const Key('photo-viewer')), findsNothing);
  });

  testWidgets('看图：ESC 与点击背景均可关闭',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());

    await _tapKey(tester, 'photo-cell-c');
    expect(find.byKey(const Key('photo-viewer')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo-viewer')), findsNothing);

    await _tapKey(tester, 'photo-cell-a');
    expect(find.byKey(const Key('photo-viewer')), findsOneWidget);
    await _tapKey(tester, 'viewer-backdrop');
    expect(find.byKey(const Key('photo-viewer')), findsNothing);
  });

  testWidgets('看图信息：只显示真实元数据，缺失尺寸不写「未知」',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());

    // c：有真实时间 / 尺寸 / 经纬度
    await _tapKey(tester, 'photo-cell-c');
    await _tapKey(tester, 'viewer-info');
    expect(find.text('拍摄时间：2024-06-03 08:00'), findsOneWidget);
    expect(find.text('尺寸：3024×4032'), findsOneWidget);
    expect(find.text('位置：30.2591, 120.1551'), findsOneWidget);
    expect(find.text('第 1 / 4 张'), findsOneWidget);

    await _tapKey(tester, 'viewer-close');

    // b：宽高为 0 → 尺寸整行不出现，也不出现「未知」
    await _tapKey(tester, 'mode-list');
    await _tapKey(tester, 'photo-thumb-b');
    await _tapKey(tester, 'viewer-info');
    expect(find.text('拍摄时间：2024-06-01 18:05'), findsOneWidget);
    expect(find.textContaining('尺寸'), findsNothing);
    expect(find.textContaining('位置'), findsNothing);
    expect(find.textContaining('未知'), findsNothing);
  });

  testWidgets('权限 denied：明确空态，绝不是「暂无照片」，且不读相册',
      (WidgetTester tester) async {
    final FakePhotoSource source = FakePhotoSource(
      state: PhotoPermissionState.denied,
      entries: _fourPhotos(),
      bytes: _tinyPng,
    );
    await _pumpPage(tester, source);

    expect(find.text('未获得相册访问权限'), findsOneWidget);
    expect(find.textContaining('请在系统设置中允许'), findsOneWidget);
    expect(find.text('重新请求授权'), findsOneWidget);
    expect(find.text('设备相册中没有可显示的照片'), findsNothing);
    expect(find.text('暂无照片'), findsNothing);
    expect(find.byKey(const Key('photo-cell-a')), findsNothing);
    expect(source.permissionCalls, 1);
    expect(source.loadCalls, 0);
  });

  testWidgets('重新请求授权是真实动作：权限恢复后重新读取并显示照片',
      (WidgetTester tester) async {
    final FakePhotoSource source = FakePhotoSource(
      state: PhotoPermissionState.denied,
      entries: _fourPhotos(),
      bytes: _tinyPng,
    );
    await _pumpPage(tester, source);
    expect(find.text('未获得相册访问权限'), findsOneWidget);

    source.state = PhotoPermissionState.granted;
    await _tapKey(tester, 'state-action');

    expect(source.permissionCalls, 2);
    expect(source.loadCalls, 1);
    expect(find.byKey(const Key('photo-cell-a')), findsOneWidget);
    expect(find.text('未获得相册访问权限'), findsNothing);
  });

  testWidgets('granted 但零照片：空态文案与权限拒绝明确不同',
      (WidgetTester tester) async {
    await _pumpPage(
      tester,
      FakePhotoSource(state: PhotoPermissionState.granted, bytes: _tinyPng),
    );

    expect(find.text('设备相册中没有可显示的照片'), findsOneWidget);
    expect(find.text('未获得相册访问权限'), findsNothing);
    expect(find.text('无法访问设备相册'), findsNothing);
    expect(find.byKey(const Key('photo-cell-a')), findsNothing);
  });

  testWidgets('信息列表：真实拍摄时间 / 尺寸 / 位置，缺尺寸整行留空',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());
    await _tapKey(tester, 'mode-list');

    expect(_textData(tester, 'row-time-a'), '2024-06-01 09:32');
    expect(_textData(tester, 'row-size-a'), '4032×3024');
    expect(_textData(tester, 'row-time-c'), '2024-06-03 08:00');
    expect(_textData(tester, 'row-size-c'), '3024×4032');
    expect(_textData(tester, 'row-location-c'), '30.2591, 120.1551');
    expect(_textData(tester, 'row-time-b'), '2024-06-01 18:05');
    expect(find.byKey(const Key('row-size-b')), findsNothing);
    expect(find.textContaining('未知'), findsNothing);
    expect(find.textContaining('示意占位'), findsNothing);
  });

  testWidgets('完成：把所选 assetId 持久化，StorageService 能读回，下次进入恢复',
      (WidgetTester tester) async {
    final FakePhotoSource source = _grantedSource();
    final StorageService storage = StorageService();
    await _pumpPage(tester, source, storage: storage);

    await _tapKey(tester, 'mode-select');
    await _tapKey(tester, 'photo-cell-a');
    await _tapKey(tester, 'photo-cell-c');
    expect(_textData(tester, 'tray-count'), '已选 2 张');

    await _tapKey(tester, 'tray-done');

    // 用全新实例读回，证明真的写进了 SharedPreferences
    final StorageService verify = StorageService();
    await verify.init();
    final List<String> ids = await verify.getSelectedPhotoIds();
    expect(ids, <String>['a', 'c']);
    expect(ids.toSet(), <String>{'a', 'c'});
    expect(find.text('已归档 2 张'), findsOneWidget);
    expect(find.byKey(const Key('gallery-notice')), findsOneWidget);

    // 重新进入页面（换 Key 强制新 State）→ 从 getSelectedPhotoIds 读回
    await _pumpPage(
      tester,
      source,
      storage: storage,
      pageKey: const ValueKey<String>('second-entry'),
    );
    await _tapKey(tester, 'mode-select');
    expect(_textData(tester, 'selection-count'), '已选 2 张');
    expect(_textData(tester, 'tray-count'), '已选 2 张');
  });

  testWidgets('拍照按钮明确标注「原型示意」并给诚实反馈',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource());

    expect(find.text('拍照（原型示意）'), findsOneWidget);
    await _tapKey(tester, 'camera-prototype');
    expect(
      find.text('拍照入口为原型示意，暂未接入真实相机，未拍摄任何照片'),
      findsOneWidget,
    );
    // 没有新增任何照片
    expect(find.byKey(const Key('photo-cell-a')), findsOneWidget);
    expect(find.byKey(const Key('photo-cell-b')), findsOneWidget);
    expect(find.byKey(const Key('photo-cell-c')), findsOneWidget);
    expect(find.byKey(const Key('photo-cell-d')), findsOneWidget);
    expect(find.byKey(const Key('photo-cell-e')), findsNothing);
  });

  testWidgets('缩略图读取失败给明确反馈（不摆假图）',
      (WidgetTester tester) async {
    await _pumpPage(tester, _grantedSource(withBytes: false));

    expect(find.text('缩略图读取失败'), findsNWidgets(4));
    await _tapKey(tester, 'photo-cell-a');
    expect(find.text('照片读取失败，无法显示大图'), findsOneWidget);
    expect(find.textContaining('示意占位'), findsNothing);
  });
}
