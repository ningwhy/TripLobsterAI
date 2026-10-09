import 'package:flutter/material.dart';

import '../../theme/preview_theme.dart';

/// navy 顶栏：左返回 / 中「行程预览」/ 右依次 编辑·海报·保存（PRD Q5 推荐排布）
class PreviewTopBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onPoster;
  final VoidCallback onSave;

  /// 标题下方的副行（如「出发 2026-10-01 · 共 3 天」）。
  ///
  /// 【TL-10 回归】旧版预览页顶部有「出发日期」元信息卡，重写时整条掉了。
  /// 分组头虽有每天的日期，但**行程级**的出发日与总天数仍是需要一眼确认的信息
  /// —— 用户核对"这趟行程拿对没有"看的是出发日，不是其中某一天。故补回。
  /// 传 null / 空串则不显示（顶栏高度相应回落到 48）。
  final String? subtitle;

  const PreviewTopBar({
    super.key,
    required this.onBack,
    required this.onEdit,
    required this.onPoster,
    required this.onSave,
    this.subtitle,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(subtitle == null || subtitle!.isEmpty ? 48 : 58);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PreviewColors.navy,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      height: preferredSize.height + MediaQuery.of(context).padding.top,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
            tooltip: '返回',
            onPressed: onBack,
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('行程预览', style: PreviewText.title),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: PreviewText.statusLine.copyWith(
                          color: Colors.white70,
                          fontSize: 10.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
            tooltip: '编辑行程',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share, size: 18, color: Colors.white),
            tooltip: '行程海报',
            onPressed: onPoster,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_border_rounded, size: 18, color: Colors.white),
            tooltip: '保存行程',
            onPressed: onSave,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
