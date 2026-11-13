import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/photo_entry.dart';
import 'package:trip_planner/utils/photo_selection.dart';

/// `lib/utils/photo_selection.dart` 纯函数逐条断言。
///
/// 期望值全部按规格手算（不从实现里抄），且逐条锁死边界：
/// 幂等 / 去重、按真实年月日分组且日期降序、空列表、同一天多张、
/// 重复 id、0 与负计数、缺失元数据返回空串而不是「未知」。
void main() {
  PhotoEntry entry(
    String id,
    DateTime createdAt, {
    int width = 4032,
    int height = 3024,
    double? latitude,
    double? longitude,
  }) =>
      PhotoEntry(
        assetId: id,
        createdAt: createdAt,
        width: width,
        height: height,
        latitude: latitude,
        longitude: longitude,
      );

  group('toggle 幂等 / 去重 / 不改入参', () {
    test('空集合 toggle a → {a}，且不修改入参', () {
      final Set<String> original = <String>{};
      final Set<String> result = toggle(original, 'a');
      expect(result, <String>{'a'});
      expect(original, <String>{});
      expect(identical(result, original), isFalse);
    });

    test('toggle 两次回到原集合（幂等切换）', () {
      final Set<String> once = toggle(<String>{}, 'a');
      final Set<String> twice = toggle(once, 'a');
      expect(once, <String>{'a'});
      expect(twice, <String>{});
      expect(toggle(twice, 'a'), <String>{'a'});
    });

    test('已有 a,b 时 toggle a → 只剩 b', () {
      expect(toggle(<String>{'a', 'b'}, 'a'), <String>{'b'});
    });

    test('已有 a,b 时 toggle c → a,b,c（长度 3）', () {
      final Set<String> result = toggle(<String>{'a', 'b'}, 'c');
      expect(result.length, 3);
      expect(result, <String>{'a', 'b', 'c'});
    });

    test('重复 id 不产生重复项（Set 语义）', () {
      // 用 List 构造（同一 id 出现两次），避开「集合字面量重复元素」的静态告警
      final List<String> raw = <String>['a', 'a', 'b'];
      final Set<String> input = raw.toSet();
      expect(input.length, 2);
      expect(toggle(input, 'a'), <String>{'b'});
    });
  });

  group('groupByDay 按真实 createdAt 年月日分组、日期降序', () {
    test('三天 4 张：三组、日期降序、组内保持输入顺序', () {
      final List<PhotoEntry> entries = <PhotoEntry>[
        entry('a', DateTime(2024, 6, 1, 9, 32)),
        entry('b', DateTime(2024, 6, 1, 18, 5)),
        entry('c', DateTime(2024, 6, 3, 8, 0)),
        entry('d', DateTime(2023, 12, 31, 23, 59)),
      ];
      final Map<DateTime, List<PhotoEntry>> groups = groupByDay(entries);

      expect(groups.length, 3);
      expect(groups.keys.toList(), <DateTime>[
        DateTime(2024, 6, 3),
        DateTime(2024, 6, 1),
        DateTime(2023, 12, 31),
      ]);
      expect(
        groups[DateTime(2024, 6, 1)]!.map((PhotoEntry e) => e.assetId).toList(),
        <String>['a', 'b'],
      );
      expect(
        groups[DateTime(2024, 6, 3)]!.map((PhotoEntry e) => e.assetId).toList(),
        <String>['c'],
      );
      expect(
        groups[DateTime(2023, 12, 31)]!.map((PhotoEntry e) => e.assetId).toList(),
        <String>['d'],
      );
    });

    test('同一天的时分秒不同不拆组（只看年月日）', () {
      final Map<DateTime, List<PhotoEntry>> groups = groupByDay(<PhotoEntry>[
        entry('x', DateTime(2025, 1, 1, 0, 0)),
        entry('y', DateTime(2025, 1, 1, 23, 59)),
      ]);
      expect(groups.length, 1);
      expect(groups[DateTime(2025, 1, 1)]!.length, 2);
    });

    test('空列表 → 空 Map', () {
      expect(groupByDay(<PhotoEntry>[]), isEmpty);
    });

    test('重复 assetId 只保留第一次出现（不重复渲染同一张照片）', () {
      final Map<DateTime, List<PhotoEntry>> groups = groupByDay(<PhotoEntry>[
        entry('dup', DateTime(2024, 6, 1, 9, 0)),
        entry('dup', DateTime(2024, 6, 1, 10, 0)),
        entry('other', DateTime(2024, 6, 1, 11, 0)),
      ]);
      expect(groups.length, 1);
      expect(
        groups[DateTime(2024, 6, 1)]!.map((PhotoEntry e) => e.assetId).toList(),
        <String>['dup', 'other'],
      );
    });

    test('分组不臆造地点分组（键必须是 DateTime 年月日）', () {
      final Map<DateTime, List<PhotoEntry>> groups = groupByDay(<PhotoEntry>[
        entry('a', DateTime(2024, 2, 29, 7, 8)),
      ]);
      expect(groups.keys.single, DateTime(2024, 2, 29));
      expect(groups.keys.single.hour, 0);
      expect(groups.keys.single.minute, 0);
    });
  });

  group('countLabel / archiveLabel 边界', () {
    test('0 → 明确空态文案「未选择照片」', () {
      expect(countLabel(0), '未选择照片');
    });
    test('1 → 已选 1 张', () {
      expect(countLabel(1), '已选 1 张');
    });
    test('7 → 已选 7 张（不进位、不估算）', () {
      expect(countLabel(7), '已选 7 张');
    });
    test('异常负值也按未选择处理（不显示负数）', () {
      expect(countLabel(-3), '未选择照片');
    });
    test('归档文案是真实条数', () {
      expect(archiveLabel(0), '已归档 0 张');
      expect(archiveLabel(3), '已归档 3 张');
    });
  });

  group('元数据文案：缺失留空，绝不写「未知」占位', () {
    test('正常宽高 → 4032×3024', () {
      expect(dimensionLabel(4032, 3024), '4032×3024');
    });
    test('宽为 0 → 空串', () {
      expect(dimensionLabel(0, 3024), '');
    });
    test('高为 0 → 空串', () {
      expect(dimensionLabel(4032, 0), '');
    });
    test('负数宽高 → 空串', () {
      expect(dimensionLabel(-1, -1), '');
    });
    test('缺任一坐标 → 空串', () {
      expect(locationLabel(null, 120.0), '');
      expect(locationLabel(30.0, null), '');
    });
    test('两坐标齐全 → 4 位小数', () {
      expect(locationLabel(30.2591, 120.1551), '30.2591, 120.1551');
    });
  });

  group('日期格式化：只由真实 DateTime 组成', () {
    test('formatDay 补零', () {
      expect(formatDay(DateTime(2024, 6, 3, 9, 32)), '2024-06-03');
    });
    test('formatDateTime 补零到 HH:mm', () {
      expect(formatDateTime(DateTime(2024, 6, 3, 9, 5)), '2024-06-03 09:05');
    });
    test('跨年边界', () {
      expect(formatDateTime(DateTime(2023, 12, 31, 23, 59)), '2023-12-31 23:59');
    });
  });

  group('PhotoEntry 元数据透传', () {
    test('缺失定位保持 null，尺寸 0 不算可用尺寸', () {
      final PhotoEntry e = entry('n', DateTime(2024, 1, 1), width: 0, height: 0);
      expect(e.latitude, isNull);
      expect(e.longitude, isNull);
      expect(e.hasLocation, isFalse);
      expect(e.hasDimensions, isFalse);
      expect(e.dayKey, DateTime(2024, 1, 1));
    });
    test('真实定位与尺寸可用', () {
      final PhotoEntry e = entry(
        'p',
        DateTime(2024, 1, 1),
        latitude: 30.2,
        longitude: 120.1,
      );
      expect(e.hasLocation, isTrue);
      expect(e.hasDimensions, isTrue);
    });
  });
}
