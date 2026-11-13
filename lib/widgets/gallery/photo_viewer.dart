import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/photo_entry.dart';
import '../../services/photo_source.dart';
import '../../utils/photo_selection.dart';
import 'photo_grid.dart' show PhotoThumb;

const Color _kViewerBg = Color(0xFF111318);
const Color _kViewerPanel = Color(0xFF1B1E26);

/// 深色全屏看图 overlay（由 GalleryPage 放进 Stack，**非独立路由**）。
///
/// * 上一张 / 下一张由外部回调驱动并循环；
/// * 信息按钮只显示 [PhotoEntry] 的真实元数据，缺失字段直接不显示；
/// * ESC 与点击背景关闭；缩略图/大图读取失败给明确文字反馈。
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.entry,
    required this.index,
    required this.total,
    required this.source,
    required this.onClose,
    required this.onPrevious,
    required this.onNext,
  });

  final PhotoEntry entry;
  final int index;
  final int total;
  final PhotoSource source;
  final VoidCallback onClose;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  bool _showInfo = false;

  @override
  Widget build(BuildContext context) {
    final PhotoEntry entry = widget.entry;
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        key: const Key('viewer-backdrop'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: ColoredBox(
          color: _kViewerBg,
          child: SafeArea(
            child: Column(
              children: <Widget>[
                _buildTopBar(entry),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: PhotoThumb(
                      source: widget.source,
                      assetId: entry.assetId,
                      size: 1200,
                      fit: BoxFit.contain,
                      placeholderColor: _kViewerPanel,
                      failureLabel: '照片读取失败，无法显示大图',
                    ),
                  ),
                ),
                if (_showInfo) _buildInfoPanel(entry),
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(PhotoEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: <Widget>[
          TextButton(
            key: const Key('viewer-close'),
            onPressed: widget.onClose,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text(
              '‹ 返回',
              style: TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
          const Spacer(),
          Text(
            '${widget.index + 1} / ${widget.total}',
            key: const Key('viewer-count'),
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
          const Spacer(),
          Text(
            formatDay(entry.createdAt),
            style: const TextStyle(fontSize: 11, color: Color(0xFFB9BDC7)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(PhotoEntry entry) {
    final List<String> lines = <String>[
      '拍摄时间：${formatDateTime(entry.createdAt)}',
      if (entry.hasDimensions)
        '尺寸：${dimensionLabel(entry.width, entry.height)}',
      if (entry.hasLocation)
        '位置：${locationLabel(entry.latitude, entry.longitude)}',
      '第 ${widget.index + 1} / ${widget.total} 张',
    ];
    return Container(
      key: const Key('viewer-info-panel'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kViewerPanel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _viewerButton(
            const Key('viewer-prev'),
            Icons.chevron_left,
            '上一张',
            widget.onPrevious,
          ),
          _viewerButton(
            const Key('viewer-info'),
            Icons.info_outline,
            '照片信息',
            () => setState(() => _showInfo = !_showInfo),
          ),
          _viewerButton(
            const Key('viewer-next'),
            Icons.chevron_right,
            '下一张',
            widget.onNext,
          ),
        ],
      ),
    );
  }

  Widget _viewerButton(
    Key key,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      color: Colors.white,
      iconSize: 28,
      icon: Icon(icon),
    );
  }
}
