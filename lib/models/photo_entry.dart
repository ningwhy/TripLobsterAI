/// 旅行相册实体：所有字段都来自设备相册 `AssetEntity` 的真实元数据。
///
/// 红线：不得为任何字段填默认值冒充真实数据。
/// * [createdAt] 只由 `AssetEntity.createDateSecond` 换算；设备未提供拍摄时间
///   的资源会在 `DevicePhotoSource.load()` 中被跳过，因此不会构造出编造时间的实体。
/// * [latitude] / [longitude] 无定位元数据时保持 null，UI 直接留空。
/// * [width] / [height] 原样透传；0 表示设备未给出尺寸，UI 不显示尺寸文案。
class PhotoEntry {
  const PhotoEntry({
    required this.assetId,
    required this.createdAt,
    required this.width,
    required this.height,
    this.latitude,
    this.longitude,
  });

  /// 设备相册中的资源 id（`AssetEntity.id`）。
  final String assetId;

  /// 真实拍摄时间。
  final DateTime createdAt;

  /// 真实像素宽（0 表示设备未给出）。
  final int width;

  /// 真实像素高（0 表示设备未给出）。
  final int height;

  /// 真实纬度；无元数据时为 null。
  final double? latitude;

  /// 真实经度；无元数据时为 null。
  final double? longitude;

  /// 真实拍摄时间对应的「年月日」键（本地时区），用于按天分组。
  DateTime get dayKey => DateTime(createdAt.year, createdAt.month, createdAt.day);

  /// 设备是否给出了可用的宽高元数据。
  bool get hasDimensions => width > 0 && height > 0;

  /// 设备是否给出了可用的经纬度元数据。
  bool get hasLocation => latitude != null && longitude != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoEntry &&
          other.assetId == assetId &&
          other.createdAt == createdAt &&
          other.width == width &&
          other.height == height &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode =>
      Object.hash(assetId, createdAt, width, height, latitude, longitude);

  @override
  String toString() =>
      'PhotoEntry($assetId, $createdAt, ${width}x$height, '
      '${hasLocation ? '$latitude,$longitude' : 'no-location'})';
}
