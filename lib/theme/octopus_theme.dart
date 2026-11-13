import 'package:flutter/material.dart';

/// 章鱼旅行统一设计系统的全局视觉令牌。
///
/// 色值与 `trip/ui-octopus.css`（依据「03-章鱼旅行 组合图.png」定稿）逐条对应，
/// 是 Flutter 客户端全局主色的唯一来源。文字色沿用 `preview_theme.dart` 已有的
/// `ink` / `sub` / `dim`，保证行程预览页与全局令牌口径一致。
///
/// 零第三方依赖，仅依赖 `package:flutter/material.dart` 的 [Color]。
class OctopusColors {
  OctopusColors._();

  // ---- 品牌 ----

  /// 品牌主色「章鱼紫」（CSS `--purple` #7C6DF7）。
  static const Color primary = Color(0xFF7C6DF7);

  /// 主色深阶（CSS `--purple-deep` #6A58E8）。
  static const Color primaryDeep = Color(0xFF6A58E8);

  /// 主色浅底（CSS `--purple-soft` #EEF0FF）。
  static const Color primarySoft = Color(0xFFEEF0FF);

  /// 主色墨字（CSS `--purple-ink` #5B58D6）。
  static const Color primaryInk = Color(0xFF5B58D6);

  /// 屏标题蓝（CSS `--title-blue` #3B6AF6）。
  static const Color titleBlue = Color(0xFF3B6AF6);

  // ---- 语义卡片色（参考图：紫 / 绿 / 红 / 橙 / 白）----

  /// 语义卡片绿（CSS `--card-green` #3FCB8E）。
  static const Color cardGreen = Color(0xFF3FCB8E);

  /// 语义卡片红（CSS `--card-red` #FF6B7C）。
  static const Color cardRed = Color(0xFFFF6B7C);

  /// 语义卡片橙（CSS `--card-orange` #FFA45C）。
  static const Color cardOrange = Color(0xFFFFA45C);

  /// 素卡片底 / 页面底（CSS `--card-plain` #F7F8FC）。
  static const Color cardPlain = Color(0xFFF7F8FC);

  /// 卡片描边（CSS `--card-line` #EDF0F7）。
  static const Color cardLine = Color(0xFFEDF0F7);

  // ---- 中性文字色（与 preview_theme.dart 的 PreviewColors 一致）----

  /// 主文字色 #22303E（沿用 `PreviewColors.ink`）。
  static const Color ink = Color(0xFF22303E);

  /// 次级文字色 #8A97A5（沿用 `PreviewColors.sub`）。
  static const Color sub = Color(0xFF8A97A5);

  /// 弱文字 / 占位色 #B9C4CF（沿用 `PreviewColors.dim`）。
  static const Color dim = Color(0xFFB9C4CF);
}

/// 章鱼旅行全局 [ThemeData] 构造器。
class OctopusTheme {
  OctopusTheme._();

  /// 构建 Material 3 亮色主题。
  ///
  /// - 以 [OctopusColors.primary] 作为 [ColorScheme.fromSeed] 的种子色；
  /// - 页面底色取 [OctopusColors.cardPlain]；
  /// - 顶栏白底、深色墨字前景、零阴影，对齐 CSS `.app-bar`。
  ///
  /// 只负责视觉令牌，不含任何业务文案、数据或交互逻辑。
  static ThemeData build() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: OctopusColors.primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: OctopusColors.cardPlain,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: OctopusColors.ink,
        elevation: 0,
      ),
    );
  }
}
