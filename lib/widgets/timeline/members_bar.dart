import 'package:flutter/material.dart';

import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';

/// 成员条（常驻）：`共 N 人 · M 间房`（N=adults+children，M=rooms，**不显示车**）
///
/// 【三铁律 1】`members.isEmpty` 时**不显示假人**（绝不为 0 成员编造头像/姓名）。
/// 但为了让 0 成员行程也能进入成员管理页，当调用方提供了 [onTap] 时，
/// 空态会渲染一条**诚实入口**「还没有成员，点击添加」——点击即跳到成员页去添加，
/// 不凭空生成任何成员。邀请的 "+" ghost 占位：点击 → [onInvite] 回调。
///
/// [onTap] 为可选的「整条点击」入口：
/// - 为 null 时**不插入任何手势层**：有成员时整条可点、空态整块隐藏，
///   widget 树 / 布局 / 文案与改动前完全一致（向后兼容）；
/// - 非 null 时：有成员则整条可点（"+" 头像仍是原有 [onInvite] 手势，子组件优先命中），
///   无成员则显示「还没有成员，点击添加」的诚实入口（点击同样跳到成员页）。
class MembersBar extends StatelessWidget {
  final Trip trip;
  final VoidCallback onInvite;
  final VoidCallback? onTap;

  const MembersBar({
    super.key,
    required this.trip,
    required this.onInvite,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (trip.members.isEmpty) return _buildEmptyState();

    final heads = trip.members.take(5).toList();
    final Widget bar = Container(
      color: PreviewColors.navy,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          ...heads.map((m) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: PreviewColors.teal.withValues(alpha: 0.85),
                  child: Text(
                    m.name.isNotEmpty ? m.name[0] : '👤',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              )),
          GestureDetector(
            onTap: onInvite,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              child: const Icon(Icons.add, size: 14, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '共 ${trip.adults + trip.children} 人 · ${trip.rooms} 间房',
            style: const TextStyle(fontSize: 11.5, color: Colors.white70),
          ),
        ],
      ),
    );

    final VoidCallback? tap = onTap;
    if (tap == null) return bar;
    return GestureDetector(
      onTap: tap,
      behavior: HitTestBehavior.opaque,
      child: bar,
    );
  }

  /// 空态：不显示假人。仅当调用方提供了 [onTap] 时，渲染一条诚实入口，
  /// 点击进入成员管理页去添加（沿用预览页 `_openMembers`）；无 [onTap] 则维持整块隐藏，向后兼容。
  Widget _buildEmptyState() {
    if (onTap == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: PreviewColors.navy,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: const Row(
          children: [
            Icon(Icons.person_add, size: 16, color: Colors.white70),
            SizedBox(width: 8),
            Text(
              '还没有成员，点击添加',
              style: TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
