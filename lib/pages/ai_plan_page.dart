import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/trip_models.dart';
import '../providers/trip_provider.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import 'location_search_page.dart';
import 'trip_preview_page.dart';

/// P0-2 AI 智能行程生成
/// 交互原则（AI 副驾）：AI 给建议，用户做决策 —— 生成后先预览，可采纳后继续手动编辑
class AiPlanPage extends StatefulWidget {
  final String? initialCity;

  const AiPlanPage({super.key, this.initialCity});

  @override
  State<AiPlanPage> createState() => _AiPlanPageState();
}

class _AiPlanPageState extends State<AiPlanPage> {
  static const _interests = [
    {'key': 'nature', 'label': '自然风光'},
    {'key': 'culture', 'label': '历史人文'},
    {'key': 'museum', 'label': '博物馆'},
    {'key': 'fun', 'label': '主题乐园'},
    {'key': 'shopping', 'label': '购物商圈'},
    {'key': 'arts', 'label': '文艺打卡'},
  ];

  final _cityController = TextEditingController();
  final _mustController = TextEditingController();
  final _descController = TextEditingController();
  DateTime _startDate = DateTime.now().add(const Duration(days: 14));
  int _days = 3;
  String _pace = 'normal';
  final Set<String> _selectedInterests = {'nature', 'culture'};

  bool _generating = false;
  Map<String, dynamic>? _result;
  String? _error;
  TripMode _tripMode = TripMode.pureTransit;
  String _intercityVehicle = 'highSpeedTrain';
  int _adults = 2;
  int _children = 0;
  int _rooms = 1;
  RoomType? _roomType;
  String _budget = 'comfort';

