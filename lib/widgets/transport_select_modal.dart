import 'package:flutter/material.dart';
import '../models/trip_models.dart';
import '../services/amap_service.dart';

class TransportSelectModal extends StatefulWidget {
  final Location fromLocation;
  final Location toLocation;
  final AmapRoute? routeInfo;
  final Function(Transport) onConfirm;

  const TransportSelectModal({
    super.key,
    required this.fromLocation,
    required this.toLocation,
    this.routeInfo,
    required this.onConfirm,
  });

  @override
  State<TransportSelectModal> createState() => _TransportSelectModalState();
}

class _TransportSelectModalState extends State<TransportSelectModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  IntercityTransitResult? _transitResult;
  int _selectedIndex = -1;
  bool _isFallbackMode = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedIndex = -1;
          _isFallbackMode = false;
        });
      }
    });
    _loadTransitData();
  }

  Future<void> _loadTransitData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fromLat = widget.fromLocation.latitude ?? 0;
      final fromLng = widget.fromLocation.longitude ?? 0;
      final toLat = widget.toLocation.latitude ?? 0;
      final toLng = widget.toLocation.longitude ?? 0;

      // 传递城市名称
      final result = await getIntercityTransit(
        originLng: fromLng,
        originLat: fromLat,
        destinationLng: toLng,
        destinationLat: toLat,
        originCity: widget.fromLocation.city,
        destinationCity: widget.toLocation.city,
      );

      setState(() {
        _transitResult = result;
        _isLoading = false;

        // 如果没有返回数据，创建空的结果（会显示备用选项）
        if (result == null) {
          _transitResult = IntercityTransitResult(
            origin: '',
            destination: '',
            flights: [],
            trains: [],
            buses: [],
          );
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // 顶部拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.fromLocation.cityName} → ${widget.toLocation.cityName}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '选择交通工具',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          // Tab 切换
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF4A90D9),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF4A90D9),
            tabs: const [
              Tab(text: '✈️ 飞机'),
              Tab(text: '🚄 高铁'),
              Tab(text: '🚌 汽车'),
            ],
          ),
          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _buildTransitList(),
          ),
          // 确认按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _confirmSelection(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90D9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('确认选择'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text('加载失败: $_error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadTransitData,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitList() {
    final lines = _getCurrentTabLines();

    if (lines.isEmpty) {
      // 显示备用选项
      return _buildFallbackOptions();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final isSelected = !_isFallbackMode && _selectedIndex == index;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedIndex = index;
              _isFallbackMode = false;
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF4A90D9).withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFF4A90D9) : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // 图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4A90D9) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      line.typeIcon,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.lineName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF4A90D9) : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            line.departureTime,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const Text(' → ', style: TextStyle(color: Colors.grey)),
                          Text(
                            line.arrivalTime,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      if (line.price != null)
                        Text(
                          '¥${line.price!.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.orange[700],
                          ),
                        ),
                    ],
                  ),
                ),
                // 选择指示
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF4A90D9),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 备用选项（当API无返回时显示）
  Widget _buildFallbackOptions() {
    final fallbackOptions = _getFallbackLines();
    if (fallbackOptions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '未能获取${_getCurrentTabName()}信息',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '请手动选择交通方式',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: fallbackOptions.length,
      itemBuilder: (context, index) {
        final line = fallbackOptions[index];
        final isSelected = _isFallbackMode && _selectedIndex == index;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedIndex = index;
              _isFallbackMode = true;
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF4A90D9).withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFF4A90D9) : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4A90D9) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(line.typeIcon, style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.lineName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF4A90D9) : Colors.black,
                        ),
                      ),
                      Text(
                        '预计${line.duration}分钟',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF4A90D9)),
              ],
            ),
          ),
        );
      },
    );
  }

  List<IntercityTransitLine> _getFallbackLines() {
    switch (_tabController.index) {
      case 0:
        // 飞机备用选项
        return [
          IntercityTransitLine(
            type: 'flight',
            lineName: 'CA1234',
            departureTime: '08:00',
            arrivalTime: '10:30',
            duration: 150,
          ),
          IntercityTransitLine(
            type: 'flight',
            lineName: 'MU5678',
            departureTime: '14:00',
            arrivalTime: '16:30',
            duration: 150,
          ),
        ];
      case 1:
        // 高铁备用选项
        return [
          IntercityTransitLine(
            type: 'train',
            lineName: 'G623',
            departureTime: '08:30',
            arrivalTime: '12:00',
            duration: 210,
          ),
          IntercityTransitLine(
            type: 'train',
            lineName: 'G625',
            departureTime: '14:30',
            arrivalTime: '18:00',
            duration: 210,
          ),
        ];
      case 2:
        // 汽车备用选项
        return [
          IntercityTransitLine(
            type: 'bus',
            lineName: '长途巴士',
            departureTime: '09:00',
            arrivalTime: '18:00',
            duration: 540,
          ),
        ];
      default:
        return [];
    }
  }

  List<IntercityTransitLine> _getCurrentTabLines() {
    switch (_tabController.index) {
      case 0:
        return _transitResult?.flights ?? [];
      case 1:
        return _transitResult?.trains ?? [];
      case 2:
        return _transitResult?.buses ?? [];
      default:
        return [];
    }
  }

  String _getCurrentTabName() {
    switch (_tabController.index) {
      case 0:
        return '航班';
      case 1:
        return '高铁';
      case 2:
        return '汽车';
      default:
        return '';
    }
  }

  void _confirmSelection() {
    IntercityTransitLine? selectedLine;

    if (_selectedIndex >= 0) {
      if (_isFallbackMode) {
        final fallback = _getFallbackLines();
        if (_selectedIndex < fallback.length) {
          selectedLine = fallback[_selectedIndex];
        }
      } else {
        final lines = _getCurrentTabLines();
        if (_selectedIndex < lines.length) {
          selectedLine = lines[_selectedIndex];
        }
      }
    }

    // 如果没有选择，使用默认选项
    if (selectedLine == null) {
      final lines = _getCurrentTabLines();
      if (lines.isNotEmpty) {
        selectedLine = lines.first;
      } else {
        final fallback = _getFallbackLines();
        if (fallback.isNotEmpty) {
          selectedLine = fallback.first;
        }
      }
    }

    if (selectedLine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择一个班次')),
      );
      return;
    }

    final transportType = selectedLine.type == 'flight'
        ? TransportType.flight
        : selectedLine.type == 'train'
            ? TransportType.highSpeedTrain
            : TransportType.bus;

    final transport = Transport(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: transportType,
      scope: TransportScope.intercity,
      flightNumber: selectedLine.lineName,
      departureTime: selectedLine.departureTime,
      arrivalTime: selectedLine.arrivalTime,
      durationMinutes: selectedLine.duration,
      distance: 0,
    );

    widget.onConfirm(transport);
    Navigator.pop(context);
  }
}
