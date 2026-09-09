import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/trip_models.dart';
import '../services/api_client.dart';

/// 游戏风示意图：方位距离保真 + 贴纸点位 + 山水贴纸 + 行政区划底图（Canvas 手绘）
class SchematicMapPage extends StatefulWidget {
  final Trip trip;

  const SchematicMapPage({super.key, required this.trip});

  @override
  State<SchematicMapPage> createState() => _SchematicMapPageState();
}

class _SchData {
  List<List<List<double>>> polygons = [];
  List<Map<String, dynamic>> labels = [];
  List<Map<String, dynamic>> natures = [];
  List<List<double>> bbox = []; // [minLng,minLat,maxLng,maxLat]
}

class _SchematicMapPageState extends State<SchematicMapPage> {
  final GlobalKey _boundaryKey = GlobalKey();
  _SchData _data = _SchData();
  bool _loading = true;
  String? _error;
  bool _exporting = false;

  static const _dayColors = [
    Color(0xFFE5584C), Color(0xFFE8862E), Color(0xFFC9A227), Color(0xFF4F9D69),
    Color(0xFF3D7AB5), Color(0xFF7B5FB5), Color(0xFFC2557E),
  ];

  Color _colorOf(int i) => _dayColors[i % _dayColors.length];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> get _cities {
    final s = <String>{};
    for (final l in widget.trip.allLocations) {
      final c = l.city ?? l.cityName;
      if (c.isNotEmpty && c != '未知') s.add(c);
    }
    return s.isEmpty ? [] : s.toList().sublist(0, s.length > 3 ? 3 : s.length);
  }