  @override
  void initState() {
    super.initState();
    if (widget.initialCity != null && widget.initialCity!.isNotEmpty) {
      _cityController.text = widget.initialCity!;
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _mustController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final city = _cityController.text.trim();
    if (city.isEmpty) {
      setState(() => _error = '请填写目的地城市');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
      _result = null;
    });
    try {
      final provider = context.read<TripProvider>();
      final result = await ApiClient.generatePlan(
        city: city,
        days: _days,
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        pace: _pace,
        interests: _selectedInterests.toList(),
        tripMode: _tripMode.name,
        intercityVehicle: _intercityVehicle,
        description: _descController.text.trim(),
        fromCity: provider.homeLocation?.city,
        adults: _adults,
        children: _children,
        rooms: _rooms,
        roomType: _roomType?.name,
        budget: _budget,
        mustVisit: _mustController.text
            .split(RegExp(r'[,，、\s]+'))
            .where((e) => e.trim().isNotEmpty)
            .take(5)
            .toList(),
      );
      setState(() => _result = result);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '生成失败，请稍后再试');
    } finally {
      setState(() => _generating = false);
    }
  }

  Future<void> _adopt() async {
    final trip = _buildTrip(_result!);
    final provider = context.read<TripProvider>();
    await provider.createTrip(trip);
    if (!mounted) return;
    Navigator.of(context).pop();
    await provider.autoSync();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TripPreviewPage(trip: trip)),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已采纳 AI 行程，可继续手动调整每个地点')),
    );
  }

  /// 服务端 cost 可能是字符串（"300-500" / "544.00"）也可能是空数组（实测酒店/景点为 []）。
  /// 空数组/非字符串 → null，避免把 "[]" 当成价格。
  String? _costString(dynamic raw) {
    if (raw is String) return raw.isEmpty ? null : raw;
    if (raw is num) return raw.toString();
    return null;
  }

  /// 必去点命中：按用户在"必去点"输入框里填的名称做包含匹配（客户端维护，不依赖服务端 _must）
  bool _isMustVisit(String name) {
    final keys = _mustController.text
        .split(RegExp(r'[,，、;；\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (name.isEmpty || keys.isEmpty) return false;
    return keys.any((k) => name.contains(k) || k.contains(name));
  }

  /// 交通段映射（服务端 planner.js toLocation / multiCity.js 产出）
  Transport? _buildTransport(dynamic raw) {
    if (raw is! Map) return null;
    final t = Map<String, dynamic>.from(raw);
    return Transport(
      type: TransportType.values.firstWhere(
        (e) => e.name == t['type'],
        orElse: () => TransportType.other,
      ),
      scope: TransportScope.values.firstWhere(
        (e) => e.name == t['scope'],
        orElse: () => TransportScope.intraCity,
      ),
      flightNumber: t['flightNumber'] as String?,
      departureTime: t['departureTime'] as String?,
      arrivalTime: t['arrivalTime'] as String?,
      durationMinutes: (t['durationMinutes'] as num?)?.round(),
      distance: (t['distance'] as num?)?.toDouble(),
      price: t['price'] as num?,
      isFixed: t['isFixed'] as bool?,
      estimated: t['estimated'] as bool?,
    );
  }

  Trip _buildTrip(Map<String, dynamic> result) {
    final tripData = Map<String, dynamic>.from(result['trip'] as Map);
    final now = DateTime.now();
    final days = (tripData['days'] as List).map((d) {
      final day = Map<String, dynamic>.from(d as Map);
      return TripDay(
        date: DateTime.parse(day['date'] as String),
        dayNumber: day['dayNumber'] as int,
        locations: (day['locations'] as List).map((l) {
          final loc = Map<String, dynamic>.from(l as Map);
          return Location(
            name: loc['name'] ?? '',
            address: loc['address'] ?? '',
            latitude: (loc['latitude'] as num?)?.toDouble(),
            longitude: (loc['longitude'] as num?)?.toDouble(),
            city: loc['city'],
            district: loc['district'],
            type: LocationType.values.firstWhere(
              (e) => e.name == loc['type'],
              orElse: () => LocationType.attraction,
            ),
            hubKind: loc['hubKind'],
            stayMinutes: loc['stayMinutes'],
            transportMinutes: loc['transportMinutes'],
            openTime: loc['openTime'],
            closeTime: loc['closeTime'],
            hotelCandidates: (loc['hotelCandidates'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
            // ---- T02 补映射：把服务端已产出的字段接进模型（缺则保持 null，不编造）----
            // 注：generate 管线**不产出** arrivalTime/leaveTime（那是 corridor 管线的能力），
            //     这两个字段在 AI 生成行程里恒为 null，预览页会回退 _slots() 推算 —— 预期行为。
            arrivalTime: loc['arrivalTime'] as String?,
            leaveTime: loc['leaveTime'] as String?,
            rating: (loc['rating'] as num?)?.toDouble(),
            stayNote: loc['stayNote'] as String?,
            // 酒店参考价原串（高德 biz_ext.cost）；实测酒店/景点该字段为空数组 → 解析后为 null
            cost: _costString(loc['cost']),
            // 【裁 4】必去点由**客户端**按 mustVisit 名称命中，不读服务端 _must（经 buildDay 后恒 false）
            fixed: _isMustVisit(loc['name']?.toString() ?? ''),
            transport: _buildTransport(loc['transport']),
          );
        }).toList(),
      );
    }).toList();

    return Trip(
      name: tripData['name'] ?? 'AI 生成行程',
      startDate: DateTime.parse(tripData['startDate'] as String),
      endDate: DateTime.parse(tripData['endDate'] as String),
      days: days,
      tripMode: TripMode.values.firstWhere(
        (e) => e.name == tripData['tripMode'],
        orElse: () => TripMode.pureTransit,
      ),
      homeLocation: context.read<TripProvider>().homeLocation,
      adults: _adults,
      children: _children,
      rooms: _rooms,
      roomType: _roomType,
      budget: _budget,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 帮我规划'),
        backgroundColor: const Color(0xFFF0F7FF),
      ),
      body: _generating
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90D9)),
                  SizedBox(height: 16),
                  Text('正在搜索真实景点并规划行程…', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  SizedBox(height: 4),
                  Text('地点与路线均来自高德真实数据', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          : _result != null
              ? _buildResultView(_result!)
              : _buildFormView(),
    );
  }

  Widget _buildFormView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F7FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF4A90D9), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '像跟团一样省心：说一句需求，AI 帮你排好每一天。\n所有地点均可预览、可修改、可放弃。',
                  style: TextStyle(fontSize: 12, color: Color(0xFF336699), height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _cityController,
          decoration: const InputDecoration(
            labelText: '目的地城市',
            hintText: '如：杭州、成都、大理',
            prefixIcon: Icon(Icons.location_city_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _buildDepartureRow(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('开始 ${DateFormat('M月d日').format(_startDate)}'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDays,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text('$_days 天'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('游玩节奏', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'relaxed', label: Text('轻松'), icon: Icon(Icons.self_improvement)),
            ButtonSegment(value: 'normal', label: Text('标准'), icon: Icon(Icons.balance)),
            ButtonSegment(value: 'packed', label: Text('特种兵'), icon: Icon(Icons.local_fire_department)),
          ],
          selected: {_pace},
          onSelectionChanged: (s) => setState(() => _pace = s.first),
        ),
        const SizedBox(height: 20),
        const Text('行程类型', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<TripMode>(
          segments: const [
            ButtonSegment(value: TripMode.pureDrive, label: Text('纯自驾'), icon: Icon(Icons.directions_car)),
            ButtonSegment(value: TripMode.pureTransit, label: Text('公共交通'), icon: Icon(Icons.directions_transit)),
            ButtonSegment(value: TripMode.transitPlusRental, label: Text('落地租车'), icon: Icon(Icons.flight_land)),
          ],
          selected: {_tripMode},
          onSelectionChanged: (s) => setState(() => _tripMode = s.first),
        ),
        if (_tripMode != TripMode.pureDrive) ...[
          const SizedBox(height: 14),
          const Text('跨城交通（你选工具，AI 只建议班次）', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'flight', label: Text('✈️ 飞机')),
              ButtonSegment(value: 'highSpeedTrain', label: Text('🚄 高铁')),
              ButtonSegment(value: 'bus', label: Text('🚌 大巴')),
              ButtonSegment(value: 'ship', label: Text('⛴️ 轮船')),
            ],
            selected: {_intercityVehicle},
            onSelectionChanged: (s) => setState(() => _intercityVehicle = s.first),
            showSelectedIcon: false,
          ),
        ],
        const SizedBox(height: 20),
        const Text('兴趣偏好', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _interests.map((i) {
            final selected = _selectedInterests.contains(i['key']);
            return FilterChip(
              label: Text(i['label']!),
              selected: selected,
              onSelected: (v) => setState(() {
                if (v) {
                  _selectedInterests.add(i['key']!);
                } else {
                  _selectedInterests.remove(i['key']!);
                }
              }),
              selectedColor: const Color(0xFFD6EAF8),
              checkmarkColor: const Color(0xFF4A90D9),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _mustController,
          decoration: const InputDecoration(
            labelText: '必去景点（可选，逗号分隔）',
            hintText: '如：西湖, 灵隐寺',
            prefixIcon: Icon(Icons.push_pin_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descController,
          maxLines: 3,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: '简短描述（AI 会据此调整行程）',
            hintText: '如：带爸妈和娃，想吃本地菜，节奏慢些\n首次去，想去经典景点',
            prefixIcon: Icon(Icons.edit_note),
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        const Text('出行人数与住宿', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _stepper('大人', _adults, (v) => setState(() => _adults = v), min: 1)),
            const SizedBox(width: 10),
            Expanded(child: _stepper('小孩', _children, (v) => setState(() => _children = v), min: 0)),
            const SizedBox(width: 10),
            Expanded(child: _stepper('房间', _rooms, (v) => setState(() => _rooms = v), min: 1)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final rt in RoomType.values)
              ChoiceChip(
                label: Text(rt.label),
                selected: _roomType == rt,
                onSelected: (_) => setState(() => _roomType = _roomType == rt ? null : rt),
                selectedColor: AppColors.mintCircle,
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('酒店预算', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'economy', label: Text('经济 · <¥200')),
            ButtonSegment(value: 'comfort', label: Text('舒适 · ¥200-500')),
            ButtonSegment(value: 'luxury', label: Text('高档 · >¥500')),
          ],
          selected: {_budget},
          onSelectionChanged: (s) => setState(() => _budget = s.first),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFC1C1)),
            ),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFCC3333), fontSize: 13)),
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _generate,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('一键生成行程'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A90D9),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildResultView(Map<String, dynamic> result) {
    final trip = Map<String, dynamic>.from(result['trip'] as Map);
    final days = trip['days'] as List;
    final warnings = (result['warnings'] as List? ?? []).cast<String>();
    final source = (result['stats']?['source'] ?? 'rule') as String;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip['name'] as String,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      source == 'rule' ? 'AI 建议' : 'AI 增强',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${trip['startDate']} 至 ${trip['endDate']} · ${days.length}天',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                '这是 AI 生成的建议行程，采纳后每个地点都可以修改、删除或替换。',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              ...days.map((d) {
                final day = Map<String, dynamic>.from(d as Map);
                final locations = (day['locations'] as List).cast<Map<dynamic, dynamic>>();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: day['dayNumber'] == 1,
                      title: Text(
                        '第${day['dayNumber']}天 · ${day['date']}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      children: locations.map((l) {
                        final loc = Map<String, dynamic>.from(l);
                        final isMeal = loc['mealFor'] != null;
                        final transport = loc['transportMinutes'] != null
                            ? '🚌 ${loc['transportMinutes']}分钟到达'
                            : '';
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isMeal ? Icons.restaurant : (loc['type'] == 'restaurant' ? Icons.restaurant : Icons.place),
                            size: 18,
                            color: isMeal ? Colors.orange : const Color(0xFF4A90D9),
                          ),
                          title: Text(loc['name'] ?? '', style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${loc['arrivalTime'] ?? ''} → ${loc['leaveTime'] ?? ''}'
                            '${loc['rating'] != null && (loc['rating'] as num) > 0 ? ' · 评分${loc['rating']}' : ''}'
                            '${transport.isNotEmpty ? ' · $transport' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              }),
              if (warnings.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFE082)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('⚠️ AI 提示', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      ...warnings.map((w) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(w, style: const TextStyle(fontSize: 12, height: 1.4)),
                          )),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _result = null),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('重新生成'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _adopt,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('采纳并编辑'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90D9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepper(String label, int value, ValueChanged<int> onChanged, {int min = 0, int max = 9}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3EDE2)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('$label $value', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary))),
          _stepBtn(Icons.remove_circle_outline, value > min, () => onChanged(value - 1)),
          _stepBtn(Icons.add_circle_outline, value < max, () => onChanged(value + 1)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 20),
      color: AppColors.greenDark,
      disabledColor: Colors.grey[300],
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      splashRadius: 16,
    );
  }

  /// 出发地行：默认取“家”，未设置时引导去没置
  Widget _buildDepartureRow() {
    return Consumer<TripProvider>(
      builder: (context, provider, _) {
        final home = provider.homeLocation;
        return InkWell(
          onTap: () async {
            final result = await Navigator.push<Location>(
              context,
              MaterialPageRoute(builder: (_) => const LocationSearchPage()),
            );
            if (result == null || !mounted) return;
            await provider.setHomeLocation(HomeLocation(
              id: 'home',
              name: result.name,
              address: result.address,
              latitude: result.latitude,
              longitude: result.longitude,
              city: result.city,
              district: result.district,
            ));
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE3EDE2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.home_outlined, size: 18, color: Color(0xFF4CA84A)),
                const SizedBox(width: 8),
                const Text('出发地', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    home != null ? (home.city != null && home.city!.isNotEmpty ? home.city! : home.name) : '未设置，点击选择家的位置',
                    style: TextStyle(
                      fontSize: 13,
                      color: home != null ? const Color(0xFF2E4A38) : const Color(0xFFE58E26),
                      fontWeight: home != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  home != null ? Icons.check_circle : Icons.chevron_right,
                  size: 16,
                  color: home != null ? const Color(0xFF4CA84A) : Colors.grey,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickDays() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: List.generate(10, (i) => i + 1).map((n) {
            return InkWell(
              onTap: () => Navigator.pop(ctx, n),
              child: Container(
                width: MediaQuery.of(ctx).size.width / 5,
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: Text('$n天', style: TextStyle(fontSize: 15, fontWeight: n == _days ? FontWeight.bold : FontWeight.normal, color: n == _days ? const Color(0xFF4A90D9) : null)),
              ),
            );
          }).toList(),
        ),
      ),
    );
    if (picked != null) setState(() => _days = picked);
  }
}
