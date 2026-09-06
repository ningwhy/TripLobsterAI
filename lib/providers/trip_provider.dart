import 'package:flutter/foundation.dart';
import '../models/trip_models.dart';
import '../services/storage_service.dart';
import '../services/api_client.dart';

class TripProvider extends ChangeNotifier {
  final StorageService _storage;

  List<Trip> _trips = [];
  Trip? _currentTrip;
  HomeLocation? _homeLocation;
  List<Footprint> _footprints = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _lastSyncError;
  int _lastSyncAt = 0;

  TripProvider(this._storage);

  List<Trip> get trips => _trips;
  Trip? get currentTrip => _currentTrip;
  HomeLocation? get homeLocation => _homeLocation;
  List<Footprint> get footprints => _footprints;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get lastSyncError => _lastSyncError;
  int get lastSyncAt => _lastSyncAt;

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    _trips = await _storage.getTrips();
    _homeLocation = await _storage.getHomeLocation();
    _footprints = await _storage.getFootprints();
    _lastSyncAt = await _storage.getLastSync();

    _isLoading = false;
    notifyListeners();
  }

  // 行程管理（保存时刷 updatedAt，供云同步 LWW）
  Future<void> createTrip(Trip trip) async {
    trip.updatedAt = DateTime.now();
    await _storage.saveTrip(trip);
    _trips = await _storage.getTrips();
    notifyListeners();
  }

  Future<void> updateTrip(Trip trip) async {
    trip.updatedAt = DateTime.now();
    await _storage.saveTrip(trip);
    _trips = await _storage.getTrips();
    if (_currentTrip?.id == trip.id) {
      _currentTrip = trip;
    }
    notifyListeners();
  }

  Future<void> deleteTrip(String tripId) async {
    await _storage.deleteTrip(tripId);
    _trips = await _storage.getTrips();
    if (_currentTrip?.id == tripId) {
      _currentTrip = null;
    }
    notifyListeners();
  }

  // ---------- 云同步 ----------
  /// 返回 null 表示成功，否则为错误信息
  Future<String?> syncNow({bool silent = false}) async {
    final token = await ApiClient.token;
    if (token == null) {
      if (!silent) return '尚未登录云同步账号';
      return null;
    }
    if (_isSyncing) return null;
    _isSyncing = true;
    _lastSyncError = null;
    notifyListeners();
    try {
      // 1. 推送本地
      final tripsPayload = _trips
          .map((t) => {
                'tripId': t.id,
                'data': t.toJson(),
                'updatedAt': t.updatedAt.millisecondsSinceEpoch,
              })
          .toList();
      final deletedMap = await _storage.getDeletedTrips();
      final deletedPayload = deletedMap.entries.map((e) => {'tripId': e.key, 'deletedAt': e.value}).toList();
      await ApiClient.push(tripsPayload, deletedPayload);

      // 2. 拉取远端
      final since = await _storage.getLastSync();
      final remote = await ApiClient.pull(since: since);
      final byId = {for (final t in _trips) t.id: t};

      for (final item in (remote['trips'] as List? ?? [])) {
        final data = Map<String, dynamic>.from(item['data'] as Map);
        final remoteMs = (item['updatedAt'] as num).toInt();
        final id = data['id'] as String?;
        if (id == null) continue;
        // 本地已删除且墓碑更新，忽略远端旧版本
        final tomb = deletedMap[id];
        if (tomb != null && tomb > remoteMs) continue;
        final local = byId[id];
        if (local == null || remoteMs > local.updatedAt.millisecondsSinceEpoch) {
          final trip = Trip.fromJson(data);
          trip.updatedAt = DateTime.fromMillisecondsSinceEpoch(remoteMs);
          byId[id] = trip;
          await _storage.saveTrip(trip);
        }
      }

      for (final d in (remote['deleted'] as List? ?? [])) {
        final id = d['tripId'] as String?;
        final at = (d['deletedAt'] as num).toInt();
        if (id == null) continue;
        final local = byId[id];
        if (local != null && at > local.updatedAt.millisecondsSinceEpoch) {
          await _storage.removeTripLocal(id);
          byId.remove(id);
        }
      }

      final serverTime = (remote['serverTime'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      await _storage.setLastSync(serverTime);
      _lastSyncAt = serverTime;
      _trips = await _storage.getTrips();
      if (_currentTrip != null && !byId.containsKey(_currentTrip!.id)) {
        _currentTrip = null;
      }
      return null;
    } on ApiException catch (e) {
      _lastSyncError = e.message;
      return e.message;
    } catch (e) {
      _lastSyncError = '同步失败: $e';
      return '同步失败';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 启动时静默自动同步（已登录才同步）
  Future<void> autoSync() async {
    await syncNow(silent: true);
  }

  void setCurrentTrip(Trip? trip) {
    _currentTrip = trip;
    notifyListeners();
  }

  // 家设置
  Future<void> setHomeLocation(HomeLocation location) async {
    await _storage.saveHomeLocation(location);
    _homeLocation = location;
    notifyListeners();
  }

  // 足迹记录
  Future<void> addFootprint(Footprint footprint) async {
    await _storage.saveFootprint(footprint);
    _footprints = await _storage.getFootprints();
    notifyListeners();
  }

  /// 检查两个地点是否需要跨城交通
  /// 返回 true 表示需要弹出交通选择弹窗
  bool needsInterCityTransport(Location? previousLocation, Location newLocation) {
    if (previousLocation == null) return false;
    return previousLocation.city != newLocation.city;
  }

  /// 为行程添加跨城交通
  /// 自动添加：家 -> 机场/车站 -> 目的地机场/车站 -> 酒店
  List<Location> addInterCityTransport(
    Location fromLocation,
    Location toLocation,
    Transport transport,
  ) {
    final List<Location> result = [];

    // TODO: 调用高德API获取机场/车站信息
    // 这里简化处理，实际需要根据城市获取最近机场/车站

    // 添加起点
    result.add(fromLocation);

    // 如果是大交通，添加交通枢纽
    if (transport.isBigTransport) {
      // 添加出发城市交通枢纽
      result.add(Location(
        name: '出发地交通枢纽',
        address: '${fromLocation.city}交通枢纽',
        type: LocationType.transport,
        isAutoAdded: true,
      ));

      // 添加到达城市交通枢纽
      result.add(Location(
        name: '到达地交通枢纽',
        address: '${toLocation.city}交通枢纽',
        type: LocationType.transport,
        isAutoAdded: true,
      ));
    }

    // 添加目的地
    result.add(toLocation);

    return result;
  }
}
