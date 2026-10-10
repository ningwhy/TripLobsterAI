import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import '../models/trip_models.dart';
import '../services/amap_service.dart';
import '../widgets/transport_select_modal.dart';
import 'location_search_page.dart';
import 'transport_preference_page.dart';

class TripCreatePage extends StatefulWidget {
  final Trip? trip; // 如果传入trip则为编辑模式

  const TripCreatePage({super.key, this.trip});

  @override
  State<TripCreatePage> createState() => _TripCreatePageState();
}

class _TripCreatePageState extends State<TripCreatePage> {
  final _nameController = TextEditingController();
  final _amapService = AmapService();
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 2));
  List<Location> _locations = [];
  // 存储每段路程的路线信息
  final Map<String, AmapRoute?> _routeInfo = {};
  TripMode _tripMode = TripMode.pureTransit;
  TransportType _intercityPref = TransportType.flight;
  TransportType _intraCityPref = TransportType.taxi;
  /// 地点归属天（locationId → dayNumber）
  final Map<String, int> _dayOfLocation = {};
  bool get _isEditing => widget.trip != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      // 加载现有行程数据
      _nameController.text = widget.trip!.name;
      _startDate = widget.trip!.startDate;
      _endDate = widget.trip!.endDate;
      _tripMode = widget.trip!.tripMode;
      _locations = List.from(widget.trip!.allLocations);
      for (final day in widget.trip!.days) {
        for (final loc in day.locations) {
          _dayOfLocation[loc.id] = day.dayNumber;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final homeLocation = provider.homeLocation;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑行程' : '创建行程'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _showBackDialog(),
        ),
        actions: [
          TextButton(
            onPressed: _saveTrip,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Home Location
          if (homeLocation != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.home, color: Colors.white),
                title: const Text(
                  '我的家',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                subtitle: Text(
                  homeLocation.address,
                  style: const TextStyle(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit, color: Colors.white70, size: 18),
                onTap: () async {
                  final result = await Navigator.push<Location>(
                    context,
                    MaterialPageRoute(builder: (_) => const LocationSearchPage()),
                  );
                  if (result != null) {
                    final newHome = HomeLocation(
                      id: 'home',
                      name: result.name,
                      address: result.address,
                      latitude: result.latitude ?? 0,
                      longitude: result.longitude ?? 0,
                      city: result.city,
                      district: result.district,
                    );
                    await context.read<TripProvider>().setHomeLocation(newHome);
                  }
                },
              ),
            ),
            // 从家出发按钮
            if (_locations.isEmpty || _locations.first.type != LocationType.home)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton.icon(
                  onPressed: () {
                    final homeLoc = Location(
                      id: 'home_${DateTime.now().millisecondsSinceEpoch}',
                      name: homeLocation.name,
                      address: homeLocation.address,
                      latitude: homeLocation.latitude,
                      longitude: homeLocation.longitude,
                      city: homeLocation.city,
                      district: homeLocation.district,
                      type: LocationType.home,
                    );
                    setState(() {
                      _locations.insert(0, homeLoc);
                    });
                  },
                  icon: const Icon(Icons.home, size: 18),
                  label: const Text('从家出发'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],

          // 交通偏好设置按钮
          Container(
            margin: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () async {
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TransportPreferencePage(
                      initialMode: _tripMode,
                      initialIntercity: _intercityPref,
                      initialIntraCity: _intraCityPref,
                    ),
                  ),
                );
                if (result != null) {
                  setState(() {
                    _tripMode = result['tripMode'] ?? _tripMode;
                    _intercityPref = result['bigTransport'] ?? _intercityPref;
                    _intraCityPref = result['smallTransport'] ?? _intraCityPref;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('交通偏好已设置')),
                  );
                }
              },
              icon: const Icon(Icons.directions_car, size: 18),
              label: Text(_tripModeLabel),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Trip Name
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: '请输入行程名称',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Date Range
          Row(
            children: [
              Expanded(
                child: _buildDatePicker(
                  label: '开始日期',
                  date: _startDate,
                  onChanged: (date) {
                    setState(() {
                      _startDate = date;
                      if (_endDate.isBefore(_startDate)) {
                        _endDate = _startDate;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDatePicker(
                  label: '结束日期',
                  date: _endDate,
                  onChanged: (date) => setState(() => _endDate = date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_endDate.difference(_startDate).inDays + 1}天行程',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),

          const SizedBox(height: 24),

          // Default Transport
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '行程类型',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('🚗 纯自驾'),
                      selected: _tripMode == TripMode.pureDrive,
                      onSelected: (_) => setState(() => _tripMode = TripMode.pureDrive),
                    ),
                    ChoiceChip(
                      label: const Text('🚄 纯公共交通'),
                      selected: _tripMode == TripMode.pureTransit,
                      onSelected: (_) => setState(() => _tripMode = TripMode.pureTransit),
                    ),
                    ChoiceChip(
                      label: const Text('🛬 公交+落地租车'),
                      selected: _tripMode == TripMode.transitPlusRental,
                      onSelected: (_) => setState(() => _tripMode = TripMode.transitPlusRental),
                    ),
                  ],
                ),
                if (_tripMode != TripMode.pureDrive) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(padding: EdgeInsets.only(top: 8), child: Text('跨城: ')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('✈️ 飞机'),
                              selected: _intercityPref == TransportType.flight,
                              onSelected: (_) => setState(() => _intercityPref = TransportType.flight),
                            ),
                            ChoiceChip(
                              label: const Text('🚄 高铁'),
                              selected: _intercityPref == TransportType.highSpeedTrain,
                              onSelected: (_) => setState(() => _intercityPref = TransportType.highSpeedTrain),
                            ),
                            ChoiceChip(
                              label: const Text('🚌 大巴'),
                              selected: _intercityPref == TransportType.bus,
                              onSelected: (_) => setState(() => _intercityPref = TransportType.bus),
                            ),
                            ChoiceChip(
                              label: const Text('⛴️ 轮船'),
                              selected: _intercityPref == TransportType.ship,
                              onSelected: (_) => setState(() => _intercityPref = TransportType.ship),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(padding: EdgeInsets.only(top: 8), child: Text('同城: ')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('🚕 打车'),
                              selected: _intraCityPref == TransportType.taxi,
                              onSelected: (_) => setState(() => _intraCityPref = TransportType.taxi),
                            ),
                            ChoiceChip(
                              label: const Text('🚇 地铁'),
                              selected: _intraCityPref == TransportType.subway,
                              onSelected: (_) => setState(() => _intraCityPref = TransportType.subway),
                            ),
                            ChoiceChip(
                              label: const Text('🚌 公交'),
                              selected: _intraCityPref == TransportType.bus,
                              onSelected: (_) => setState(() => _intraCityPref = TransportType.bus),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('纯自驾行程无交通枢纽，长距离将自动提示服务区',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Timeline
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '行程时间线',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      onPressed: _addLocation,
                      icon: const Icon(Icons.add_circle),
                      color: const Color(0xFF4A90D9),
                    ),
                  ],
                ),
                const Divider(),

                // Hint
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lightbulb, color: Color(0xFF4A90D9), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '跨城交通自动触发：添加不同城市地点时，系统会自动弹出交通选择',
                          style: TextStyle(fontSize: 12, color: Color(0xFF4A90D9)),
                        ),
                      ),
                    ],
                  ),
                ),

                // Locations
                if (_locations.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('点击 + 添加地点'),
                    ),
                  )
                else
                  ...List.generate(_locations.length, (index) {
                    return _buildLocationItem(index);
                  }),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _showBackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存行程?'),
        content: const Text('是否保存当前行程?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(this.context);
            },
            child: const Text('不保存'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _saveTrip();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF4A90D9)),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime date,
    required ValueChanged<DateTime> onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '${date.month}/${date.day}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationItem(int index) {
    final location = _locations[index];

    // 检查是否需要显示交通信息（只要有交通信息就显示）
    final showTransport = index > 0 && location.transport != null;
    // 简化：只要有交通信息就显示，不再严格判断跨城
    // 因为用户手动选择了交通方式，应该显示

    return Column(
      children: [
        // 显示交通信息（有交通信息时显示）
        if (showTransport)
          Container(
            margin: const EdgeInsets.only(left: 20, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _transportIcon(location.transport!.type),
                  size: 16,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                // 显示出发时间 -> 到达时间
                Text(
                  '${location.transport!.departureTime ?? '--'} → ${location.transport!.arrivalTime ?? '--'}',
                  style: const TextStyle(fontSize: 12, color: Colors.orange),
                ),
                // 显示班次/车次
                if (location.transport!.flightNumber != null && location.transport!.flightNumber!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    location.transport!.flightNumber!,
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ],
                // 显示时长
                if (location.transport!.durationMinutes != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${_formatDuration(location.transport!.durationMinutes!)})',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                  ),
                ],
              ],
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getTypeColor(location.type).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getTypeIcon(location.type),
              color: _getTypeColor(location.type),
              size: 20,
            ),
          ),
          title: Text(location.name),
          subtitle: Text(
            location.address,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.grey),
            onPressed: () {
              setState(() {
                _locations.removeAt(index);
              });
            },
          ),
        ),
      ],
    );
  }

  void _addLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocationSearchPage()),
    );

    if (result != null && result is Location) {
      // 选择归属天（点+线模型：每个点归属某一天）
      await _pickDayFor(result);

      // 如果有上一个地点，先计算路线
      if (_locations.isNotEmpty) {
        final previousLocation = _locations.last;

        // 判断是否同城
        final isInterCity = !previousLocation.isSameCity(result);

        // 显示加载中
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(isInterCity ? '正在计算跨城路线...' : '正在计算同城路线...'),
                ],
              ),
              duration: const Duration(seconds: 10),
            ),
          );
        }

        // 计算路线：自驾类用驾车路线；纯公交模式同城优先公交路线
        if (previousLocation.longitude != null && previousLocation.latitude != null &&
            result.longitude != null && result.latitude != null) {
          AmapRoute? route;
          if (_tripMode == TripMode.pureTransit && !isInterCity) {
            route = await _amapService.transitRoute(
              originLng: previousLocation.longitude!,
              originLat: previousLocation.latitude!,
              destinationLng: result.longitude!,
              destinationLat: result.latitude!,
              city: previousLocation.cityName,
            );
          }
          route ??= await _amapService.drivingRoute(
            originLng: previousLocation.longitude!,
            originLat: previousLocation.latitude!,
            destinationLng: result.longitude!,
            destinationLat: result.latitude!,
          );

          // 存储路线信息
          final routeKey = '${previousLocation.id}_${result.id}';
          _routeInfo[routeKey] = route;

          // 更新交通时间
          if (route != null && route.paths.isNotEmpty) {
            result.transportMinutes = route.duration;
            // 保存默认交通方式（根据同城/跨城设置）
            result.transport = Transport(
              type: _tripMode == TripMode.pureDrive
                  ? TransportType.selfDrive
                  : (isInterCity ? _intercityPref : _intraCityPref),
              scope: isInterCity ? TransportScope.intercity : TransportScope.intraCity,
              durationMinutes: route.duration,
              distance: route.distance.toDouble(),
            );
          }

          // 关闭加载提示
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        } else {
          // 关闭加载提示
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        }
      }

      setState(() {
        _locations.add(result);
      });

      // 跨城时弹出交通选择弹窗
      if (_locations.length > 1) {
        final previousLocation = _locations[_locations.length - 2];
        if (!previousLocation.isSameCity(result)) {
          // 延迟一下，让UI先更新
          Future.delayed(const Duration(milliseconds: 100), () {
            _showTransportModal(previousLocation, result);
          });
        }
      }
    }
  }

  void _showTransportModal(Location from, Location to) {
    // 获取已计算的路线信息
    final routeKey = '${from.id}_${to.id}';
    final routeInfo = _routeInfo[routeKey];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransportSelectModal(
        fromLocation: from,
        toLocation: to,
        routeInfo: routeInfo,
        onConfirm: (transport) {
          setState(() {
            // 添加交通信息到目的地
            to.transport = transport;

            // 计算到达时间
            final depTime = transport.departureTime;
            if (depTime != null && depTime != '--:--' && transport.durationMinutes != null) {
              // 解析出发时间
              final parts = depTime.split(':');
              if (parts.length == 2) {
                final hour = int.tryParse(parts[0]) ?? 0;
                final minute = int.tryParse(parts[1]) ?? 0;
                final departureMinutes = hour * 60 + minute;

                // 计算到达时间
                final arrivalMinutes = departureMinutes + transport.durationMinutes!;
                final arrivalHour = (arrivalMinutes ~/ 60) % 24;
                final arrivalMinute = arrivalMinutes % 60;

                // 更新到达时间
                to.transport = Transport(
                  id: transport.id,
                  type: transport.type,
                  scope: transport.scope,
                  flightNumber: transport.flightNumber,
                  departureTime: depTime,
                  arrivalTime: '${arrivalHour.toString().padLeft(2, '0')}:${arrivalMinute.toString().padLeft(2, '0')}',
                  durationMinutes: transport.durationMinutes,
                  distance: transport.distance,
                );
              }
            }
          });
        },
      ),
    );
  }

  IconData _transportIcon(TransportType type) {
    switch (type) {
      case TransportType.flight:
        return Icons.flight;
      case TransportType.highSpeedTrain:
      case TransportType.train:
        return Icons.train;
      case TransportType.ship:
        return Icons.directions_boat;
      case TransportType.selfDrive:
        return Icons.directions_car;
      case TransportType.taxi:
        return Icons.local_taxi;
      case TransportType.subway:
        return Icons.subway;
      case TransportType.walk:
        return Icons.directions_walk;
      default:
        return Icons.directions_bus;
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

  /// 格式化时长显示
  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes分钟';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) {
        return '$hours小时';
      }
      return '$hours小时$mins分钟';
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

  String get _tripModeLabel {
    switch (_tripMode) {
      case TripMode.pureDrive:
        return '🚗 纯自驾';
      case TripMode.transitPlusRental:
        return '🛬 公交+落地租车';
      case TripMode.pureTransit:
        final big = _intercityPref == TransportType.flight
            ? '✈️ 飞机'
            : (_intercityPref == TransportType.ship
                ? '⛴️ 轮船'
                : (_intercityPref == TransportType.bus ? '🚌 大巴' : '🚄 高铁'));
        final small = _intraCityPref == TransportType.subway
            ? '🚇 地铁'
            : (_intraCityPref == TransportType.bus ? '🚌 公交' : '🚕 打车');
        return '$big + $small';
    }
  }

  Future<void> _pickDayFor(Location loc) async {
    final dayCount = _endDate.difference(_startDate).inDays + 1;
    if (dayCount <= 1) {
      _dayOfLocation[loc.id] = 1;
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('添加到哪一天？', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            ...List.generate(dayCount, (i) {
              final date = _startDate.add(Duration(days: i));
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE2F3DA),
                  child: Text('${i + 1}', style: const TextStyle(color: Color(0xFF4CA84A), fontWeight: FontWeight.bold)),
                ),
                title: Text('第${i + 1}天 · ${date.month}/${date.day}'),
                onTap: () => Navigator.pop(ctx, i + 1),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    _dayOfLocation[loc.id] = picked ?? 1;
  }

  void _saveTrip() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入行程名称')),
      );
      return;
    }

    // 按“地点归属天”构建天数（点+线模型：点归属到天，线连接点）
    final dayCount = _endDate.difference(_startDate).inDays + 1;
    final fallbackDay = _isEditing ? dayCount : 1;
    final days = <TripDay>[];
    for (var i = 0; i < dayCount; i++) {
      final dayNumber = i + 1;
      days.add(TripDay(
        date: _startDate.add(Duration(days: i)),
        dayNumber: dayNumber,
        locations: _locations
            .where((l) => ((_dayOfLocation[l.id] ?? fallbackDay).clamp(1, dayCount)) == dayNumber)
            .toList(),
      ));
    }

    if (_isEditing) {
      // 更新现有行程（保留地点归属，不再清空）
      final updatedTrip = widget.trip!;
      updatedTrip.name = _nameController.text;
      updatedTrip.startDate = _startDate;
      updatedTrip.endDate = _endDate;
      updatedTrip.tripMode = _tripMode;
      updatedTrip.days = days;

      context.read<TripProvider>().updateTrip(updatedTrip);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('行程更新成功')),
      );
    } else {
      // 创建新行程
      final trip = Trip(
        name: _nameController.text,
        startDate: _startDate,
        endDate: _endDate,
        days: days,
        homeLocation: context.read<TripProvider>().homeLocation,
        tripMode: _tripMode,
      );

      context.read<TripProvider>().createTrip(trip);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('行程创建成功')),
      );
    }
  }
}
