import 'package:flutter/material.dart';

import '../models/photo_entry.dart';
import '../services/photo_source.dart';
import '../services/storage_service.dart';
import '../utils/photo_selection.dart';
import '../widgets/gallery/photo_grid.dart';
import '../widgets/gallery/photo_viewer.dart';

const Color _kPrimary = Color(0xFF7C6DF7);
const Color _kInk = Color(0xFF1F2430);
const Color _kSub = Color(0xFF6B7280);
const Color _kLine = Color(0xFFE7E9EF);
const Color _kBg = Color(0xFFF7F8FC);
const Color _kChipOff = Color(0xFFF1F2F7);

/// 旅行相册页（HomePage 的第 3 个 Tab）。
///
/// 三模式互斥：浏览 / 多选 / 信息列表；勾选集合跨模式保留并实时计数；
/// 「完成」把选中的真实 assetId 通过 [StorageService] 持久化。
/// 数据源可注入（测试用 FakePhotoSource），绝不编造照片 / 时间 / 地点 / 张数。
class GalleryPage extends StatefulWidget {
  const GalleryPage({
    super.key,
    this.photoSource = const DevicePhotoSource(),
    this.storage,
  });

  final PhotoSource photoSource;
  final StorageService? storage;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final StorageService _storage = widget.storage ?? StorageService();

