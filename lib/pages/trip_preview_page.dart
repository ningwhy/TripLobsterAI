import 'package:flutter/material.dart';
import '../models/trip_models.dart';

class TripPreviewPage extends StatefulWidget {
  final Trip trip;

  const TripPreviewPage({super.key, required this.trip});

  @override
  State<TripPreviewPage> createState() => _TripPreviewPageState();
}

class _TripPreviewPageState extends State<TripPreviewPage> {
  int _selectedDayIndex = 0;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final days = trip.days.isEmpty
        ? List.generate(
            3,
            (i) => TripDay(
              date: trip.startDate.add(Duration(days: i)),
              dayNumber: i + 1,
              locations: [],
            ),
          )
        : trip.days;

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF89CFF0), Color(0xFF6BB3E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // App Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            '行程预览',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.white),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  // Trip Info
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        Text(
                          trip.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${trip.startDate.month}/${trip.startDate.day} - ${trip.endDate.month}/${trip.endDate.day} · ${days.length}天 · ${trip.allLocations.length}个地点',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Day Tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: days.asMap().entries.map((entry) {
                  final index = entry.key;
                  final isSelected = _selectedDayIndex == index;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedDayIndex = index;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF89CFF0) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Day ${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[600],
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Content
          Expanded(
            child: Container(
              color: Colors.grey[50],
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDayTimeline(days[_selectedDayIndex], _selectedDayIndex),
                ],
              ),
            ),
          ),

          // Bottom Cost Estimate
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '费用预估',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '¥${_calculateTotalCost()}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildCostItem('交通', '¥${_calculateTransportCost()}'),
                      _buildCostItem('住宿', '¥${_calculateHotelCost()}'),
                      _buildCostItem('餐饮', '¥${_calculateFoodCost()}'),
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

  Widget _buildDayTimeline(TripDay day, int dayIndex) {
    if (day.locations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: const Center(
          child: Text(
            '暂无地点',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${day.date.month}月${day.date.day}日 · Day ${dayIndex + 1}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...day.locations.asMap().entries.map((entry) {
          final index = entry.key;
          final location = entry.value;
          return _buildLocationItem(location, index, day.locations.length);
        }),
      ],
    );
  }

  Widget _buildLocationItem(Location location, int index, int total) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: index == 0 ? const Color(0xFF89CFF0) : const Color(0xFF4A90D9),
                  shape: BoxShape.circle,
                ),
              ),
              if (index < total - 1)
                Container(
                  width: 2,
                  height: 60,
                  color: const Color(0xFF4A90D9).withOpacity(0.3),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // Location card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getTypeIcon(location.type),
                        size: 16,
                        color: _getTypeColor(location.type),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location.address,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (location.stayMinutes != null && location.stayMinutes! > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '游玩${location.stayMinutes}分钟',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
      case LocationType.home:
        return Icons.home;
      default:
        return Icons.place;
    }
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
        return const Color(0xFF1ABC9C);
      case LocationType.transport:
        return const Color(0xFF3498DB);
      default:
        return const Color(0xFF95A5A6);
    }
  }

  Widget _buildCostItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFF6600),
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

  int _calculateTransportCost() {
    int cost = 0;
    for (var loc in widget.trip.allLocations) {
      if (loc.transport != null) {
        if (loc.transport!.type == TransportType.flight) {
          cost += 800;
        } else if (loc.transport!.type == TransportType.highSpeedTrain) {
          cost += 400;
        } else {
          cost += 200;
        }
      }
    }
    return cost;
  }

  int _calculateHotelCost() {
    int nights = widget.trip.totalDays > 0 ? widget.trip.totalDays - 1 : 0;
    return nights * 400;
  }

  int _calculateFoodCost() {
    return widget.trip.totalDays * 100;
  }

  int _calculateTotalCost() {
    return _calculateTransportCost() + _calculateHotelCost() + _calculateFoodCost();
  }
}
