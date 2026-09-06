import 'package:flutter/material.dart';
import '../models/trip_models.dart';
import '../services/amap_service.dart';

class LocationSearchPage extends StatefulWidget {
  const LocationSearchPage({super.key});

  @override
  State<LocationSearchPage> createState() => _LocationSearchPageState();
}

class _LocationSearchPageState extends State<LocationSearchPage> {
  final _searchController = TextEditingController();
  final _amapService = AmapService();

  List<AmapPoi> _results = [];
  bool _isLoading = false;

  // 热门推荐（本地缓存）
  final List<AmapPoi> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    // 加载热门城市热门景点
    final pois = await _amapService.searchPoi('北京景点', city: '北京');
    if (mounted && pois.isNotEmpty) {
      setState(() {
        _suggestions.addAll(pois.take(6));
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加地点'),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索地点、景点、酒店...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _results = [];
                              });
                            },
                          )
                        : null,
              ),
              onChanged: (value) {
                _search(value);
              },
            ),
          ),

          // Results or Suggestions
          Expanded(
            child: _results.isNotEmpty
                ? ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      return _buildResultItem(item);
                    },
                  )
                : _suggestions.isNotEmpty
                    ? ListView(
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              '热门推荐',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          ..._suggestions.map((item) => _buildResultItem(item)),
                        ],
                      )
                    : const Center(
                        child: Text('搜索地点添加到行程'),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _amapService.searchPoi(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e')),
        );
      }
    }
  }

  Widget _buildResultItem(AmapPoi poi) {
    final type = _poiTypeToLocationType(poi.typecode);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _getTypeColor(type).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getTypeIcon(type),
          color: _getTypeColor(type),
          size: 20,
        ),
      ),
      title: Text(poi.name),
      subtitle: Text(
        poi.address.isNotEmpty ? poi.address : poi.cityName,
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        final location = Location(
          name: poi.name,
          address: poi.address.isNotEmpty ? poi.address : poi.cityName,
          latitude: poi.lat,
          longitude: poi.lng,
          city: poi.city,
          district: poi.district,
          type: type,
          stayMinutes: _getDefaultStayTime(type),
        );
        Navigator.pop(context, location);
      },
    );
  }

  LocationType _poiTypeToLocationType(String typecode) {
    // 高德POI类型码对应
    if (typecode.startsWith('1501')) return LocationType.hotel;      // 酒店
    if (typecode.startsWith('1502')) return LocationType.attraction; // 景点
    if (typecode.startsWith('1503')) return LocationType.restaurant; // 餐饮
    if (typecode.startsWith('1504')) return LocationType.shopping;   // 购物
    if (typecode.startsWith('1505')) return LocationType.transport;  // 交通
    if (typecode.startsWith('1506')) return LocationType.attraction; // 娱乐
    if (typecode.startsWith('1507')) return LocationType.other;      // 生活服务
    if (typecode.startsWith('1508')) return LocationType.other;      // 医疗
    return LocationType.other;
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

  int _getDefaultStayTime(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return 0; // 过夜
      case LocationType.attraction:
        return 180; // 3小时
      case LocationType.restaurant:
        return 60; // 1小时
      case LocationType.shopping:
        return 90; // 1.5小时
      default:
        return 60;
    }
  }
}
