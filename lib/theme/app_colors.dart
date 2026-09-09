import 'package:flutter/material.dart';

/// 全局设计令牌（参考"清新绿"首页视觉）
class AppColors {
  AppColors._();

  /// 主绿（按钮/FAB/高亮）
  static const green = Color(0xFF5FBE5B);
  static const greenDark = Color(0xFF4CA84A);

  /// 深绿（标题文字）
  static const textPrimary = Color(0xFF2E4A38);

  /// 次级文字（灰绿）
  static const textSub = Color(0xFF7C8F80);

  /// 页面背景（薄荷白）
  static const mintBg = Color(0xFFF1F8EF);

  /// 头部渐变
  static const headerTop = Color(0xFFE1F2DC);
  static const headerBottom = Color(0xFFF4FAF1);

  /// 快捷功能粉彩圆底
  static const mintCircle = Color(0xFFE2F3DA);
  static const peach = Color(0xFFFFE9D6);
  static const lavender = Color(0xFFE9E1FA);
  static const sky = Color(0xFFDBEDFB);

  /// 卡片
  static const card = Colors.white;
  static const cardRadius = 16.0;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF2E4A38).withOpacity(0.05),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];
}