  GalleryMode _mode = GalleryMode.browse;
  bool _loading = true;
  PhotoPermissionState _permission = PhotoPermissionState.unavailable;
  String _loadError = '';
  String _notice = '';
  List<PhotoEntry> _entries = const <PhotoEntry>[];
  Map<DateTime, List<PhotoEntry>> _groups =
      const <DateTime, List<PhotoEntry>>{};
  Set<String> _selected = <String>{};
  int _archivedCount = 0;
  int? _viewerIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 首帧由 `_loading = true` 呈现加载态；本方法只负责异步计算 + 收尾 setState。
  Future<void> _load() async {
    final StorageService storage = _storage;
    PhotoPermissionState state = PhotoPermissionState.unavailable;
    String loadError = '';
    List<String> saved = const <String>[];
    List<PhotoEntry> loaded = const <PhotoEntry>[];
    try {
      await storage.init();
      saved = await storage.getSelectedPhotoIds();
      state = await widget.photoSource.permission();
      if (state == PhotoPermissionState.granted ||
          state == PhotoPermissionState.limited) {
        loaded = await widget.photoSource.load();
      }
    } catch (error) {
      // 不吞异常：把真实错误原文带到空态里，绝不降级成「没有照片」。
      loadError = error.toString();
    }

    final Map<DateTime, List<PhotoEntry>> groups = groupByDay(loaded);
    final List<PhotoEntry> flat = <PhotoEntry>[
      for (final List<PhotoEntry> day in groups.values) ...day,
    ];
    // 读回上次归档的 id；只保留当前设备相册里仍存在的，避免幽灵勾选。
    final Set<String> restored = <String>{
      for (final String id in saved)
        if (flat.any((PhotoEntry e) => e.assetId == id)) id,
    };

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _permission = state;
      _loadError = loadError;
      _groups = groups;
      _entries = flat;
      _archivedCount = saved.length;
      _selected = restored;
      _viewerIndex = null;
    });
  }

  /// 空态 / 错误态里的「重新请求授权」「重新读取」都是真实动作。
  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _notice = '';
    });
    await _load();
  }

  void _setMode(GalleryMode mode) {
    setState(() {
      _mode = mode;
      _viewerIndex = null;
      _notice = '';
    });
  }

  void _toggle(String id) {
    setState(() {
      _selected = toggle(_selected, id);
      _notice = '';
    });
  }

  void _openViewer(String id) {
    final int index =
        _entries.indexWhere((PhotoEntry entry) => entry.assetId == id);
    if (index < 0) {
      return;
    }
    setState(() => _viewerIndex = index);
  }

  void _closeViewer() {
    setState(() => _viewerIndex = null);
  }

  /// 上一张 / 下一张循环（取模），索引始终落在真实 [entries] 范围内。
  VoidCallback _stepViewer(int delta) {
    return () {
      final int total = _entries.length;
      if (total == 0 || _viewerIndex == null) {
        return;
      }
      setState(() => _viewerIndex = (_viewerIndex! + delta + total) % total);
    };
  }

  /// 「完成」做真实的事：把选中 assetId 列表持久化，并回到浏览模式。
  /// 不假装已关联到任何行程地点。
  Future<void> _finish() async {
    final List<String> ids = _selected.toList()..sort();
    try {
      await _storage.init();
      await _storage.saveSelectedPhotoIds(ids);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _notice = '归档失败：$error');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _archivedCount = ids.length;
      _mode = GalleryMode.browse;
      _viewerIndex = null;
      _notice = ids.isEmpty
          ? '未选择照片，未归档任何内容'
          : '已归档 ${ids.length} 张照片（已保存到本地）';
    });
  }

  void _onManage() {
    switch (_mode) {
      case GalleryMode.browse:
        _setMode(GalleryMode.select);
        break;
      case GalleryMode.select:
        _setMode(GalleryMode.list);
        break;
      case GalleryMode.list:
        _finish();
        break;
    }
  }

  void _onCameraTap() {
    setState(() => _notice = '拍照入口为原型示意，暂未接入真实相机，未拍摄任何照片');
  }

  String _modeLabel(GalleryMode mode) {
    switch (mode) {
      case GalleryMode.browse:
        return '浏览';
      case GalleryMode.select:
        return '多选';
      case GalleryMode.list:
        return '信息列表';
    }
  }

  String _manageLabel() {
    switch (_mode) {
      case GalleryMode.browse:
        return '管理';
      case GalleryMode.select:
        return '信息列表';
      case GalleryMode.list:
        return '完成';
    }
  }

  String _hint() {
    switch (_mode) {
      case GalleryMode.browse:
        return '当前：浏览模式。点击照片查看大图；「管理」依次切换到多选、信息列表。'
            '照片来自设备相册，按真实拍摄日期分组。';
      case GalleryMode.select:
        return '当前：多选模式。点击照片切换勾选，已选计数实时更新；勾选在其他模式保留。';
      case GalleryMode.list:
        return '当前：信息列表模式。缩略图看大图，行切换勾选；「完成」把所选照片归档到本地。';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _kBg,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              _buildHeader(),
              _buildModeBar(),
              _buildHint(),
              if (_mode == GalleryMode.browse) _buildPrototypeActions(),
              if (_notice.isNotEmpty) _buildNotice(),
              Expanded(child: _buildBody()),
              if (_mode == GalleryMode.select) _buildTray(),
            ],
          ),
          if (_viewerIndex != null && _entries.isNotEmpty)
            Positioned.fill(
              child: PhotoViewer(
                key: const Key('photo-viewer'),
                entry: _entries[_viewerIndex!],
                index: _viewerIndex!,
                total: _entries.length,
                source: widget.photoSource,
                onClose: _closeViewer,
                onPrevious: _stepViewer(-1),
                onNext: _stepViewer(1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              '旅行相册',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: _kInk,
              ),
            ),
          ),
          if (_archivedCount > 0)
            Text(
              archiveLabel(_archivedCount),
              key: const Key('archive-count'),
              style: const TextStyle(fontSize: 11, color: _kPrimary),
            ),
          const SizedBox(width: 6),
          TextButton(
            key: const Key('manage-button'),
            onPressed: _onManage,
            style: TextButton.styleFrom(foregroundColor: _kPrimary),
            child: Text(_manageLabel(), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildModeBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: <Widget>[
          for (final GalleryMode mode in GalleryMode.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: Key('mode-${mode.name}'),
                label: Text(
                  _modeLabel(mode),
                  style: TextStyle(
                    fontSize: 12,
                    color: _mode == mode ? Colors.white : _kSub,
                  ),
                ),
                labelStyle: const TextStyle(fontSize: 12),
                showCheckmark: false,
                selected: _mode == mode,
                selectedColor: _kPrimary,
                backgroundColor: _kChipOff,
                onSelected: (bool _) => _setMode(mode),
              ),
            ),
          const Spacer(),
          if (_mode != GalleryMode.browse)
            Text(
              countLabel(_selected.length),
              key: const Key('selection-count'),
              style: const TextStyle(fontSize: 11, color: _kPrimary),
            ),
        ],
      ),
    );
  }

  Widget _buildHint() {
    return Container(
      width: double.infinity,
      color: _kBg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Text(
        _hint(),
        style: const TextStyle(fontSize: 11, color: _kSub, height: 1.45),
      ),
    );
  }

  /// 拍照入口没有真实相机实现 → 明确标注「原型示意」并给诚实反馈。
  Widget _buildPrototypeActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 14, 0),
      child: Row(
        children: <Widget>[
          TextButton.icon(
            key: const Key('camera-prototype'),
            onPressed: _onCameraTap,
            icon: const Icon(Icons.photo_camera_outlined, size: 15, color: _kSub),
            label: const Text(
              '拍照（原型示意）',
              style: TextStyle(fontSize: 11, color: _kSub),
            ),
          ),
          const Spacer(),
          Text(
            '共 ${_entries.length} 张',
            style: const TextStyle(fontSize: 11, color: _kSub),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF0EEFF),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        _notice,
        key: const Key('gallery-notice'),
        style: const TextStyle(fontSize: 11, color: _kInk),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _stateCard(
        icon: Icons.hourglass_top,
        title: '正在读取设备相册…',
        detail: '正在请求相册权限并读取照片的真实拍摄时间与尺寸。',
        spinner: true,
      );
    }
    switch (_permission) {
      case PhotoPermissionState.denied:
        return _stateCard(
          icon: Icons.lock_outline,
          title: '未获得相册访问权限',
          detail: '无法读取设备相册。请在系统设置中允许访问照片后重试。'
              '这与「设备里没有照片」是两回事。',
          actionLabel: '重新请求授权',
          onAction: _retry,
        );
      case PhotoPermissionState.unavailable:
        return _stateCard(
          icon: Icons.error_outline,
          title: '无法访问设备相册',
          detail: _loadError.isEmpty
              ? '当前环境无法调用设备相册能力。'
              : '当前环境无法调用设备相册能力：$_loadError',
          actionLabel: '重新请求授权',
          onAction: _retry,
        );
      case PhotoPermissionState.granted:
      case PhotoPermissionState.limited:
        break;
    }
    if (_loadError.isNotEmpty) {
      return _stateCard(
        icon: Icons.error_outline,
        title: '读取设备相册失败',
        detail: _loadError,
        actionLabel: '重新读取',
        onAction: _retry,
      );
    }
    if (_entries.isEmpty) {
      return _stateCard(
        icon: Icons.photo_library_outlined,
        title: '设备相册中没有可显示的照片',
        detail: '仅显示带有真实拍摄时间的照片；没有拍摄时间的资源不会被展示，'
            '也不会用占位图代替。',
        actionLabel: '重新读取',
        onAction: _retry,
      );
    }
    return PhotoGrid(
      groups: _groups,
      mode: _mode,
      selected: _selected,
      source: widget.photoSource,
      onOpen: _openViewer,
      onToggle: _toggle,
    );
  }

  Widget _stateCard({
    required IconData icon,
    required String title,
    required String detail,
    bool spinner = false,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kLine),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (spinner)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, size: 38, color: _kPrimary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kInk,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: _kSub,
                  height: 1.5,
                ),
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: 16),
                ElevatedButton(
                  key: const Key('state-action'),
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTray() {
    final List<PhotoEntry> selectedPhotos = _entries
        .where((PhotoEntry entry) => _selected.contains(entry.assetId))
        .toList();
    return Container(
      key: const Key('select-tray'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kLine)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 46,
              child: selectedPhotos.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '未选择照片',
                        style: TextStyle(fontSize: 11, color: _kSub),
                      ),
                    )
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      children: <Widget>[
                        for (final PhotoEntry entry in selectedPhotos)
                          GestureDetector(
                            key: Key('tray-thumb-${entry.assetId}'),
                            onTap: () => _openViewer(entry.assetId),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: PhotoThumb(
                                  source: widget.photoSource,
                                  assetId: entry.assetId,
                                  size: 120,
                                  failureLabel: '照片读取失败',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            countLabel(_selected.length),
            key: const Key('tray-count'),
            style: const TextStyle(fontSize: 11, color: _kPrimary),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            key: const Key('tray-done'),
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('完成', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
