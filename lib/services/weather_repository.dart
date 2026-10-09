import 'package:flutter/foundation.dart';

import '../models/day_weather.dart';
import '../models/trip_models.dart';
import '../services/api_client.dart';

/// 天气仓库：按天缓存（key = `{city}_{date}`），并发预取，单天失败不影响其他天
///
/// 【WX-04】无数据时徽章**整块隐藏**，不留空白占位。
/// 【A-8】超过 16 天预报窗口 → `DayWeather == null` → 隐藏，**不用最后一天充数**。
/// 【裁 8】坐标为空 → 不打点、不请求（null 守卫）。
class WeatherRepository extends ChangeNotifier {
  WeatherRepository();

  final Map<String, DayWeather?> _cache = <String, DayWeather?>{};
  final Map<String, bool> _pending = <String, bool>{};

  /// 取某天天气（缓存命中直接返回；未命中返回 null 并触发后台拉取）
  DayWeather? peek(TripDay day) {
    final key = _key(day);
    return _cache[key];
  }

  /// 是否正在拉取（用于显示固定尺寸占位，防抖动）
  bool isPending(TripDay day) => _pending[_key(day)] == true;

  Future<DayWeather?> get(TripDay day) async {
    final key = _key(day);
    if (_cache.containsKey(key)) return _cache[key];
    return _fetch(day);
  }

  /// 并发预取（不阻塞首屏）：按 `city+date` 去重，单天 try/catch 隔离
  Future<void> prefetch(List<TripDay> days) async {
    final todo = <TripDay>[];
    final seen = <String>{};
    for (final d in days) {
      final anchor = pickAnchor(d);
      if (anchor == null) continue; // 无可用坐标 → 该天不拉（徽章隐藏）
      final k = '${anchor.city}_${_dateStr(d.date)}';
      if (_cache.containsKey(k)) continue;
      if (!seen.add(k)) continue;
      todo.add(d);
    }
    if (todo.isEmpty) return;
    await Future.wait(todo.map((d) async {
      try {
        await _fetch(d);
      } catch (_) {
        // 单天失败静默：该天徽章整块隐藏，不影响其他天
      }
    }));
    notifyListeners();
  }

  Future<DayWeather?> _fetch(TripDay day) async {
    final key = _key(day);
    final anchor = pickAnchor(day);
    if (anchor == null) {
      _cache[key] = null;
      return null;
    }
    _pending[key] = true;
    try {
      final json = await ApiClient.weather(anchor.latitude!, anchor.longitude!);
      final w = DayWeather.fromOpenMeteoByDate(json, _dateStr(day.date));
      _cache[key] = w;
      return w;
    } catch (_) {
      _cache[key] = null; // 失败 = 无数据（徽章隐藏），不抛给 UI
      return null;
    } finally {
      _pending[key] = false;
      notifyListeners();
    }
  }

  /// 取点规则（严格按设计）：当日**最后一个 hotel** → 当日**最后一个 attraction** → 首项
  ///
  /// 【裁 8】坐标必须判空：服务端枢纽兜底可能是 `{lng:null, lat:null}`。
  Location? pickAnchor(TripDay day) {
    final locs = day.locations;
    for (var i = locs.length - 1; i >= 0; i--) {
      final l = locs[i];
      if (l.type == LocationType.hotel && _hasCoord(l)) return l;
    }
    for (var i = locs.length - 1; i >= 0; i--) {
      final l = locs[i];
      if (l.type == LocationType.attraction && _hasCoord(l)) return l;
    }
    for (final l in locs) {
      if (_hasCoord(l)) return l;
    }
    return null;
  }

  static bool _hasCoord(Location l) =>
      l.latitude != null && l.longitude != null;

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _key(TripDay day) {
    final anchor = pickAnchor(day);
    final city = anchor?.city ?? (day.locations.isNotEmpty ? day.locations.first.city : '') ?? '';
    return '${city}_${_dateStr(day.date)}';
  }
}
