import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_models.dart';

class StorageService {
  static const String _tripsKey = 'trips';
  static const String _homeLocationKey = 'home_location';
  static const String _footprintsKey = 'footprints';
  static const String _settingsKey = 'settings';
  static const String _deletedTripsKey = 'deleted_trips';
  static const String _lastSyncKey = 'last_sync_ms';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // 行程相关
  Future<List<Trip>> getTrips() async {
    final String? data = _prefs.getString(_tripsKey);
    if (data == null) return [];
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((e) => Trip.fromJson(e)).toList();
  }

  Future<void> saveTrips(List<Trip> trips) async {
    final String data = jsonEncode(trips.map((e) => e.toJson()).toList());
    await _prefs.setString(_tripsKey, data);
  }

  Future<void> saveTrip(Trip trip) async {
    final trips = await getTrips();
    final index = trips.indexWhere((t) => t.id == trip.id);
    if (index >= 0) {
      trips[index] = trip;
    } else {
      trips.add(trip);
    }
    await saveTrips(trips);
  }

  Future<void> deleteTrip(String tripId) async {
    final trips = await getTrips();
    trips.removeWhere((t) => t.id == tripId);
    await saveTrips(trips);
    await addDeletedTrip(tripId);
  }

  // 删除墓碑（云同步 LWW 用）
  Future<Map<String, int>> getDeletedTrips() async {
    final data = _prefs.getString(_deletedTripsKey);
    if (data == null) return {};
    final map = jsonDecode(data) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<void> addDeletedTrip(String tripId) async {
    final map = await getDeletedTrips();
    map[tripId] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_deletedTripsKey, jsonEncode(map));
  }

  // 同步水位
  Future<int> getLastSync() async => _prefs.getInt(_lastSyncKey) ?? 0;

  Future<void> setLastSync(int ms) async => _prefs.setInt(_lastSyncKey, ms);

  // 本地移除但不记墓碑（同步时远端墓碑下行）
  Future<void> removeTripLocal(String tripId) async {
    final trips = await getTrips();
    trips.removeWhere((t) => t.id == tripId);
    await saveTrips(trips);
  }

  // 家设置
  Future<HomeLocation?> getHomeLocation() async {
    final String? data = _prefs.getString(_homeLocationKey);
    if (data == null) return null;
    return HomeLocation.fromJson(jsonDecode(data));
  }

  Future<void> saveHomeLocation(HomeLocation location) async {
    await _prefs.setString(_homeLocationKey, jsonEncode(location.toJson()));
  }

  // 足迹记录
  Future<List<Footprint>> getFootprints() async {
    final String? data = _prefs.getString(_footprintsKey);
    if (data == null) return [];
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((e) => Footprint.fromJson(e)).toList();
  }

  Future<void> saveFootprint(Footprint footprint) async {
    final footprints = await getFootprints();
    // 检查是否已存在该城市
    final index = footprints.indexWhere(
      (f) => f.city == footprint.city && f.province == footprint.province,
    );
    if (index >= 0) {
      // 更新已有足迹
      final existing = footprints[index];
      footprints[index] = Footprint(
        id: existing.id,
        city: existing.city,
        province: existing.province,
        latitude: existing.latitude,
        longitude: existing.longitude,
        visitedAt: footprint.visitedAt,
        visitCount: existing.visitCount + 1,
      );
    } else {
      footprints.add(footprint);
    }
    final String data = jsonEncode(footprints.map((e) => e.toJson()).toList());
    await _prefs.setString(_footprintsKey, data);
  }

  // 设置
  Future<Map<String, dynamic>> getSettings() async {
    final String? data = _prefs.getString(_settingsKey);
    if (data == null) return {};
    return jsonDecode(data);
  }

  Future<void> saveSetting(String key, dynamic value) async {
    final settings = await getSettings();
    settings[key] = value;
    await _prefs.setString(_settingsKey, jsonEncode(settings));
  }
}
