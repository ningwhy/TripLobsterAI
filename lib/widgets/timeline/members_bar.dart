import 'package:flutter/material.dart';

import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';

/// 成员条（常驻）：`共 N 人 · M 间房`（N=adults+children，M=rooms，**不显示车**）
///
/// 【三铁律 1】`members.isEmpty` 时**整块隐藏**，不显示假人。
/// 邀请为 ghost 占位：点击 → 回调（页面弹 SnackBar「邀请功能开发中，可先分享行程海报」+ 跳海报）。
class MembersBar extends StatelessWidget {
  final Trip trip;
  final VoidCallback onInvite;

  const MembersBar({super.key, required this.trip, required this.onInvite});

  @override
  Widget build(BuildContext context) {
    if (trip.members.isEmpty) return const SizedBox.shrink();

    final heads = trip.members.take(5).toList();
    return Container(
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
  }
}
