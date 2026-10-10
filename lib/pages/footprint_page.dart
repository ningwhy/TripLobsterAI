import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/trip_models.dart';
import '../providers/trip_provider.dart';

class FootprintPage extends StatelessWidget {
  const FootprintPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('足迹记录'),
      ),
      body: Consumer<TripProvider>(
        builder: (context, provider, _) {
          final footprints = provider.footprints.isEmpty
              ? _getSampleFootprints()
              : provider.footprints;

          return Stack(
            children: [
              // Map
              CustomPaint(
                painter: _FootprintMapPainter(footprints),
                size: Size.infinite,
              ),

              // City Markers
              ...footprints.asMap().entries.map((entry) {
                final index = entry.key;
                final footprint = entry.value;
                return _buildCityMarker(
                  context,
                  index,
                  footprint,
                  footprints.length,
                );
              }),

              // Stats Card
              Positioned(
                bottom: 100,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            '${footprints.length}',
                            '个城市',
                            const Color(0xFF4A90D9),
                          ),
                          _buildStatItem(
                            '${footprints.fold(0, (sum, f) => sum + f.visitCount)}',
                            '次旅行',
                            const Color(0xFF9B59B6),
                          ),
                          _buildStatItem(
                            _getTotalDays(footprints),
                            '天足迹',
                            const Color(0xFFF39C12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '这是你的终生旅行地图',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Footprint> _getSampleFootprints() {
    return [
      Footprint(city: '北京', province: '北京', latitude: 39.9042, longitude: 116.4074, visitedAt: DateTime(2024, 1, 15), visitCount: 5),
      Footprint(city: '上海', province: '上海', latitude: 31.2304, longitude: 121.4737, visitedAt: DateTime(2024, 3, 20), visitCount: 3),
      Footprint(city: '广州', province: '广东', latitude: 23.1291, longitude: 113.2644, visitedAt: DateTime(2024, 5, 1), visitCount: 2),
      Footprint(city: '深圳', province: '广东', latitude: 22.5431, longitude: 114.0579, visitedAt: DateTime(2024, 5, 3), visitCount: 2),
      Footprint(city: '成都', province: '四川', latitude: 30.5728, longitude: 104.0668, visitedAt: DateTime(2024, 7, 10), visitCount: 1),
      Footprint(city: '西安', province: '陕西', latitude: 34.3416, longitude: 108.9398, visitedAt: DateTime(2023, 10, 1), visitCount: 1),
      Footprint(city: '杭州', province: '浙江', latitude: 30.2741, longitude: 120.1551, visitedAt: DateTime(2023, 11, 15), visitCount: 1),
      Footprint(city: '昆明', province: '云南', latitude: 25.0406, longitude: 102.7129, visitedAt: DateTime(2024, 2, 10), visitCount: 1),
      Footprint(city: '大理', province: '云南', latitude: 25.6064, longitude: 100.2679, visitedAt: DateTime(2024, 2, 12), visitCount: 1),
    ];
  }

  Widget _buildCityMarker(
    BuildContext context,
    int index,
    Footprint footprint,
    int total,
  ) {
    // 简化的位置映射
    final positions = [
      const Offset(0.55, 0.25), // 北京
      const Offset(0.7, 0.55),  // 上海
      const Offset(0.55, 0.75), // 广州
      const Offset(0.6, 0.72),  // 深圳
      const Offset(0.35, 0.55), // 成都
      const Offset(0.45, 0.4),  // 西安
      const Offset(0.65, 0.5),  // 杭州
      const Offset(0.35, 0.75), // 昆明
      const Offset(0.32, 0.72), // 大理
    ];

    if (index >= positions.length) return const SizedBox.shrink();

    final position = positions[index];
    final size = MediaQuery.of(context).size;

    return Positioned(
      left: size.width * position.dx - 15,
      top: size.height * position.dy - 60,
      child: GestureDetector(
        onTap: () => _showCityDetail(context, footprint),
        child: Column(
          children: [
            Container(
              width: 12 + (footprint.visitCount * 2).toDouble(),
              height: 12 + (footprint.visitCount * 2).toDouble(),
              decoration: BoxDecoration(
                color: const Color(0xFF4A90D9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A90D9).withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              footprint.city,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  String _getTotalDays(List<Footprint> footprints) {
    // 估算总天数
    return '${footprints.length * 3}';
  }

  void _showCityDetail(BuildContext context, Footprint footprint) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              footprint.city,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              footprint.province,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCityStat(Icons.flight, '${footprint.visitCount}次'),
                const SizedBox(width: 24),
                _buildCityStat(
                  Icons.calendar_today,
                  '${footprint.visitedAt.year}年',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 44),
              ),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCityStat(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}

class _FootprintMapPainter extends CustomPainter {
  final List<Footprint> footprints;

  _FootprintMapPainter(this.footprints);

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制地图背景
    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 简化的中国地图轮廓
    final mapPaint = Paint()
      ..color = const Color(0xFF16213E)
      ..style = PaintingStyle.fill;

    final path = Path();
    // 简化的中国地图形状
    path.moveTo(size.width * 0.3, size.height * 0.2);
    path.lineTo(size.width * 0.45, size.height * 0.15);
    path.lineTo(size.width * 0.55, size.height * 0.2);
    path.lineTo(size.width * 0.6, size.height * 0.3);
    path.lineTo(size.width * 0.65, size.height * 0.5);
    path.lineTo(size.width * 0.6, size.height * 0.7);
    path.lineTo(size.width * 0.55, size.height * 0.8);
    path.lineTo(size.width * 0.45, size.height * 0.75);
    path.lineTo(size.width * 0.35, size.height * 0.65);
    path.lineTo(size.width * 0.3, size.height * 0.5);
    path.lineTo(size.width * 0.25, size.height * 0.35);
    path.close();

    canvas.drawPath(path, mapPaint);

    // 绘制连接线
    if (footprints.length > 1) {
      final linePaint = Paint()
        ..color = const Color(0xFF4A90D9).withValues(alpha: 0.5)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      final linePath = Path();
      final positions = [
        const Offset(0.55, 0.25),
        const Offset(0.7, 0.55),
        const Offset(0.55, 0.75),
        const Offset(0.6, 0.72),
        const Offset(0.35, 0.55),
        const Offset(0.45, 0.4),
        const Offset(0.65, 0.5),
        const Offset(0.35, 0.75),
        const Offset(0.32, 0.72),
      ];

      for (int i = 0; i < footprints.length - 1 && i < positions.length - 1; i++) {
        linePath.moveTo(size.width * positions[i].dx, size.height * positions[i].dy);
        linePath.lineTo(
          size.width * positions[i + 1].dx,
          size.height * positions[i + 1].dy,
        );
      }

      canvas.drawPath(linePath, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
