import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../models/photo_entry.dart';

/// 设备相册权限状态。UI 按状态显示不同空态，
/// **绝不把「无权限」显示成「暂无照片」**。
enum PhotoPermissionState {
  /// 完整访问权限。
  granted,

  /// 仅可访问用户选中的照片（iOS limited）；仍可读取真实元数据。
  limited,

  /// 用户拒绝 / 受限 / 尚未授权：拿不到任何照片。
  denied,

  /// 平台不支持或调用出错，相册能力不可用。
  unavailable,
}

/// 数据源异常：不吞异常、不把失败伪装成「没有照片」。
class PhotoSourceException implements Exception {
  const PhotoSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 相册数据源抽象。
///
/// 缩略图返回字节而不是 Widget，保持 services 层不依赖 widget；
/// 测试可注入 FakePhotoSource，完全不触碰真实设备相册。
abstract class PhotoSource {
  const PhotoSource();

  /// 查询（并按需请求）相册权限。
  Future<PhotoPermissionState> permission();

  /// 读取全部照片的真实元数据；无权限时抛 [PhotoSourceException]。
  Future<List<PhotoEntry>> load();

  /// 读取指定资源的真实缩略图字节；资源不存在返回 null，出错抛 [PhotoSourceException]。
  Future<Uint8List?> thumbnail(String assetId, {int size = 300});
}

/// 真实设备相册实现（photo_manager 3.x）。
///
/// 数据来源全部是 `AssetEntity` 的真实字段：
/// `id` / `createDateSecond` / `width` / `height` / `latLng`。
/// 没有真实拍摄时间的资源会被跳过，而不是用 epoch 或当前时间冒充。
class DevicePhotoSource extends PhotoSource {
  const DevicePhotoSource();

  static const int _pageSize = 200;

  static bool _canRead(PhotoPermissionState state) =>
      state == PhotoPermissionState.granted ||
      state == PhotoPermissionState.limited;

  @override
  Future<PhotoPermissionState> permission() async {
    final PermissionState state;
    try {
      state = await PhotoManager.requestPermissionExtend();
    } catch (error) {
      throw PhotoSourceException('无法请求设备相册权限：$error');
    }
    switch (state) {
      case PermissionState.authorized:
        return PhotoPermissionState.granted;
      case PermissionState.limited:
        return PhotoPermissionState.limited;
      case PermissionState.denied:
      case PermissionState.restricted:
      case PermissionState.notDetermined:
        return PhotoPermissionState.denied;
    }
  }

  @override
  Future<List<PhotoEntry>> load() async {
    final PhotoPermissionState state = await permission();
    if (!_canRead(state)) {
      throw const PhotoSourceException('未获得相册访问权限，无法读取照片');
    }

    final List<AssetPathEntity> paths;
    try {
      paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
      );
    } catch (error) {
      throw PhotoSourceException('读取相册目录失败：$error');
    }
    // onlyAll=true 且确实没有图片相册 → 真实的「没有照片」。
    if (paths.isEmpty) {
      return <PhotoEntry>[];
    }

    final AssetPathEntity allPhotos = paths.first;
    final int total;
    try {
      total = await allPhotos.assetCountAsync;
    } catch (error) {
      throw PhotoSourceException('读取相册数量失败：$error');
    }

    final List<PhotoEntry> result = <PhotoEntry>[];
    final Set<String> seen = <String>{};
    var page = 0;
    while (true) {
      final List<AssetEntity> assets;
      try {
        assets = await allPhotos.getAssetListPaged(page: page, size: _pageSize);
      } catch (error) {
        throw PhotoSourceException('读取第 $page 页照片失败：$error');
      }
      if (assets.isEmpty) {
        break;
      }
      for (final AssetEntity asset in assets) {
        final int? createdSecond = asset.createDateSecond;
        // 没有真实拍摄时间 → 不编造 epoch / 当前时间，直接跳过该资源。
        if (createdSecond == null || createdSecond <= 0) {
          continue;
        }
        if (!seen.add(asset.id)) {
          continue;
        }
        final LatLng? latLng = asset.latLng;
        result.add(
          PhotoEntry(
            assetId: asset.id,
            createdAt: DateTime.fromMillisecondsSinceEpoch(createdSecond * 1000),
            width: asset.width,
            height: asset.height,
            latitude: latLng?.latitude,
            longitude: latLng?.longitude,
          ),
        );
      }
      if (assets.length < _pageSize) {
        break;
      }
      // 防越界：已取满总数后不再翻页。
      if ((page + 1) * _pageSize >= total) {
        break;
      }
      page += 1;
    }
    return result;
  }

  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 300}) async {
    final AssetEntity? entity;
    try {
      entity = await AssetEntity.fromId(assetId);
    } catch (error) {
      throw PhotoSourceException('读取照片 $assetId 失败：$error');
    }
    if (entity == null) {
      return null;
    }
    try {
      return await entity.thumbnailDataWithSize(ThumbnailSize.square(size));
    } catch (error) {
      throw PhotoSourceException('生成照片 $assetId 缩略图失败：$error');
    }
  }
}
