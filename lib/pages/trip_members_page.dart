import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/trip_models.dart';
import '../providers/trip_provider.dart';

/// 成员管理页。
///
/// 【数据来源】只渲染 [TripProvider] 中按 [tripId] 命中的真实 `Trip.members`，
/// 找不到行程时显示明确空态，⛔ 不补示例成员、不编造姓名/头像/照片数。
///
/// 【诚实性红线】当前项目没有邀请服务：
/// - 邀请链接是按真实 `trip.id` 拼出的**示意链接**，UI 与反馈均标注
///   [inviteDisclaimer]，不冒充真实邀请码；
/// - 「复制」必须真的写入剪贴板后才反馈，失败则如实说明；
/// - 分享只如实描述「系统分享面板是否被调起」，⛔ 不宣称「已分享成功」。
///
/// 【管理员保护】项目没有登录态 / 当前用户标识，无法凭数据判断「自己是谁」，
/// 因此把「admin 移除自己」落地为唯一可由真实数据判定的口径：
/// **行程唯一管理员不可移除、不可降级**（否则行程会变成无管理员）。
/// 不编造用户身份。
class TripMembersPage extends StatelessWidget {
  final String tripId;

  const TripMembersPage({super.key, required this.tripId});

  /// 项目未接入邀请服务时的统一说明文案（UI 与反馈都必须出现）。
  static const String inviteDisclaimer = '示意链接，实际项目需接入邀请服务';

  /// 示意邀请链接：用行程真实 id 拼接，避免展示一个凭空捏造的邀请码。
  static String inviteLinkFor(Trip trip) => 'https://trip.app/invite/${trip.id}';

