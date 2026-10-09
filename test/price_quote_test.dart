import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/models/price_quote.dart';

void main() {
  group('PriceRange.fromAmapCost 脏数据防御【裁 6】', () {
    test('① 区间 "300-500"', () {
      final r = PriceRange.fromAmapCost('300-500')!;
      expect(r.low, 300);
      expect(r.high, 500);
      expect(r.text, '¥300–500');
    });

    test('② 单值 "300"（餐饮常见形态）', () {
      final r = PriceRange.fromAmapCost('300')!;
      expect(r.low, 300);
      expect(r.high, 300);
      expect(r.text, '¥300');
    });

    test('③ 两位小数 "544.00"（FX-06a 实测餐饮人均价形态）', () {
      final r = PriceRange.fromAmapCost('544.00')!;
      expect(r.low, 544);
      expect(r.high, 544);
    });

    test('④ 千分位 "1,200" 剥逗号 → 1200（不是 ¥1）', () {
      final r = PriceRange.fromAmapCost('1,200')!;
      expect(r.low, 1200);
    });

    test('⑤ 千分位区间 "1,200-1,500"', () {
      final r = PriceRange.fromAmapCost('1,200-1,500')!;
      expect(r.low, 1200);
      expect(r.high, 1500);
    });

    test('⑥ low < 20 → 脏数据 null', () {
      expect(PriceRange.fromAmapCost('1'), isNull);
      expect(PriceRange.fromAmapCost('19'), isNull);
    });

    test('⑦ high < low（区间倒置）→ null', () {
      expect(PriceRange.fromAmapCost('500-100'), isNull);
    });

    test('⑧ 空 / null / 非数字 → null', () {
      expect(PriceRange.fromAmapCost(null), isNull);
      expect(PriceRange.fromAmapCost(''), isNull);
      expect(PriceRange.fromAmapCost('abc'), isNull);
    });

    test('⑨ 空数组形态（FX-06a 实测酒店 cost=[]）经 String 化后也判空', () {
      // 服务端用 String(biz_ext.cost || '') → '[]' 不是数字
      expect(PriceRange.fromAmapCost('[]'), isNull);
    });
  });

  group('PriceQuote.fromJson 结构对齐', () {
    final json = {
      'kind': 'hotel',
      'name': '某酒店',
      'city': '威海',
      'poi': {
        'name': '某酒店',
        'address': 'a',
        'latitude': 37.5,
        'longitude': 122.1,
        'rating': 4.6,
        'reference': {'low': 300, 'high': 500, 'currency': 'CNY'},
        'source': 'amap-static',
      },
      'candidates': [
        {
          'name': '某酒店',
          'rating': 4.6,
          'reference': {'low': 300, 'high': 500, 'currency': 'CNY'},
          'source': 'amap-static',
        },
        {
          'name': '另一家',
          'rating': 4.2,
          'reference': {'low': 1, 'high': 1200, 'currency': 'CNY'},
          'source': 'amap-static',
        },
        {'name': '无价家', 'rating': 4.0, 'reference': null, 'source': 'amap-static'},
      ],
      'reference': {'low': 300, 'high': 500, 'currency': 'CNY'},
      'realTime': {
        'available': false,
        'provider': 'ctrip-union (P0-5 预留)',
        'deepLink': 'https://m.ctrip.com/webapp/hotel/',
        'note': 'OTA 反爬',
      },
      'source': 'amap-static',
      'fetchedAt': DateTime.now().toIso8601String(),
      'fetchedAtText': '截至 10:30',
      'warning': null,
    };

    test('① 顶层 reference 正常解析', () {
      final q = PriceQuote.fromJson(Map<String, dynamic>.from(json));
      expect(q.hasReference, isTrue);
      expect(q.reference!.text, '¥300–500');
      expect(q.isDirty, isFalse);
    });

    test('② 脏候选的 reference 被丢弃', () {
      final q = PriceQuote.fromJson(Map<String, dynamic>.from(json));
      expect(q.candidates[1].reference, isNull);
      expect(q.candidates[1].hasPrice, isFalse);
    });

    test('③ 无价候选 reference 为 null', () {
      final q = PriceQuote.fromJson(Map<String, dynamic>.from(json));
      expect(q.candidates[2].reference, isNull);
    });

    test('④ 比价卡只用 candidates（禁止顶层 poi + reference 拼接）', () {
      final q = PriceQuote.fromJson(Map<String, dynamic>.from(json));
      expect(q.candidates.length, 3);
      expect(q.candidates[0].name, '某酒店');
      expect(q.candidates[0].reference!.low, 300); // 各自带自己的价
    });

    test('⑤ realTime.available 恒 false（不做"实时价加载中"态）', () {
      final q = PriceQuote.fromJson(Map<String, dynamic>.from(json));
      expect(q.realTime.available, isFalse);
    });

    test('⑥ 顶层脏价 → reference null 且 isDirty', () {
      final q = PriceQuote.fromJson({
        'reference': {'low': 5, 'high': 900, 'currency': 'CNY'},
      });
      expect(q.isDirty, isTrue);
      expect(q.reference, isNull);
    });

    test('⑦ 缓存新鲜度（7 天 TTL）', () {
      final fresh = PriceQuote.fromJson({
        'fetchedAt': DateTime.now().toIso8601String(),
      });
      expect(fresh.isStale(const Duration(days: 7)), isFalse);
      final old = PriceQuote.fromJson({
        'fetchedAt': DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
      });
      expect(old.isStale(const Duration(days: 7)), isTrue);
      expect(const PriceQuote().isStale(const Duration(days: 7)), isTrue);
    });

    test('⑧ 缺字段不崩（服务端只回 error 时）', () {
      final q = PriceQuote.fromJson(<String, dynamic>{});
      expect(q.candidates, isEmpty);
      expect(q.reference, isNull);
      expect(q.hasCandidates, isFalse);
    });
  });
}
