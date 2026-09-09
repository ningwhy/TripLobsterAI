import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/trip_models.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import '../providers/trip_provider.dart';
import 'trip_create_page.dart';
import 'trip_map_page.dart';
import 'location_search_page.dart';

/// 行程预览：时间轴 + 渐变地点卡 + 交通行 + 天气/停留信息（参考视觉稿）
class TripPreviewPage extends StatefulWidget {
  final Trip trip;

  const TripPreviewPage({super.key, required this.trip});

  @override
  State<TripPreviewPage> createState() => _TripPreviewPageState();
}

class _Slot {
  final Location location;
  final int arrival; // 分钟
  final int leave;
  final int? travelMinutes;
  _Slot(this.location, this.arrival, this.leave, this.travelMinutes);
}

class _TripPreviewPageState extends State<TripPreviewPage> {
  int _selectedDayIndex = 0;
  final Map<int, int?> _dayTemp = {}; // dayIndex -> 当日最高温
  bool _weatherLoading = false;

  static const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    if (_weatherLoading) return;
    _weatherLoading = true;
    final days = widget.trip.days;
    for (var i = 0; i < days.length; i++) {
      final locWithCoord = days[i].locations.firstWhere(
        (l) => l.latitude != null && l.longitude != null,
        orElse: () => days[i].locations.isNotEmpty ? days[i].locations.first : Location(name: '', address: '', type: LocationType.other),
      );
      if (locWithCoord.latitude == null) continue;
      try {
        final w = await ApiClient.weather(locWithCoord.latitude!, locWithCoord.longitude!);
        final times = (w['daily']?['time'] as List?)?.cast<String>() ?? [];
        final temps = (w['daily']?['temperature_2m_max'] as List?)?.cast<num>() ?? [];
        final dateStr = DateFormat('yyyy-MM-dd').format(days[i].date);
        final idx = times.indexOf(dateStr);
        if (idx >= 0 && idx < temps.length) {
          if (mounted) setState(() => _dayTemp[i] = temps[idx].round());
        }
      } catch (_) {
        // 天气失败静默降级
      }
    }
    _weatherLoading = false;
  }

  List<TripDay> get _days => widget.trip.days.isEmpty
      ? List.generate(
          3,
          (i) => TripDay(
            date: widget.trip.startDate.add(Duration(days: i)),
            dayNumber: i + 1,
            locations: [],
          ),
        )
      : widget.trip.days;

  String _fmt(int min) {
    final m = ((min % 1440) + 1440) % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String _dur(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    if (h == 0) return '$m分钟';
    return m == 0 ? '$h小时' : '$h小时$m分';
  }

  List<_Slot> _slots(TripDay day) {
    int clock = 9 * 60;
    final out = <_Slot>[];
    for (final loc in day.locations) {
      final travel = (loc.transportMinutes != null && loc.transportMinutes! > 0) ? loc.transportMinutes : null;
      if (travel != null) clock += travel;
      final stay = loc.stayMinutes ?? 60;
      out.add(_Slot(loc, clock, clock + stay, travel));
      clock += stay;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    if (_selectedDayIndex >= days.length) _selectedDayIndex = 0;
    final day = days[_selectedDayIndex];

    return Scaffold(
      backgroundColor: AppColors.mintBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('行程预览', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: '编辑行程',
            onPressed: () {
              context.read<TripProvider>().setCurrentTrip(widget.trip);
              Navigator.push(context, MaterialPageRoute(builder: (_) => TripCreatePage(trip: widget.trip)));
            },
          ),
          IconButton(
            icon: const Icon(Icons.ios_share, size: 20),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('行程分享海报（路线图）功能开发中，敬请期待')),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildMetaCard(days),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                _buildDayStrip(day),
                const SizedBox(height: 12),
                if (day.locations.isEmpty)
                  _buildEmptyDay()
                else
                  ..._slots(day).map((s) => _buildTimelineEntry(s, day.locations.indexOf(s.location) == day.locations.length - 1)),
                const SizedBox(height: 16),
                _buildCostCard(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _fab(Icons.map_outlined, const Color(0xFFFF9F43), () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => TripMapPage(trip: widget.trip)));
          }),
          const SizedBox(height: 12),
          _fab(Icons.add, AppColors.green, _addLocationToDay),
        ],
      ),
    );
  }

  Widget _fab(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  // ---------- 顶部信息卡 + 天数选择 ----------
  Widget _buildMetaCard(List<TripDay> days) {
    final trip = widget.trip;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('出发日期', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              const SizedBox(width: 10),
              Text(
                DateFormat('yyyy-MM-dd').format(trip.startDate),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const Spacer(),
              const Text('出行人', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              const SizedBox(width: 6),
              if (trip.members.isEmpty)
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: AppColors.mintCircle, shape: BoxShape.circle),
                  child: const Center(child: Text('🧳', style: TextStyle(fontSize: 13))),
                )
              else
                ...trip.members.take(4).map((m) => Container(
                      width: 26,
                      height: 26,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(color: AppColors.sky, shape: BoxShape.circle),
                      child: Center(
                        child: Text(
                          m.name.isNotEmpty ? m.name[0] : '👤',
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    )),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final selected = i == _selectedDayIndex;
                final d = days[i];
                return GestureDetector(
                  onTap: () => setState(() => _selectedDayIndex = i),
                  child: Container(
                    width: 52,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.green : AppColors.mintBg,
                      borderRadius: BorderRadius.circular(14),
                      border: selected ? null : Border.all(color: const Color(0xFFE3EDE2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${d.dayNumber}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${d.date.month}/${d.date.day}',
                          style: TextStyle(
                            fontSize: 10,
                            color: selected ? Colors.white70 : AppColors.textSub,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayStrip(TripDay day) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.mintCircle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            '${day.date.year}.${day.date.month.toString().padLeft(2, '0')}.${day.date.day.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.greenDark),
          ),
          const SizedBox(width: 10),
          Text(
            _weekdays[day.date.weekday - 1],
            style: const TextStyle(fontSize: 12, color: AppColors.greenDark),
          ),
          const Spacer(),
          Text(
            '${day.locations.length}个地点',
            style: const TextStyle(fontSize: 11, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.calendar_month_outlined, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text('这一天还没有安排', style: TextStyle(fontSize: 14, color: AppColors.textSub)),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: _addLocationToDay,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加地点'),
            style: TextButton.styleFrom(foregroundColor: AppColors.greenDark),
          ),
        ],
      ),
    );
  }

  // ---------- 时间轴条目 ----------
  Widget _buildTimelineEntry(_Slot slot, bool isLast) {
    final loc = slot.location;
    final grad = _gradient(loc.type);
    final dotColor = grad.colors.first;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间列
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _fmt(slot.arrival),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSub),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 节点 + 竖线
          Column(
            children: [
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: dotColor.withOpacity(0.4), blurRadius: 4)],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: const Color(0xFFDCE8DC)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // 卡片列
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (slot.travelMinutes != null || loc.transport != null) _buildTransportRow(loc, slot.travelMinutes),
                _buildLocationCard(loc, slot, grad),
                _buildStayRow(loc, slot),
                SizedBox(height: isLast ? 0 : 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportRow(Location loc, int? travelMinutes) {
    IconData icon;
    String title;
    String sub;
    final t = loc.transport;
    if (t != null) {
      switch (t.type) {
        case TransportType.flight:
          icon = Icons.flight_takeoff_rounded;
          break;
        case TransportType.highSpeedTrain:
        case TransportType.train:
          icon = Icons.train_rounded;
          break;
        case TransportType.ship:
          icon = Icons.directions_boat_rounded;
          break;
        default:
          icon = Icons.directions_bus_rounded;
      }
      title = t.flightNumber ?? t.displayName.replaceAll(RegExp(r'[^\u4e00-\u9fa5A-Za-z0-9]'), '');
      sub = [
        if (t.departureTime != null && t.arrivalTime != null) '${t.departureTime} → ${t.arrivalTime}',
        if (t.durationMinutes != null) _dur(t.durationMinutes!),
        if (t.distance != null) '${(t.distance! / 1000).toStringAsFixed(0)}公里',
      ].join(' · ');
      if (sub.isEmpty) sub = t.displayName;
    } else {
      final mins = travelMinutes ?? 0;
      final walk = mins <= 25;
      icon = walk ? Icons.directions_walk_rounded : Icons.directions_transit_rounded;
      title = walk ? '步行' : '公共交通';
      sub = '约${_dur(mins)}到达';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 17, color: AppColors.textSub),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (sub.isNotEmpty)
                  Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC4D2C4)),
        ],
      ),
    );
  }

  Widget _buildLocationCard(Location loc, _Slot slot, LinearGradient grad) {
    final temp = _dayTemp[_selectedDayIndex];
    return GestureDetector(
      onTap: () => _showLocationSheet(loc),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          gradient: grad,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: grad.colors.last.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(loc.type), color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    loc.address,
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (temp != null)
                  Text('$temp°C', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white))
                else
                  Text('--°', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(slot.arrival)}到达',
                  style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.85)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStayRow(Location loc, _Slot slot) {
    final stay = loc.stayMinutes;
    if (stay == null || stay <= 0) return const SizedBox(height: 6);
    final open = (loc.openTime != null && loc.closeTime != null) ? ' · 营业 ${loc.openTime}-${loc.closeTime}' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.schedule, size: 12, color: Color(0xFFFF9F43)),
          const SizedBox(width: 4),
          Text(
            '停留时间：${_dur(stay)}$open',
            style: const TextStyle(fontSize: 11, color: Color(0xFFE58E26)),
          ),
        ],
      ),
    );
  }

  // ---------- 费用卡 ----------
  Widget _buildCostCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppColors.greenDark),
              const SizedBox(width: 6),
              const Text('费用预估', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const Spacer(),
              Text(
                '¥${_calculateTotalCost()}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF6600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _costItem('交通', '¥${_calculateTransportCost()}'),
              _costItem('住宿', '¥${_calculateHotelCost()}'),
              _costItem('餐饮', '¥${_calculateFoodCost()}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _costItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFFF6600))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
      ],
    );
  }

  // ---------- 交互 ----------
  Future<void> _addLocationToDay() async {
    final result = await Navigator.push<Location>(
      context,
      MaterialPageRoute(builder: (_) => const LocationSearchPage()),
    );
    if (result == null || !mounted) return;
    final trip = widget.trip;
    final days = List<TripDay>.from(trip.days);
    final i = _selectedDayIndex;
    if (i >= days.length) return;
    final day = days[i];
    final locations = List<Location>.from(day.locations)..add(result);
    days[i] = TripDay(id: day.id, date: day.date, dayNumber: day.dayNumber, locations: locations);
    trip.days = days;
    await context.read<TripProvider>().updateTrip(trip);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加「${result.name}」到第${day.dayNumber}天')),
    );
  }

  void _showLocationSheet(Location loc) {
    final isHotel = loc.type == LocationType.hotel;
    final cands = (loc.hotelCandidates ?? []).where((c) => c['name'] != loc.name).toList();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(loc.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
            if (isHotel && cands.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('换一家（AI 已按位置/口碑/星级/预算筛过）', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ),
              ),
              ...cands.map((c) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.hotel_rounded, size: 20, color: AppColors.greenDark),
                    title: Text(c['name']?.toString() ?? '', style: const TextStyle(fontSize: 14)),
                    subtitle: Text(c['reason']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchHotel(loc, c);
                    },
                  )),
              const Divider(height: 1, indent: 20, endIndent: 20),
            ],
            ListTile(
              leading: const Icon(Icons.timelapse_outlined, color: AppColors.greenDark),
              title: const Text('调整停留时长'),
              onTap: () {
                Navigator.pop(ctx);
                _editStay(loc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('从行程中移除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _removeLocation(loc);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _switchHotel(Location loc, Map<String, dynamic> cand) async {
    loc.name = cand['name']?.toString() ?? loc.name;
    loc.address = cand['address']?.toString() ?? loc.address;
    loc.latitude = (cand['latitude'] as num?)?.toDouble() ?? loc.latitude;
    loc.longitude = (cand['longitude'] as num?)?.toDouble() ?? loc.longitude;
    await context.read<TripProvider>().updateTrip(widget.trip);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已切换酒店，次日出发交通时长可重新编辑校准')),
    );
  }

  void _editStay(Location loc) {
    final options = [30, 60, 90, 120, 150, 180, 240];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('停留时长', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: options.map((m) {
                  final selected = loc.stayMinutes == m;
                  return ChoiceChip(
                    label: Text(_dur(m)),
                    selected: selected,
                    onSelected: (_) async {
                      Navigator.pop(ctx);
                      loc.stayMinutes = m;
                      await context.read<TripProvider>().updateTrip(widget.trip);
                      if (mounted) setState(() {});
                    },
                    selectedColor: AppColors.mintCircle,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: selected ? AppColors.greenDark : AppColors.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeLocation(Location loc) async {
    final trip = widget.trip;
    final days = List<TripDay>.from(trip.days);
    final i = _selectedDayIndex;
    if (i >= days.length) return;
    final day = days[i];
    final locations = List<Location>.from(day.locations)..removeWhere((l) => l.id == loc.id);
    days[i] = TripDay(id: day.id, date: day.date, dayNumber: day.dayNumber, locations: locations);
    trip.days = days;
    await context.read<TripProvider>().updateTrip(trip);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已移除「${loc.name}」')));
  }

  // ---------- 视觉映射 ----------
  LinearGradient _gradient(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return const LinearGradient(colors: [Color(0xFF6ECB63), Color(0xFF3FA34D)]);
      case LocationType.attraction:
        return const LinearGradient(colors: [Color(0xFFA29BFE), Color(0xFF7C6FF0)]);
      case LocationType.restaurant:
        return const LinearGradient(colors: [Color(0xFFFFB26B), Color(0xFFFA8A4F)]);
      case LocationType.shopping:
        return const LinearGradient(colors: [Color(0xFFFF8FA3), Color(0xFFF5576C)]);
      case LocationType.transport:
        return const LinearGradient(colors: [Color(0xFFB0BEC5), Color(0xFF8FA3AD)]);
      case LocationType.home:
        return const LinearGradient(colors: [Color(0xFF4DD0E1), Color(0xFF26B8CA)]);
      default:
        return const LinearGradient(colors: [Color(0xFF90A8B8), Color(0xFF78909C)]);
    }
  }

  IconData _typeIcon(LocationType type) {
    switch (type) {
      case LocationType.hotel:
        return Icons.hotel_rounded;
      case LocationType.attraction:
        return Icons.attractions_rounded;
      case LocationType.restaurant:
        return Icons.restaurant_rounded;
      case LocationType.shopping:
        return Icons.shopping_bag_rounded;
      case LocationType.transport:
        return Icons.directions_bus_rounded;
      case LocationType.home:
        return Icons.home_rounded;
      default:
        return Icons.place_rounded;
    }
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
    final nights = widget.trip.totalDays > 0 ? widget.trip.totalDays - 1 : 0;
    return nights * 400;
  }

  int _calculateFoodCost() => widget.trip.totalDays * 100;

  int _calculateTotalCost() => _calculateTransportCost() + _calculateHotelCost() + _calculateFoodCost();
}
