import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/photo_entry.dart';
import '../../services/photo_source.dart';
import '../../utils/photo_selection.dart';

/// 设计系统主色「章鱼紫」（见 ui-octopus.css）。本文件不 import 并行批次正在
/// 修改的 theme 文件，避免写冲突；颜色只用于选中角标等局部强调。
const Color _kPrimary = Color(0xFF7C6DF7);
const Color _kInk = Color(0xFF1F2430);
const Color _kSub = Color(0xFF6B7280);
const Color _kLine = Color(0xFFE7E9EF);
const Color _kPlaceholder = Color(0xFFE9EBEF);

/// 相册三种互斥模式（原型 `:126-128` / `:460-473`）。
enum GalleryMode { browse, select, list }

/// 真实缩略图加载器：从 [PhotoSource] 取字节，不渲染任何假图 / 渐变占位。
/// 内部缓存 Future，避免每次 rebuild 都重新读设备相册。
class PhotoThumb extends StatefulWidget {
  const PhotoThumb({
    super.key,
    required this.source,
    required this.assetId,
    this.size = 300,
    this.fit = BoxFit.cover,
    this.placeholderColor = _kPlaceholder,
    this.failureLabel = '缩略图读取失败',
  });

  final PhotoSource source;
  final String assetId;
  final int size;
  final BoxFit fit;
  final Color placeholderColor;
  final String failureLabel;

  @override
  State<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<PhotoThumb> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.source.thumbnail(widget.assetId, size: widget.size);
  }

  @override
  void didUpdateWidget(PhotoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId ||
        oldWidget.size != widget.size ||
        oldWidget.source != widget.source) {
      _future = widget.source.thumbnail(widget.assetId, size: widget.size);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ColoredBox(
            color: widget.placeholderColor,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _ThumbFailure(
            text: '加载失败：${snapshot.error}',
            color: widget.placeholderColor,
          );
        }
        final Uint8List? bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _ThumbFailure(
            text: widget.failureLabel,
            color: widget.placeholderColor,
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              _ThumbFailure(
                text: widget.failureLabel,
                color: widget.placeholderColor,
              ),
        );
      },
    );
  }
}

/// 加载失败时的明确反馈（中性底色 + 文字，绝不用渐变假装照片）。
class _ThumbFailure extends StatelessWidget {
  const _ThumbFailure({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: _kSub),
          ),
        ),
      ),
    );
  }
}

/// 三模式相册主体：浏览 / 多选共用 3 列网格，信息列表用行。
/// 所有展示的日期、时间、尺寸、位置均来自 [PhotoEntry] 的真实元数据。
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({
    super.key,
    required this.groups,
    required this.mode,
    required this.selected,
    required this.source,
    required this.onOpen,
    required this.onToggle,
  });

  final Map<DateTime, List<PhotoEntry>> groups;
  final GalleryMode mode;
  final Set<String> selected;
  final PhotoSource source;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      key: const Key('photo-list'),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: groups.length,
      itemBuilder: (BuildContext context, int index) {
        final DateTime day = groups.keys.elementAt(index);
        final List<PhotoEntry> photos = groups[day]!;
        return _DaySection(
          day: day,
          photos: photos,
          mode: mode,
          selected: selected,
          source: source,
          onOpen: onOpen,
          onToggle: onToggle,
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.photos,
    required this.mode,
    required this.selected,
    required this.source,
    required this.onOpen,
    required this.onToggle,
  });

  final DateTime day;
  final List<PhotoEntry> photos;
  final GalleryMode mode;
  final Set<String> selected;
  final PhotoSource source;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Row(
            children: <Widget>[
              Text(
                formatDay(day),
                key: Key('day-header-${formatDay(day)}'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${photos.length} 张',
                style: const TextStyle(fontSize: 11, color: _kSub),
              ),
            ],
          ),
        ),
        if (mode == GalleryMode.list)
          _InfoList(
            photos: photos,
            selected: selected,
            source: source,
            onOpen: onOpen,
            onToggle: onToggle,
          )
        else
          _ThreeColumnGrid(
            photos: photos,
            selectable: mode == GalleryMode.select,
            selected: selected,
            source: source,
            onOpen: onOpen,
            onToggle: onToggle,
          ),
      ],
    );
  }
}

class _ThreeColumnGrid extends StatelessWidget {
  const _ThreeColumnGrid({
    required this.photos,
    required this.selectable,
    required this.selected,
    required this.source,
    required this.onOpen,
    required this.onToggle,
  });

  final List<PhotoEntry> photos;
  final bool selectable;
  final Set<String> selected;
  final PhotoSource source;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (BuildContext context, int index) {
        final PhotoEntry entry = photos[index];
        final bool isSelected = selected.contains(entry.assetId);
        return GestureDetector(
          key: Key('photo-cell-${entry.assetId}'),
          onTap: () =>
              selectable ? onToggle(entry.assetId) : onOpen(entry.assetId),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PhotoThumb(source: source, assetId: entry.assetId),
              if (selectable)
                Positioned(
                  right: 5,
                  top: 5,
                  child: _CheckBadge(
                    key: Key('cell-check-${entry.assetId}'),
                    selected: isSelected,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _kPrimary : const Color(0x66000000),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : const SizedBox.shrink(),
    );
  }
}

/// 信息列表：缩略图 + 真实拍摄时间 + 真实尺寸（缺失则留空，不写「未知」）。
class _InfoList extends StatelessWidget {
  const _InfoList({
    required this.photos,
    required this.selected,
    required this.source,
    required this.onOpen,
    required this.onToggle,
  });

  final List<PhotoEntry> photos;
  final Set<String> selected;
  final PhotoSource source;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final PhotoEntry entry in photos) _infoRow(entry),
      ],
    );
  }

  Widget _infoRow(PhotoEntry entry) {
    final bool isSelected = selected.contains(entry.assetId);
    final String dimensions = dimensionLabel(entry.width, entry.height);
    final String location = locationLabel(entry.latitude, entry.longitude);
    return InkWell(
      key: Key('photo-row-${entry.assetId}'),
      onTap: () => onToggle(entry.assetId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kLine)),
        ),
        child: Row(
          children: <Widget>[
            GestureDetector(
              key: Key('photo-thumb-${entry.assetId}'),
              onTap: () => onOpen(entry.assetId),
              child: SizedBox(
                width: 56,
                height: 56,
                child: PhotoThumb(
                  source: source,
                  assetId: entry.assetId,
                  size: 160,
                  failureLabel: '照片读取失败',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    formatDateTime(entry.createdAt),
                    key: Key('row-time-${entry.assetId}'),
                    style: const TextStyle(fontSize: 13, color: _kInk),
                  ),
                  if (dimensions.isNotEmpty)
                    Text(
                      dimensions,
                      key: Key('row-size-${entry.assetId}'),
                      style: const TextStyle(fontSize: 11, color: _kSub),
                    ),
                  if (location.isNotEmpty)
                    Text(
                      location,
                      key: Key('row-location-${entry.assetId}'),
                      style: const TextStyle(fontSize: 11, color: _kSub),
                    ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              key: Key(isSelected
                  ? 'selected-mark-${entry.assetId}'
                  : 'unselected-mark-${entry.assetId}'),
              size: 22,
              color: isSelected ? _kPrimary : const Color(0xFFB9BDC7),
            ),
          ],
        ),
      ),
    );
  }
}
