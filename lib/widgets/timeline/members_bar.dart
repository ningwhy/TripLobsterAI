import 'package:flutter/material.dart';

import '../../models/trip_models.dart';
import '../../theme/preview_theme.dart';

/// 成员条（常驻）：`共 N 人 · M 间房`（N=adults+children，M=rooms，**不显示车**）
///
/// 【三铁律 1】`members.isEmpty` 时**整块隐藏**，不显示假人。
/// 邀请为 ghost 占位：点击 → 回调（页面弹 SnackBar「邀请功能开发中，可先分享行程海报」+ 跳海报）。
///
/// [onTap] 为可选的「整条点击」入口：
/// - 为 null 时**不插入任何手势层**，widget 树 / 布局 / 文案与改动前完全一致；
/// - 非 null 时点击整条触发（"+" 头像仍是原有 [onInvite] 手势，子组件优先命中）。
/// ⛔ 不新增可见控件、不改变 `members` 为空整块隐藏的语义、不改现有布局尺寸与文本。
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
    if (trip.members.isEmpty) return const SizedBox.shrink();

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
}
