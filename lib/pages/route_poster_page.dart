import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/trip_models.dart';
import '../services/api_client.dart';

/// 路线海报：行程地图模式（卫星底图 + 分日彩色路线 + 标注）→ 导出 PNG 分享
class RoutePosterPage extends StatefulWidget {
  final Trip trip;

  const RoutePosterPage({super.key, required this.trip});

  @override
  State<RoutePosterPage> createState() => _RoutePosterPageState();
}

class _DayRoute {
  final int dayNumber;
  final List<LatLng> points = []; // 路线点（OSRM 真实路线，失败为直线）
  final List<Location> locations = [];
  double km = 0;
  _DayRoute(this.dayNumber);
}

class _RoutePosterPageState extends State<RoutePosterPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  final MapController _mapController = MapController();

  static const _dayColors = [
    Color(0xFFFF6B6B), Color(0xFFFFA94D), Color(0xFFFFD43B), Color(0xFF69DB7C),
    Color(0xFF4DABF7), Color(0xFFB197FC), Color(0xFFF783AC),
  ];

  List<_DayRoute> _routes = [];
  bool _loading = true;
  String? _error;
  double _totalKm = 0;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final routes = <_DayRoute>[];
      for (final day in widget.trip.days) {
        final locs = day.locations.where((l) => l.latitude != null && l.longitude != null).toList();
        if (locs.isEmpty) continue;
        final r = _DayRoute(day.dayNumber)..locations.addAll(locs);
        if (locs.length >= 2) {
          final waypoints = locs.map((l) => [l.longitude!, l.latitude!]).toList();
          try {
            final data = await ApiClient.corridorRoute(waypoints);
            final coords = (data['coordinates'] as List).cast<List>();
            r.points.addAll(coords.map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())));
            r.km = (data['distanceKm'] as num?)?.toDouble() ?? 0;
          } catch (_) {
            r.points.addAll(locs.map((l) => LatLng(l.latitude!, l.longitude!)));
          }
        } else {
          r.points.add(LatLng(locs.first.latitude!, locs.first.longitude!));
        }
        routes.add(r);
      }
      if (routes.isEmpty) {
        setState(() { _loading = false; _error = '行程里还没有带坐标的地点，先添加地点再生成海报'; });
        return;
      }
      _totalKm = routes.fold(0, (s, r) => s + r.km);
      setState(() { _routes = routes; _loading = false; });
      // 地图框选全部点
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final all = routes.expand((r) => r.locations.map((l) => LatLng(l.latitude!, l.longitude!))).toList();
        if (all.length == 1) {
          _mapController.move(all.first, 13);
        } else {
          _mapController.fitCamera(CameraFit.coordinates(coordinates: all, padding: const EdgeInsets.all(64)));
        }
      });
    } catch (e) {
      setState(() { _loading = false; _error = '路线加载失败：$e'; });
    }
  }

  Color _colorOf(int i) => _dayColors[i % _dayColors.length];

  Future<void> _exportAndShare() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('渲染失败');
      // 等待一帧确保瓦片绘制完成
      await Future.delayed(const Duration(milliseconds: 600));
      final image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('图像编码失败');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/route_poster_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '${widget.trip.name} · 行程路线图');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: const Text('路线海报', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: (_loading || _error != null) ? null : _exportAndShare,
            icon: _exporting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.ios_share, size: 18, color: Colors.white),
            label: const Text('保存/分享', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70))))
              : RepaintBoundary(
                  key: _boundaryKey,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: LatLng(35.0, 105.0),
                      initialZoom: 4,
                      interactionOptions: InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                        userAgentPackageName: 'com.example.trip_planner',
                        maxNativeZoom: 18,
                      ),
                      PolylineLayer(
                        polylines: [
                          for (var i = 0; i < _routes.length; i++)
                            if (_routes[i].points.length >= 2)
                              Polyline(
                                points: _routes[i].points,
                                color: _colorOf(i),
                                strokeWidth: 4,
                                borderStrokeWidth: 1.5,
                                borderColor: Colors.white38,
                              ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          for (var i = 0; i < _routes.length; i++)
                            for (final loc in _routes[i].locations)
                              Marker(
                                point: LatLng(loc.latitude!, loc.longitude!),
                                width: 30,
                                height: 30,
                                child: _marker(_colorOf(i), loc),
                              ),
                        ],
                      ),
                      _buildTitleCard(),
                      _buildLegend(),
                    ],
                  ),
                ),
    );
  }

  Widget _marker(Color color, Location loc) {
    final isHotel = loc.type == LocationType.hotel;
    final isHub = loc.type == LocationType.transport;
    return Container(
      decoration: BoxDecoration(
        color: isHotel ? Colors.white : color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
      ),
      child: Center(
        child: Icon(
          isHotel ? Icons.hotel_rounded : isHub ? Icons.flight_takeoff_rounded : Icons.place_rounded,
          size: 14,
          color: isHotel ? color : Colors.white,
        ),
      ),
    );
  }

  Widget _buildTitleCard() {
    final t = widget.trip;
    final dateStr = '${DateFormat('M.d').format(t.startDate)} - ${DateFormat('M.d').format(t.endDate)}';
    final places = t.allLocations.length;
    return Positioned(
      left: 12,
      top: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 16, 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '$dateStr · ${t.totalDays}天 · $places个地点${_totalKm > 0 ? ' · 行程${_totalKm.toStringAsFixed(0)}km' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Positioned(
      left: 12,
      bottom: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (var i = 0; i < _routes.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 14, height: 4, decoration: BoxDecoration(color: _colorOf(i), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text('Day ${_routes[i].dayNumber}', style: const TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
