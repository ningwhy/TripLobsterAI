import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import '../models/trip_models.dart';
import '../theme/app_colors.dart';
import '../services/api_client.dart';
import 'trip_create_page.dart';
import 'trip_preview_page.dart';
import 'footprint_page.dart';
import 'location_search_page.dart';
import 'ai_plan_page.dart';
import 'cloud_settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  Timer? _clockTimer;
  String _clock = '';
  final GlobalKey _tripSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tickClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tickClock());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TripProvider>().autoSync();
    });
  }

  void _tickClock() {
    final now = DateFormat('H:mm').format(DateTime.now());
    if (now != _clock) setState(() => _clock = now);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mintBg,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            _buildHomeTab(),
            const FootprintPage(),
            _buildGalleryTab(),
            _buildMineTab(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ================= 底部导航（中间飞机 FAB） =================
  Widget _buildBottomBar() {
    return SizedBox(
      height: 78,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 62,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  _navItem(0, Icons.home_rounded, '首页'),
                  _navItem(1, Icons.map_outlined, '旅行足迹'),
                  const Spacer(),
                  _navItem(2, Icons.photo_library_outlined, '我的相册'),
                  _navItem(3, Icons.person_outline, '我的'),
                ],
              ),
            ),
          ),
          // 中间 FAB
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => _createNewTrip(context),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.green.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.flight_takeoff, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(int tab, IconData icon, String label) {
    final active = _tab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: active ? AppColors.mintCircle : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 22, color: active ? AppColors.greenDark : AppColors.textSub),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                      color: active ? AppColors.greenDark : AppColors.textSub,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 首页 Tab =================
  Widget _buildHomeTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _buildHeader(),
        _buildSearchBar(),
        _sectionTitle('旅行灵感', icon: Icons.auto_awesome, iconColor: AppColors.green),
        _buildInspirationRow(),
        _sectionTitle('快捷功能'),
        _buildQuickActions(),
        _sectionTitle('我的行程', key: _tripSectionKey),
        Consumer<TripProvider>(
          builder: (context, provider, _) {
            if (provider.trips.isEmpty) return _buildEmptyState();
            return Column(
              children: provider.trips.map((t) => _buildTripCard(context, t)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final home = context.watch<TripProvider>().homeLocation;
    final city = (home?.city?.isNotEmpty ?? false) ? home!.city! : '上海';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.headerTop, AppColors.headerBottom],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          // 装饰圆
          Positioned(
            right: -30,
            top: -40,
            child: _decoCircle(120, 0.10),
          ),
          Positioned(
            right: 40,
            top: 30,
            child: _decoCircle(60, 0.08),
          ),
          Positioned(
            right: 96,
            top: -14,
            child: _decoCircle(28, 0.10),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hi，去旅行吧',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 16, color: AppColors.textSub),
                  const SizedBox(width: 4),
                  Text(
                    _clock,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSub, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 18),
                  GestureDetector(
                    onTap: () => _editHomeLocation(context),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSub),
                        const SizedBox(width: 3),
                        Text(
                          city,
                          style: const TextStyle(fontSize: 14, color: AppColors.textSub, fontWeight: FontWeight.w500),
                        ),
                        const Icon(Icons.keyboard_arrow_down, size: 16, color: AppColors.textSub),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '开始一场说走就走的旅行 ✈',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSub.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _decoCircle(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.green.withOpacity(opacity + 0.06), width: 10),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiPlanPage()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.grey[400], size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '想去哪里？',
                      style: TextStyle(fontSize: 15, color: Colors.grey[400]),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _createNewTrip(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                    child: const Icon(Icons.add, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text, {IconData? icon, Color? iconColor, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 6),
            Icon(icon, size: 16, color: iconColor ?? AppColors.green),
          ],
        ],
      ),
    );
  }

  // ---- 旅行灵感 ----
  static const _inspo = [
    {'city': '上海', 'title': '上海citywalk', 'sub': '3天 · 22个地点', 'emoji': '🏙️', 'c1': 0xFF9CCBA8, 'c2': 0xFF5E9E6E},
    {'city': '成都', 'title': '成都慢生活', 'sub': '4天 · 18个地点', 'emoji': '🐼', 'c1': 0xFFFFCFA0, 'c2': 0xFFDE9A5E},
    {'city': '杭州', 'title': '杭州湖山行', 'sub': '3天 · 15个地点', 'emoji': '🍃', 'c1': 0xFFA8CDE8, 'c2': 0xFF6E96BE},
  ];

  Widget _buildInspirationRow() {
    return SizedBox(
      height: 158,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          ..._inspo.map((d) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _inspoCard(d),
              )),
          _aiCard(),
        ],
      ),
    );
  }

  Widget _inspoCard(Map<String, dynamic> d) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AiPlanPage(initialCity: d['city'] as String)),
      ),
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(d['c1'] as int), Color(d['c2'] as int)],
          ),
          boxShadow: AppColors.cardShadow,
        ),
        child: Stack(
          children: [
            Positioned(
              right: 8,
              top: 6,
              child: Text(
                d['emoji'] as String,
                style: const TextStyle(fontSize: 34),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  d['sub'] as String,
                  style: const TextStyle(fontSize: 10, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                d['title'] as String,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0x44000000), blurRadius: 4)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AiPlanPage()),
      ),
      child: Container(
        width: 172,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6ECB63), Color(0xFF4FA84A)],
          ),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(child: Text('🤖', style: TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI帮你规划行程',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '告诉AI你的想法，自动生成完整行程',
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.92), height: 1.4),
            ),
            const Spacer(),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Text('开始规划', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.greenDark)),
                      Icon(Icons.arrow_forward, size: 12, color: AppColors.greenDark),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 快捷功能 ----
  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _quickAction(Icons.directions_walk_rounded, '旅行足迹', AppColors.mintCircle, const Color(0xFF4CA84A), () => setState(() => _tab = 1)),
          _quickAction(Icons.assignment_outlined, '我的行程', AppColors.peach, const Color(0xFFE8A05C), _scrollToTrips),
          _quickAction(Icons.photo_library_outlined, '我的相册', AppColors.lavender, const Color(0xFF9B7EDE), () => setState(() => _tab = 2)),
          _quickAction(Icons.add_location_alt_outlined, '添加地点', AppColors.sky, const Color(0xFF5B9BD5), _quickAddLocation),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, Color bg, Color fg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  void _scrollToTrips() {
    final ctx = _tripSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  Future<void> _quickAddLocation() async {
    final provider = context.read<TripProvider>();
    final result = await Navigator.push<Location>(
      context,
      MaterialPageRoute(builder: (_) => const LocationSearchPage()),
    );
    if (result == null || !mounted) return;

    final trip = provider.currentTrip ?? (provider.trips.isNotEmpty ? provider.trips.first : null);
    if (trip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有行程，点右下角 ✈ 先创建一个吧')),
      );
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List<TripDay>.from(trip.days);
    var dayIndex = days.indexWhere((d) => DateTime(d.date.year, d.date.month, d.date.day) == today);
    if (dayIndex < 0) {
      days.add(TripDay(date: today, dayNumber: days.length + 1));
      dayIndex = days.length - 1;
    }
    final day = days[dayIndex];
    final locations = List<Location>.from(day.locations)..add(result);
    days[dayIndex] = TripDay(id: day.id, date: day.date, dayNumber: day.dayNumber, locations: locations);
    trip.days = days;
    await provider.updateTrip(trip);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已把「${result.name}」加入行程第${days[dayIndex].dayNumber}天')),
    );
    _scrollToTrips();
  }

  // ---- 我的行程 ----
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.mintBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.flight_takeoff, size: 40, color: Color(0xFFB7CDB9)),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无行程',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text('点击 + 开始规划你的旅行', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _createNewTrip(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                child: const Text('创建我的第一个行程', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, Trip trip) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        boxShadow: AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          onTap: () {
            context.read<TripProvider>().setCurrentTrip(trip);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TripPreviewPage(trip: trip)),
            );
          },
          onLongPress: () => _showTripMenu(context, trip),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trip.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.mintCircle,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${trip.totalDays}天',
                        style: const TextStyle(fontSize: 12, color: AppColors.greenDark, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textSub),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateRange(trip.startDate, trip.endDate),
                      style: const TextStyle(fontSize: 13, color: AppColors.textSub),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSub),
                    const SizedBox(width: 4),
                    Text(
                      '${trip.allLocations.length}个地点',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSub),
                    ),
                    if (trip.members.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.people_outline, size: 14, color: AppColors.textSub),
                      const SizedBox(width: 4),
                      Text(
                        '${trip.members.length}人同行',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSub),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTripMenu(BuildContext context, Trip trip) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppColors.greenDark),
              title: const Text('编辑行程'),
              onTap: () {
                Navigator.pop(ctx);
                context.read<TripProvider>().setCurrentTrip(trip);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => TripCreatePage(trip: trip)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除行程', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteTrip(context, trip);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    return '${start.month}/${start.day} - ${end.month}/${end.day}';
  }

  void _createNewTrip(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TripCreatePage()),
    );
  }

  void _editHomeLocation(BuildContext context) async {
    final result = await Navigator.push<Location>(
      context,
      MaterialPageRoute(builder: (_) => const LocationSearchPage()),
    );

    if (result != null && context.mounted) {
      final homeLocation = HomeLocation(
        id: 'home',
        name: result.name,
        address: result.address,
        latitude: result.latitude ?? 0,
        longitude: result.longitude ?? 0,
        city: result.city,
        district: result.district,
      );
      await context.read<TripProvider>().setHomeLocation(homeLocation);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已设置家的位置: ${result.name}')),
        );
      }
    }
  }

  void _confirmDeleteTrip(BuildContext context, Trip trip) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除行程'),
        content: Text('确定要删除「${trip.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<TripProvider>().deleteTrip(trip.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已删除「${trip.name}」')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ================= 相册 Tab（占位，P1-4 照片归档） =================
  Widget _buildGalleryTab() {
    return Container(
      color: AppColors.mintBg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: AppColors.lavender, shape: BoxShape.circle),
              child: const Icon(Icons.photo_library_outlined, size: 40, color: Color(0xFF9B7EDE)),
            ),
            const SizedBox(height: 18),
            const Text('相册功能开发中', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                '将支持行程照片自动归档、旅行地图和 AI 游记生成',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= 我的 Tab =================
  Widget _buildMineTab() {
    return Container(
      color: AppColors.mintBg,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 账号卡片
          FutureBuilder<String?>(
            future: ApiClient.username,
            builder: (context, snap) {
              final name = snap.data;
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudSettingsPage())),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6ECB63), Color(0xFF4FA84A)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(child: Text('🧳', style: TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name ?? '未登录',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name != null ? '行程已开启云同步' : '点击登录，行程云同步不丢失',
                              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              children: [
                _mineTile(Icons.cloud_sync_rounded, '云同步设置', AppColors.mintCircle, const Color(0xFF4CA84A),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CloudSettingsPage()))),
                const Divider(height: 1, indent: 56),
                _mineTile(Icons.home_outlined, '家的位置', AppColors.peach, const Color(0xFFE8A05C),
                    () => _editHomeLocation(context)),
                const Divider(height: 1, indent: 56),
                _mineTile(Icons.map_outlined, '旅行足迹', AppColors.sky, const Color(0xFF5B9BD5),
                    () => setState(() => _tab = 1)),
                const Divider(height: 1, indent: 56),
                _mineTile(Icons.info_outline, '关于', AppColors.lavender, const Color(0xFF9B7EDE), _showAbout),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('旅行助手 · TripLobsterAI v1.1', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
          ),
        ],
      ),
    );
  }

  Widget _mineTile(IconData icon, String title, Color bg, Color fg, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: fg, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15, color: AppColors.textPrimary)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textSub),
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: '旅行助手',
      applicationVersion: 'v1.1 (P0 阶段1)',
      applicationIcon: const Icon(Icons.flight_takeoff, color: AppColors.green, size: 36),
      children: const [
        Text('让自由行像跟团一样省心：AI 行程生成 · 云同步 · 时间线规划'),
      ],
    );
  }
}
