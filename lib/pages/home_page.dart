import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trip_provider.dart';
import '../models/trip_models.dart';
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
  @override
  void initState() {
    super.initState();
    // 已登录则启动时静默云同步
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TripProvider>().autoSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: _buildHeader(context),
            ),

            // Home Location Card
            SliverToBoxAdapter(
              child: _buildHomeLocationCard(context),
            ),

            // Quick Actions
            SliverToBoxAdapter(
              child: _buildQuickActions(context),
            ),

            // Trip List Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: const Text(
                  '我的行程',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Trip List
            Consumer<TripProvider>(
              builder: (context, provider, _) {
                if (provider.trips.isEmpty) {
                  return SliverToBoxAdapter(
                    child: _buildEmptyState(context),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final trip = provider.trips[index];
                      return _buildTripCard(context, trip);
                    },
                    childCount: provider.trips.length,
                  ),
                );
              },
            ),

            // Footprint Section
            SliverToBoxAdapter(
              child: _buildFootprintSection(context),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () => _createNewTrip(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF89CFF0),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
            child: const Text(
              '创建新行程',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF89CFF0), Color(0xFF6BB3E0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  '我的出行',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Consumer<TripProvider>(
                builder: (context, provider, _) => InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CloudSettingsPage()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(
                      provider.isSyncing
                          ? Icons.sync
                          : (provider.lastSyncAt > 0 ? Icons.cloud_done : Icons.cloud_off),
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Consumer<TripProvider>(
            builder: (context, provider, _) {
              if (provider.trips.isEmpty) {
                return const SizedBox.shrink();
              }
              // 显示最近一次行程的日期
              final latestTrip = provider.trips.first;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${latestTrip.startDate.month}月${latestTrip.startDate.day}日 - ${latestTrip.endDate.month}月${latestTrip.endDate.day}日',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHomeLocationCard(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, provider, _) {
        final home = provider.homeLocation;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _editHomeLocation(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.home, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '家',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            home?.address ?? '点击设置家的位置',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildActionCard(
              context,
              icon: Icons.map_outlined,
              title: '足迹记录',
              subtitle: '${context.watch<TripProvider>().footprints.length} 个城市',
              color: const Color(0xFF4A90D9),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FootprintPage()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionCard(
              context,
              icon: Icons.auto_awesome,
              title: 'AI 帮我规划',
              subtitle: '一键生成省心行程',
              color: const Color(0xFF9B59B6),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiPlanPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.flight_takeoff,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          const Text(
            '还没有行程',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '创建你的第一个旅行计划吧',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, Trip trip) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            context.read<TripProvider>().setCurrentTrip(trip);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TripPreviewPage(trip: trip),
              ),
            );
          },
          onLongPress: () {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('编辑行程'),
                    onTap: () {
                      Navigator.pop(ctx);
                      // 跳转到编辑页面
                      context.read<TripProvider>().setCurrentTrip(trip);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TripCreatePage(trip: trip),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('删除行程', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDeleteTrip(context, trip);
                    },
                  ),
                ],
              ),
            );
          },
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90D9).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${trip.totalDays}天',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4A90D9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${trip.startDate.month}/${trip.startDate.day} - ${trip.endDate.month}/${trip.endDate.day}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${trip.allLocations.length}个地点',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    if (trip.members.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      const Icon(Icons.people, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${trip.members.length}人同行',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
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

  Widget _buildFootprintSection(BuildContext context) {
    return Consumer<TripProvider>(
      builder: (context, provider, _) {
        if (provider.footprints.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '足迹记录',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const FootprintPage()),
                    ),
                    icon: const Icon(Icons.map),
                    label: Text('查看 ${provider.footprints.length} 个城市的足迹'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final startStr = '${start.month}/${start.day}';
    final endStr = '${end.month}/${end.day}';
    return '$startStr - $endStr';
  }

  void _createNewTrip(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TripCreatePage()),
    );
  }

  void _editHomeLocation(BuildContext context) async {
    // 跳转到位置搜索页面设置家的位置
    final result = await Navigator.push<Location>(
      context,
      MaterialPageRoute(builder: (_) => const LocationSearchPage()),
    );

    if (result != null && context.mounted) {
      // 保存家的位置
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
}
