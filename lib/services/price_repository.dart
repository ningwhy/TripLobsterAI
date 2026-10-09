import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/price_quote.dart';
import '../models/trip_models.dart';
import '../services/api_client.dart';
import '../services/price_source.dart';
import '../theme/preview_theme.dart';
import '../utils/cost_aggregator.dart';

/// 价格仓库：内存 + SharedPreferences 双层缓存（7 天过期）
///
/// 【裁 10】价格**不进 Trip.toJson**、不云同步，走本地 KV（PRD Q4-A）。
/// 【M9】**首屏 0 次网络请求**：只在用户点「🔄 刷新参考价」时才打 `/api/planner/prices`。
///
/// 【PR-10】本类**不含任何数据源语义** —— "查谁 / 用什么 kind / 结果算不算数"全部由
/// 构造注入的 `PriceSource` 决定。OTA 接入时本类零改动。
///
/// 【FX-06a 探针实测】酒店 / 景点 `biz_ext.cost` **0/20 全空** →
/// 刷新**只请求餐饮**；酒店与门票**永久 0 次请求**（拉回来也是空，纯烧高德配额，
/// 禁止"先拉一次试试"的兜底）。
class PriceRepository extends ChangeNotifier {
  /// [source] 价格数据源（默认高德参考价；将来切 OTA 只换实现，不改本类）
  PriceRepository({PriceSource source = const AmapReferencePriceSource()})
      : _source = source;

  final PriceSource _source;

  /// 缓存有效期（7 天，PRD Q4-A）
  static const Duration ttl = Duration(days: 7);

  /// 批量刷新并发上限（防打爆高德配额）
  static const int maxConcurrency = 4;

  final Map<String, PriceQuote> _mem = <String, PriceQuote>{};
  SharedPreferences? _prefs;

  String _status = '';
  bool _loading = false;

  /// 状态行文案（⏳ / ✅ / ❌）
  String get refreshStatus => _status;

  /// 是否正在刷新（按钮置灰）
  bool get isLoading => _loading;

  /// 当前缓存快照（供 CostAggregator 读取；key = `price:{city}:{name}`）
  Map<String, PriceQuote> get snapshot => Map<String, PriceQuote>.unmodifiable(_mem);

  /// 数据源标识（透传，供页面/埋点读取）
  String get sourceId => _source.id;

  /// 读一条**新鲜**缓存（内存 → 磁盘），过期则返回 null。
  ///
  /// 只被 `refreshTrip` 用来"跳过不必再拉的项目"，不直接对外提供查询
  /// （页面唯一入口是 `refreshTrip` + `snapshot`，避免各处各写一份取数逻辑）。
  Future<PriceQuote?> _freshCacheOf(String key) async {
    final hitMem = _mem[key];
    if (hitMem != null) {
      if (!hitMem.isStale(ttl)) return hitMem;
      return null;
    }
    final disk = await _readDisk(key);
    if (disk == null || disk.isStale(ttl)) return null;
    _mem[key] = disk; // 回填内存，避免同一会话内重复读盘
    return disk;
  }

  /// 强制走网络；失败抛 ApiException（调用方决定降级）
  Future<PriceQuote> fetch({
    required String city,
    required String name,
    required String kind,
  }) async {
    final json = await ApiClient.lookupPrice(city: city, name: name, kind: kind);
    final q = PriceQuote.fromJson(json);
    final key = PriceRepositoryKey.of(city, name);
    _mem[key] = q;
    await _writeDisk(key, q);
    return q;
  }

  /// 批量刷新整条行程（去重 + 并发上限 + 失败沿用旧值，不清空已有徽章）
  ///
  /// **只对 `PriceSource.requestKindFor()` 返回非 null 的地点发请求**（本轮 = 仅餐饮）。
  /// 返回成功条数。
  Future<int> refreshTrip(Trip trip) async {
    if (_loading) return 0;
    _loading = true;
    _status = PreviewStrings.refreshing;
    notifyListeners();

    final tasks = <_PriceTask>[];
    final seen = <String>{};
    var fresh = 0; // 命中新鲜缓存 → 跳过（7 天 TTL 的意义：省配额）
    for (final loc in trip.allLocations) {
      // ⛔ 数据源说不需要请求 → 一个包都不发（酒店 / 景点 / 跨城班次）
      final kind = _source.requestKindFor(loc);
      if (kind == null) continue;
      final key = PriceRepositoryKey.of(loc.city, loc.name);
      if (!seen.add(key)) continue;
      if (await _freshCacheOf(key) != null) {
        fresh++;
        continue;
      }
      tasks.add(_PriceTask(city: loc.city ?? '', name: loc.name, kind: kind));
    }

    var ok = 0;
    for (var i = 0; i < tasks.length; i += maxConcurrency) {
      final batch = tasks.skip(i).take(maxConcurrency).toList();
      final results = await Future.wait(
        batch.map((t) async {
          try {
            return await fetch(city: t.city, name: t.name, kind: t.kind);
          } catch (_) {
            return null; // 单项失败：沿用旧值，不清空
          }
        }),
      );
      for (var k = 0; k < results.length; k++) {
        final r = results[k];
        if (r == null) continue;
        // A-11：`kind='ticket'` 走泛搜索，可能命中同名/近似的**另一个 POI** → 一律不用
        if (!_source.matchesSubject(r, batch[k].name)) continue;
        // 服务端可能返回了条目但没有参考价（hasReference == false）。
        // 该情形在下游 CostAggregator 里按"缺失项"计数（missingCount），
        // 此处不另设计数器，避免出现无人消费的死变量。
        ok++;
      }
    }

    _loading = false;
    if (tasks.isEmpty && fresh == 0) {
      // 真·无可刷新项（例如全程没有餐饮点）
      _status = PreviewStrings.refreshNone;
    } else if (ok == 0 && fresh == 0) {
      // 全军覆没：§7.6 要求失败也保留后半句口径说明，仅在前面加前缀
      _status = PreviewStrings.refreshStatusLine(failed: true);
    } else {
      _status = PreviewStrings.refreshStatusLine(failed: false);
    }
    notifyListeners();
    return ok + fresh;
  }

  // ---------------- 本地 KV ----------------
  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<PriceQuote?> _readDisk(String key) async {
    try {
      await _ensurePrefs();
      final raw = _prefs!.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PriceQuote.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String key, PriceQuote q) async {
    try {
      await _ensurePrefs();
      await _prefs!.setString(key, jsonEncode(q.toCacheJson()));
    } catch (_) {
      // 写入失败不影响内存缓存与 UI
    }
  }
}

/// 批量刷新任务（内部用）
class _PriceTask {
  final String city;
  final String name;
  final String kind;
  const _PriceTask({required this.city, required this.name, required this.kind});
}
