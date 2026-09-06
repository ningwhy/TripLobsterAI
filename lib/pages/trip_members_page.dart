import 'package:flutter/material.dart';
import '../models/trip_models.dart';

class TripMembersPage extends StatelessWidget {
  final Trip trip;

  const TripMembersPage({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    // 示例数据
    final members = trip.members.isEmpty
        ? [
            Member(
              name: '张明',
              role: MemberRole.admin,
              photoIds: List.generate(25, (i) => 'photo_$i'),
            ),
            Member(
              name: '李雪',
              role: MemberRole.member,
              photoIds: List.generate(18, (i) => 'photo_$i'),
            ),
            Member(
              name: '王强',
              role: MemberRole.member,
              photoIds: List.generate(12, (i) => 'photo_$i'),
            ),
          ]
        : trip.members;

    return Scaffold(
      appBar: AppBar(
        title: const Text('成员管理'),
      ),
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
                _buildStatItem('55', '照片'),
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
                        onPressed: _inviteMember,
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('邀请'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ...members.map((member) => _buildMemberItem(context, member)),
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
                      const Expanded(
                        child: Text(
                          'https://trip.app/invite/abc123',
                          style: TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('链接已复制')),
                          );
                        },
                        child: const Text('复制'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildShareButton(
                        '微信',
                        Icons.chat,
                        const Color(0xFF07C160),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildShareButton(
                        '朋友圈',
                        Icons.photo,
                        const Color(0xFFFF9500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildShareButton(
                        '二维码',
                        Icons.qr_code,
                        const Color(0xFF4A90D9),
                      ),
                    ),
                  ],
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

  Widget _buildMemberItem(BuildContext context, Member member) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.isAdmin
            ? const Color(0xFF667eea)
            : const Color(0xFF4A90D9),
        child: Text(
          member.name[0],
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
                color: const Color(0xFF4A90D9).withOpacity(0.1),
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
      trailing: member.isAdmin
          ? null
          : IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showMemberOptions(context, member),
            ),
    );
  }

  Widget _buildShareButton(String label, IconData icon, Color color) {
    return ElevatedButton(
      onPressed: () {},
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
                  ? const Color(0xFF4A90D9).withOpacity(0.1)
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

  void _inviteMember() {
    // TODO: 实现邀请功能
  }

  void _showMemberOptions(BuildContext context, Member member) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('设为管理员'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('移除成员', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