  Future<void> _load() async {
    try {
      final locs = widget.trip.allLocations.where((l) => l.latitude != null).toList();
      if (locs.isEmpty) {
        setState(() { _loading = false; _error = '行程里还没有带坐标的地点'; });
        return;
      }
      var bbox = <List<double>>[
        [locs.map((l) => l.longitude!).reduce((a, b) => a < b ? a : b), locs.map((l) => l.latitude!).reduce((a, b) => a < b ? a : b)],
        [locs.map((l) => l.longitude!).reduce((a, b) => a > b ? a : b), locs.map((l) => l.latitude!).reduce((a, b) => a > b ? a : b)],
      ];
      final data = _SchData();
      // 行政区划
      if (_cities.isNotEmpty) {
        try {
          final b = await ApiClient.geoBoundary(_cities);
          data.polygons = ((b['polygons'] as List?) ?? []).cast<List>().map((e) => (e as List).cast<List<double>>().map((r) => (r as List).cast<double>()).toList()).toList();
          data.labels = ((b['labels'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }
      // 山水贴纸
      if (_cities.isNotEmpty) {
        try {
          final bboxStr = '${bbox[0][0]},${bbox[0][1]},${bbox[1][0]},${bbox[1][1]}';
          final n = await ApiClient.geoNature(_cities.first, bboxStr);
          data.natures = ((n['features'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (_) {}
      }
      // bbox 含山水并外扩
      for (final n in data.natures) {
        final lng = (n['lng'] as num).toDouble(), lat = (n['lat'] as num).toDouble();
        bbox = [
          [bbox[0][0], bbox[0][1]],
          [bbox[1][0], bbox[1][1]],
        ];
      }
      var minX = bbox[0][0], minY = bbox[0][1], maxX = bbox[1][0], maxY = bbox[1][1];
      for (final n in data.natures) {
        final lng = (n['lng'] as num).toDouble(), lat = (n['lat'] as num).toDouble();
        if (lng < minX) minX = lng;
        if (lng > maxX) maxX = lng;
        if (lat < minY) minY = lat;
        if (lat > maxY) maxY = lat;
      }
      final padX = (maxX - minX) * 0.22 + 0.02;
      final padY = (maxY - minY) * 0.22 + 0.02;
      data.bbox = [
        [minX - padX, minY - padY],
        [maxX + padX, maxY + padY],
      ];
      setState(() { _data = data; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = '加载失败：$e'; });
    }
  }

  Future<void> _exportAndShare() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('渲染失败');
      await Future.delayed(const Duration(milliseconds: 400));
      final image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) throw Exception('编码失败');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/schematic_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bd.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '${widget.trip.name} · 手绘示意图');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3B2F23),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A3B2C),
        title: const Text('示意图海报', style: TextStyle(color: Color(0xFFF3E5C3), fontSize: 16, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Color(0xFFF3E5C3)),
        actions: [
          TextButton.icon(
            onPressed: (_loading || _error != null) ? null : _exportAndShare,
            icon: _exporting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF3E5C3)))
                : const Icon(Icons.ios_share, size: 18, color: Color(0xFFF3E5C3)),
            label: const Text('保存/分享', style: TextStyle(color: Color(0xFFF3E5C3), fontSize: 13)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF3E5C3)))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFD8C79E)))))
              : RepaintBoundary(
                  key: _boundaryKey,
                  child: LayoutBuilder(
                    builder: (context, cons) => CustomPaint(
                      size: Size(cons.maxWidth, cons.maxHeight),
                      painter: _SchPainter(
                        trip: widget.trip,
                        data: _data,
                        colorOf: _colorOf,
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _SchPainter extends CustomPainter {
  final Trip trip;
  final _SchData data;
  final Color Function(int) colorOf;

  _SchPainter({required this.trip, required this.data, required this.colorOf});

  static const _bgTop = Color(0xFFF7EFDA);
  static const _bgBottom = Color(0xFFEFE1BE);
  static const _regionA = Color(0xFFF2E7C9);
  static const _regionB = Color(0xFFEBDCB4);
  static const _regionLine = Color(0xFFC4A870);
  static const _ink = Color(0xFF5B4630);

  late double _minX, _minY, _maxX, _maxY;
  late Rect _area; // 绘图区

  Offset _p(double lng, double lat) {
    final x = _area.left + (lng - _minX) / (_maxX - _minX) * _area.width;
    final y = _area.bottom - (lat - _minY) / (_maxY - _minY) * _area.height;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _minX = data.bbox[0][0]; _minY = data.bbox[0][1];
    _maxX = data.bbox[1][0]; _maxY = data.bbox[1][1];
    final w = size.width, h = size.height;
    _area = Rect.fromLTRB(w * 0.07, h * 0.16, w * 0.93, h * 0.84);

    // 1. 羊皮纸背景
    canvas.drawRect(Offset.zero & size, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_bgTop, _bgBottom]).createShader(Offset.zero & size));
    // 边框（双线）
    _frame(canvas, size);

    // 2. 行政区划
    _regions(canvas);

    // 3. 山水贴纸
    _natures(canvas);

    // 4. 每日路线 + 地点贴纸
    _routesAndStops(canvas);

    // 5. 标题横幅 / 指南针 / 图例
    _banner(canvas, w, h);
    _compass(canvas, w);
    _legend(canvas, w, h);
  }

  void _frame(Canvas canvas, Size size) {
    final outerPaint = Paint()..color = const Color(0xFFB99A62)..style = PaintingStyle.stroke..strokeWidth = 6;
    final innerPaint = Paint()..color = const Color(0xFF8A6D3F)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawRect(Rect.fromLTWH(10, 10, size.width - 20, size.height - 20), outerPaint);
    canvas.drawRect(Rect.fromLTWH(17, 17, size.width - 34, size.height - 34), innerPaint);
  }

  void _regions(Canvas canvas) {
    var i = 0;
    for (final ring in data.polygons) {
      if (ring.length < 4) continue;
      final path = Path();
      var first = true;
      for (final pt in ring) {
        final o = _p(pt[0], pt[1]);
        if (o.dx < _area.left - 80 || o.dx > _area.right + 80 || o.dy < _area.top - 80 || o.dy > _area.bottom + 80) continue;
        if (first) { path.moveTo(o.dx, o.dy); first = false; } else { path.lineTo(o.dx, o.dy); }
      }
      if (first) continue;
      path.close();
      canvas.drawPath(path, Paint()..color = i.isEven ? _regionA : _regionB);
      canvas.drawPath(path, Paint()..color = _regionLine..style = PaintingStyle.stroke..strokeWidth = 1.1..strokeJoin = StrokeJoin.round);
      i++;
    }
    // 区县名
    for (final lb in data.labels) {
      final o = _p((lb['lng'] as num).toDouble(), (lb['lat'] as num).toDouble());
      if (!_area.inflate(30).contains(o)) continue;
      _text(canvas, '${lb['name']}', o, 11, const Color(0xFF9A7F55), bold: false);
    }
  }

  void _natures(Canvas canvas) {
    for (final n in data.natures) {
      final o = _p((n['lng'] as num).toDouble(), (n['lat'] as num).toDouble());
      if (!_area.inflate(20).contains(o)) continue;
      final isM = n['kind'] == 'mountain';
      _emoji(canvas, isM ? '⛰️' : '🌊', o, 26);
      final name = (n['name'] as String).replaceAll(RegExp(r'风景名胜区|风景区|旅游区|度假区|国家|森林公园'), '');
      _text(canvas, name.length > 6 ? name.substring(0, 6) : name, o + const Offset(0, 16), 9.5, const Color(0xFF6E7F5A));
    }
  }

  void _routesAndStops(Canvas canvas) {
    final days = trip.days.where((d) => d.locations.any((l) => l.latitude != null)).toList();
    for (var di = 0; di < days.length; di++) {
      final color = colorOf(di);
      final pts = days[di].locations.where((l) => l.latitude != null).toList();
      if (pts.length >= 2) {
        final path = Path()..moveTo(_p(pts.first.longitude!, pts.first.latitude!).dx, _p(pts.first.longitude!, pts.first.latitude!).dy);
        for (var k = 1; k < pts.length; k++) {
          final o = _p(pts[k].longitude!, pts[k].latitude!);
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
        canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
      }
      for (final loc in pts) {
        _stop(canvas, _p(loc.longitude!, loc.latitude!), color, loc, di);
      }
    }
  }

  void _stop(Canvas canvas, Offset o, Color color, Location loc, int dayIdx) {
    // 停留贴纸：白圆底 + 日色边 + emoji
    canvas.drawCircle(o, 17, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawCircle(o, 17, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 3);
    _emoji(canvas, _emojiOf(loc.type), o, 17);
    // 名字标签
    final label = loc.name.length > 8 ? '${loc.name.substring(0, 8)}…' : loc.name;
    _chip(canvas, label, o + const Offset(0, 26), color);
  }

  void _chip(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Color(0xFF4A3B2C), fontSize: 10.5, fontWeight: FontWeight.w600)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(center: center, width: tp.width + 14, height: 18);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(9));
    canvas.drawRRect(rrect, Paint()..color = Colors.white.withOpacity(0.94));
    canvas.drawRRect(rrect, Paint()..color = color.withOpacity(0.65)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    tp.paint(canvas, rect.topLeft + Offset(7, (rect.height - tp.height) / 2));
  }

  String _emojiOf(LocationType t) {
    switch (t) {
      case LocationType.hotel: return '🏨';
      case LocationType.attraction: return '🎡';
      case LocationType.restaurant: return '🍜';
      case LocationType.shopping: return '🛍️';
      case LocationType.transport: return '✈️';
      case LocationType.home: return '🏠';
      default: return '📍';
    }
  }

  void _banner(Canvas canvas, double w, double h) {
    final name = trip.name;
    final sub = '${DateFormat('M.d').format(trip.startDate)}-${DateFormat('M.d').format(trip.endDate)} · ${trip.totalDays}天 · ${trip.allLocations.length}个地点';
    final tp = TextPainter(
      text: TextSpan(text: name, style: const TextStyle(color: Color(0xFFF7EDD1), fontSize: 21, fontWeight: FontWeight.bold)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final tp2 = TextPainter(
      text: TextSpan(text: sub, style: const TextStyle(color: Color(0xFFD8C79E), fontSize: 11)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final width = (tp.width > tp2.width ? tp.width : tp2.width) + 44;
    final rect = Rect.fromCenter(center: Offset(w / 2, h * 0.085), width: width, height: 62);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF5B4630));
    canvas.drawRRect(rrect.shift(const Offset(2, 2)), Paint()..color = const Color(0xFFC9A227)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF8A6D3F)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.top + 10));
    tp2.paint(canvas, Offset(rect.center.dx - tp2.width / 2, rect.top + 38));
  }

  void _compass(Canvas canvas, double w) {
    _emoji(canvas, '🧭', Offset(w - 52, 64), 26);
  }

  void _legend(Canvas canvas, double w, double h) {
    final days = trip.days.where((d) => d.locations.any((l) => l.latitude != null)).toList();
    final y = h - 52;
    var x = 26.0;
    for (var i = 0; i < days.length && i < 7; i++) {
      final c = colorOf(i);
      final tp = TextPainter(
        text: TextSpan(text: 'Day ${days[i].dayNumber}', style: const TextStyle(color: Color(0xFF5B4630), fontSize: 10.5, fontWeight: FontWeight.w600)),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 30, 5), const Radius.circular(3)), Paint()..color = c);
      tp.paint(canvas, Offset(x, y + 9));
      x += 62;
    }
    final mark = TextPainter(
      text: const TextSpan(text: '· AI 行程助手 ·', style: TextStyle(color: Color(0xFFB99A62), fontSize: 9.5)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    mark.paint(canvas, Offset(w - mark.width - 26, h - 30));
  }

  void _text(Canvas canvas, String s, Offset o, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o - Offset(tp.width / 2, 0));
  }

  void _emoji(Canvas canvas, String e, Offset o, double size) {
    final tp = TextPainter(
      text: TextSpan(text: e, style: TextStyle(fontSize: size)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SchPainter old) => true;
}
