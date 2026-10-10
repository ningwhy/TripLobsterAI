import 'package:flutter/material.dart';
import '../models/trip_models.dart';

class TripMapPage extends StatefulWidget {
  final Trip trip;

  const TripMapPage({super.key, required this.trip});

  @override
  State<TripMapPage> createState() => _TripMapPageState();
}

class _TripMapPageState extends State<TripMapPage> {
  bool _isCartoonMode = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('行程地图'),
        actions: [
          // Map Mode Toggle
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isCartoonMode = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isCartoonMode
                          ? const Color(0xFF4A90D9)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '卡通',
                      style: TextStyle(
                        color: _isCartoonMode ? Colors.white : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _isCartoonMode = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: !_isCartoonMode
                          ? const Color(0xFF4A90D9)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '真实',
                      style: TextStyle(
                        color: !_isCartoonMode ? Colors.white : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map Placeholder
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.grey[200],
            child: _buildMapView(),
          ),

          // Legend
          Positioned(
            bottom: 100,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '图例',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildLegendItem(const Color(0xFF4A90D9), '景点'),
                  _buildLegendItem(const Color(0xFF9B59B6), '酒店'),
                  _buildLegendItem(const Color(0xFFF39C12), '餐饮'),
                  _buildLegendItem(const Color(0xFF2ECC71), '交通'),
                ],
              ),
            ),
          ),

          // Trip Summary Card
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.trip.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatChip(Icons.location_on, '${widget.trip.allLocations.length}个地点'),
                      _buildStatChip(Icons.straighten, '128km'),
                      _buildStatChip(Icons.flight_takeoff, '3段交通'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    if (_isCartoonMode) {
      return _buildCartoonMap();
    } else {
      return _buildRealMap();
    }
  }

  Widget _buildCartoonMap() {
    // 卡通模式：方位真实，距离压缩
    return CustomPaint(
      painter: _CartoonMapPainter(),
      child: Stack(
        children: [
          // Location Markers
          _buildLocationMarker(0.3, 0.2, '北京', LocationType.transport),
          _buildLocationMarker(0.5, 0.4, '石家庄', LocationType.attraction),
          _buildLocationMarker(0.7, 0.6, '郑州', LocationType.restaurant),
          _buildLocationMarker(0.85, 0.8, '武汉', LocationType.hotel),
          _buildLocationMarker(0.9, 0.9, '长沙', LocationType.attraction),
        ],
      ),
    );
  }

  Widget _buildRealMap() {
    // 真实地图模式 - 实际应该集成高德地图SDK
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            '真实地图模式',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '需要集成高德地图SDK',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationMarker(double x, double y, String name, LocationType type) {
    return Positioned(
      left: MediaQuery.of(context).size.width * x - 20,
      top: MediaQuery.of(context).size.height * y - 80,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getTypeColor(type),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _getTypeColor(type).withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              _getTypeIcon(type),
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Color _getTypeColor(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return const Color(0xFF9B59B6);
      case LocationType.attraction:
        return const Color(0xFFE74C3C);
      case LocationType.restaurant:
        return const Color(0xFFF39C12);
      case LocationType.shopping:
        return const Color(0xFF2ECC71);
      case LocationType.transport:
        return const Color(0xFF4A90D9);
      default:
        return const Color(0xFF95A5A6);
    }
  }

  IconData _getTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return Icons.hotel;
      case LocationType.attraction:
        return Icons.attractions;
      case LocationType.restaurant:
        return Icons.restaurant;
      case LocationType.shopping:
        return Icons.shopping_bag;
      case LocationType.transport:
        return Icons.directions_bus;
      default:
        return Icons.place;
    }
  }
}

class _CartoonMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 绘制卡通地图背景
    final paint = Paint()
      ..color = const Color(0xFFE8F5E9)
      ..style = PaintingStyle.fill;

    // 简化的中国地图轮廓
    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.2);
    path.lineTo(size.width * 0.4, size.height * 0.15);
    path.lineTo(size.width * 0.6, size.height * 0.2);
    path.lineTo(size.width * 0.8, size.height * 0.4);
    path.lineTo(size.width * 0.85, size.height * 0.7);
    path.lineTo(size.width * 0.7, size.height * 0.85);
    path.lineTo(size.width * 0.4, size.height * 0.8);
    path.lineTo(size.width * 0.2, size.height * 0.6);
    path.close();

    canvas.drawPath(path, paint);

    // 绘制连接线
    final linePaint = Paint()
      ..color = const Color(0xFF4A90D9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path2 = Path();
    path2.moveTo(size.width * 0.3, size.height * 0.2);
    path2.lineTo(size.width * 0.5, size.height * 0.4);
    path2.lineTo(size.width * 0.7, size.height * 0.6);
    path2.lineTo(size.width * 0.85, size.height * 0.8);
    path2.lineTo(size.width * 0.9, size.height * 0.9);

    canvas.drawPath(path2, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