  @override
  Widget build(BuildContext context) {
    final List<Trip> trips = context.watch<TripProvider>().trips;
    Trip? found;
    for (final Trip candidate in trips) {
      if (candidate.id == tripId) {
        found = candidate;
        break;
      }
    }
    final Trip? trip = found;
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('成员管理')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '未找到该行程，无法查看成员',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
        ),
      );
    }
    return _buildContent(context, trip);
  }

  Widget _buildContent(BuildContext context, Trip trip) {
    final List<Member> members = trip.members;
    // 照片数由真实成员数据累加，⛔ 不再显示写死的 55 张。
    final int photoCount = members.fold<int>(0, (int sum, Member m) => sum + m.photoIds.length);
    final String link = inviteLinkFor(trip);

    return Scaffold(
      appBar: AppBar(title: const Text('成员管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Trip Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A90D9), Color(0xFF6BB3F0)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${trip.startDate.month}/${trip.startDate.day} - ${trip.endDate.month}/${trip.endDate.day} · ${trip.totalDays}天',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('${members.length}', '成员'),
                _buildStatItem('$photoCount', '照片'),
                _buildStatItem('${trip.allLocations.length}', '地点'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Members List
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '成员列表',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextButton.icon(
                        onPressed: () => _inviteMember(context, trip),
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('邀请'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ...members.map((Member member) => _buildMemberItem(context, trip, member)),
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '当前行程没有成员',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('新增成员'),
                  onTap: () => _showAddMemberDialog(context, trip),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Invite Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.link, color: Color(0xFF4A90D9), size: 20),
                    SizedBox(width: 8),
                    Text(
                      '邀请链接',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          link,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _copyInviteLink(context, link),
                        child: const Text('复制'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  inviteDisclaimer,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildShareButton(
                        context,
                        trip,
                        '微信',
                        Icons.chat,
                        const Color(0xFF07C160),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildShareButton(
                        context,
                        trip,
                        '朋友圈',
                        Icons.photo,
                        const Color(0xFFFF9500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildShareButton(
                        context,
                        trip,
                        '二维码',
                        Icons.qr_code,
                        const Color(0xFF4A90D9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 诚实标注：三个沿用设计稿的渠道名都只调起系统分享，
                // 并没有真的生成二维码 / 定向发到微信，⛔ 也不宣称分享成功。
                const Text(
                  '入口说明：以上按钮均调起系统分享，未生成二维码；是否发送由所选应用决定',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Permissions
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
                  '权限说明',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _buildPermissionItem(
                  '管理员',
                  '增删改地点、修改行程、邀请成员',
                  true,
                ),
                _buildPermissionItem(
                  '成员',
                  '查看行程、上传和共享照片',
                  false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF4A90D9),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildMemberItem(BuildContext context, Trip trip, Member member) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.isAdmin
            ? const Color(0xFF667eea)
            : const Color(0xFF4A90D9),
        child: Text(
          member.name.isNotEmpty ? member.name[0] : '?',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Row(
        children: [
          Text(member.name),
          if (member.isAdmin) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '管理员',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF4A90D9),
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${member.photoIds.length}张照片',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: '成员操作',
        onPressed: () => _showMemberOptions(context, trip, member),
      ),
    );
  }

  Widget _buildShareButton(
    BuildContext context,
    Trip trip,
    String label,
    IconData icon,
    Color color,
  ) {
    return ElevatedButton(
      onPressed: () => _shareInvite(context, trip),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(String role, String desc, bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isAdmin
                  ? const Color(0xFF4A90D9).withValues(alpha: 0.1)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isAdmin ? Icons.edit : Icons.visibility,
              size: 16,
              color: isAdmin ? const Color(0xFF4A90D9) : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  desc,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle,
            color: Color(0xFF2ECC71),
            size: 20,
          ),
        ],
      ),
    );
  }

  // ---------------- 业务动作 ----------------

  /// 反馈辅助：只在同步上下文里调用；跨 async gap 的调用点必须先
  /// `if (!context.mounted) return;`（见下方各业务方法）。
  void _showMessage(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  int _adminCount(Trip trip) =>
      trip.members.where((Member m) => m.isAdmin).length;

  /// 把 [members] 写回真实行程并落库。
  ///
  /// 失败时回滚内存里的 `trip.members`，保证「界面显示的」与「Provider 里存的」一致。
  Future<void> _writeMembers(
    BuildContext context,
    Trip trip,
    List<Member> members,
    String successText,
  ) async {
    final TripProvider provider = context.read<TripProvider>();
    final List<Member> previous = trip.members;
    trip.members = members;
    try {
      await provider.updateTrip(trip);
      if (!context.mounted) return;
      _showMessage(context, successText);
    } catch (_) {
      trip.members = previous;
      if (!context.mounted) return;
      _showMessage(context, '保存失败，成员信息未更新');
    }
  }

  /// 邀请（复制示意链接）：必须真的写入剪贴板后才给「已复制」反馈。
  Future<void> _inviteMember(BuildContext context, Trip trip) async {
    await _copyInviteLink(context, inviteLinkFor(trip));
  }

  Future<void> _copyInviteLink(BuildContext context, String link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (!context.mounted) return;
      _showMessage(context, '邀请链接已复制（$inviteDisclaimer）');
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '复制失败，未写入剪贴板');
    }
  }

  /// 分享：如实反馈系统分享面板的状态，⛔ 不宣称「分享成功」。
  Future<void> _shareInvite(BuildContext context, Trip trip) async {
    final String link = inviteLinkFor(trip);
    final String text =
        '${trip.name} · 邀请你加入行程：$link（$inviteDisclaimer）';
    try {
      final ShareResult result = await Share.share(text, subject: trip.name);
      if (!context.mounted) return;
      final String feedback = switch (result.status) {
        ShareResultStatus.success => '已调起系统分享，是否发送由所选应用决定',
        ShareResultStatus.dismissed => '已取消系统分享',
        ShareResultStatus.unavailable => '当前环境无法调起系统分享',
      };
      _showMessage(context, feedback);
    } catch (_) {
      if (!context.mounted) return;
      _showMessage(context, '系统分享不可用，未分享');
    }
  }

  /// 新增成员：昵称由用户输入，⛔ 不自动生成假姓名 / 头像 / 照片。
  Future<void> _showAddMemberDialog(BuildContext context, Trip trip) async {
    String input = '';
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('新增成员'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入成员昵称'),
          onChanged: (String value) => input = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, input),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final String trimmed = name.trim();
    if (!context.mounted) return;
    if (trimmed.isEmpty) {
      _showMessage(context, '昵称不能为空，未添加成员');
      return;
    }
    final List<Member> updated = <Member>[
      ...trip.members,
      Member(name: trimmed, role: MemberRole.member),
    ];
    await _writeMembers(context, trip, updated, '已添加成员 $trimmed');
  }

  /// 成员操作面板：切换角色 / 移除成员（均写回 Provider）。
  void _showMemberOptions(BuildContext context, Trip trip, Member member) {
    final bool isLastAdmin = member.isAdmin && _adminCount(trip) <= 1;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(member.isAdmin ? Icons.person : Icons.edit),
              title: Text(member.isAdmin ? '设为普通成员' : '设为管理员'),
              subtitle: isLastAdmin
                  ? const Text('唯一管理员不可降级，行程需保留至少一名管理员')
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await _toggleRole(context, trip, member);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('移除成员', style: TextStyle(color: Colors.red)),
              subtitle: isLastAdmin
                  ? const Text('唯一管理员不可移除，行程需保留至少一名管理员')
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await _confirmRemove(context, trip, member);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleRole(BuildContext context, Trip trip, Member member) async {
    if (member.isAdmin && _adminCount(trip) <= 1) {
      _showMessage(context, '行程需保留至少一名管理员，无法将唯一管理员降级');
      return;
    }
    final MemberRole next =
        member.isAdmin ? MemberRole.member : MemberRole.admin;
    final List<Member> updated = trip.members.map((Member m) {
      if (m.id != member.id) return m;
      return Member(
        id: m.id,
        name: m.name,
        role: next,
        avatarUrl: m.avatarUrl,
        photoIds: List<String>.from(m.photoIds),
        lastActiveAt: m.lastActiveAt,
      );
    }).toList();
    await _writeMembers(
      context,
      trip,
      updated,
      next == MemberRole.admin ? '已设为管理员' : '已设为普通成员',
    );
  }

  /// 移除成员：二次确认后才写回；唯一管理员直接给出明确提示并阻止。
  Future<void> _confirmRemove(
    BuildContext context,
    Trip trip,
    Member member,
  ) async {
    if (member.isAdmin && _adminCount(trip) <= 1) {
      _showMessage(context, '行程需保留至少一名管理员，无法移除唯一管理员');
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定移除「${member.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final List<Member> updated =
        trip.members.where((Member m) => m.id != member.id).toList();
    await _writeMembers(context, trip, updated, '已移除成员 ${member.name}');
  }
}
