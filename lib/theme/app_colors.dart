import 'package:flutter/material.dart';
import 'octopus_theme.dart';

/// 全局设计令牌。
///
/// 已对齐「章鱼旅行」设计系统（见 `trip/ui-octopus.css`，主色章鱼紫 #7C6DF7）。
///
/// 【兼容别名策略】下方历史常量名（`green` / `mintBg` / `textPrimary` 等）一律
/// **保留原名与 getter 签名**，仅把值指向 `OctopusColors` 的新设计 token。
/// 全库 `lib/pages/**` 有 90+ 处引用这些名字，重命名会要求同步改页面，
/// 与并行批次产生写冲突；因此本文件是「旧名 → 新色」的唯一映射层。
/// 新代码请直接引用语义清晰的新增常量（或 `OctopusColors` 本身）。
class AppColors {
  AppColors._();

  // ---- 新增：紫色语义常量（值全部来自 OctopusColors）----

  /// 品牌主色「章鱼紫」。
  static const Color primary = OctopusColors.primary;

  /// 主色深阶。
  static const Color primaryDark = OctopusColors.primaryDeep;

  /// 主色浅底。
  static const Color primarySoft = OctopusColors.primarySoft;

  /// 主色墨字。
  static const Color primaryInk = OctopusColors.primaryInk;

  /// 屏标题蓝。
  static const Color titleBlue = OctopusColors.titleBlue;

  /// 语义卡片绿。
  static const Color cardGreen = OctopusColors.cardGreen;

  /// 语义卡片红。
  static const Color cardRed = OctopusColors.cardRed;

  /// 语义卡片橙。
  static const Color cardOrange = OctopusColors.cardOrange;

  /// 素卡片底 / 页面底。
  static const Color cardPlain = OctopusColors.cardPlain;

  /// 卡片描边。
  static const Color cardLine = OctopusColors.cardLine;

  // ---- 存量常量名（兼容别名；零页面改动）----

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向主色「章鱼紫」）。
  static const Color green = OctopusColors.primary;

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向主色深阶）。
  static const Color greenDark = OctopusColors.primaryDeep;

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向主文字色 ink）。
  static const Color textPrimary = OctopusColors.ink;

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向次级文字色 sub）。
  static const Color textSub = OctopusColors.sub;

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向素卡片底）。
  static const Color mintBg = OctopusColors.cardPlain;

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向主色浅底）。
  /// 原「薄荷绿渐变」两端收敛为同一设计 token，不臆造中间色。
  static const Color headerTop = OctopusColors.primarySoft;

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向主色浅底）。
  /// 原「薄荷绿渐变」两端收敛为同一设计 token，不臆造中间色。
  static const Color headerBottom = OctopusColors.primarySoft;

  /// 历史命名；值已按章鱼旅行设计系统更新（现指向主色浅底）。
  static const Color mintCircle = OctopusColors.primarySoft;

  // ---- 装饰色：保留原值，不随设计系统改动 ----

  /// 快捷功能粉彩圆底（装饰色，保留原值）。
  static const Color peach = Color(0xFFFFE9D6);
  static const Color lavender = Color(0xFFE9E1FA);
  static const Color sky = Color(0xFFDBEDFB);

  // ---- 卡片：结构常量保留 ----

  /// 卡片底色。
  static const Color card = Colors.white;

  /// 卡片圆角。
  static const double cardRadius = 16.0;

  /// 卡片阴影；阴影基色改用设计系统主文字色 ink 的低透明度版本。
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: OctopusColors.ink.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];
}
