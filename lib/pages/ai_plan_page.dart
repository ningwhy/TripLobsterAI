import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/trip_models.dart';
import '../providers/trip_provider.dart';
import '../services/api_client.dart';
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
  DateTime _startDate = DateTime.now().add(const Duration(days: 14));
  int _days = 3;
  String _pace = 'normal';
  final Set<String> _selectedInterests = {'nature', 'culture'};

  bool _generating = false;
  Map<String, dynamic>? _result;
  String? _error;
  TripMode _tripMode = TripMode.pureTransit;

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
      final result = await ApiClient.generatePlan(
        city: city,
        days: _days,
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        pace: _pace,
        interests: _selectedInterests.toList(),
        tripMode: _tripMode.name,
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
