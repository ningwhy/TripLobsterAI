import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/theme/app_colors.dart';
import 'package:trip_planner/theme/octopus_theme.dart';

/// 全局视觉令牌回归。
///
/// 期望值一律写成字面量 [Color]，由 `trip/ui-octopus.css` 与
/// 「03-章鱼旅行 组合图.png」的设计 token 手算抄录；
/// **禁止**用 `OctopusColors.xxx` / `AppColors.xxx` 自身充当期望值，
/// 否则实现改错时断言会跟着一起漂移，失去回归意义。
///
/// 唯一例外是「Material 3 派生色」：fromSeed 的 primary 是种子色经 HCT
/// 调色板派生后的值，无法与设计 token 字面量直接相等，故以写死的设计主色
/// 独立重建一次 fromSeed 作为期望（验证主题确实接到章鱼紫，而非旧的清新绿）。
void main() {
  group('OctopusColors 品牌色 token（期望值逐条手算自设计系统）', () {
    test('primary = 章鱼紫 #7C6DF7', () {
      expect(OctopusColors.primary, const Color(0xFF7C6DF7));
    });

    test('primaryDeep = #6A58E8', () {
      expect(OctopusColors.primaryDeep, const Color(0xFF6A58E8));
    });

    test('primarySoft = #EEF0FF', () {
      expect(OctopusColors.primarySoft, const Color(0xFFEEF0FF));
    });

    test('primaryInk = #5B58D6', () {
      expect(OctopusColors.primaryInk, const Color(0xFF5B58D6));
    });

    test('titleBlue = #3B6AF6', () {
      expect(OctopusColors.titleBlue, const Color(0xFF3B6AF6));
    });
  });

  group('OctopusColors 语义卡片色 token（期望值逐条手算自设计系统）', () {
    test('cardGreen = #3FCB8E', () {
      expect(OctopusColors.cardGreen, const Color(0xFF3FCB8E));
    });

    test('cardRed = #FF6B7C', () {
      expect(OctopusColors.cardRed, const Color(0xFFFF6B7C));
    });

    test('cardOrange = #FFA45C', () {
      expect(OctopusColors.cardOrange, const Color(0xFFFFA45C));
    });

    test('cardPlain = #F7F8FC', () {
      expect(OctopusColors.cardPlain, const Color(0xFFF7F8FC));
    });

    test('cardLine = #EDF0F7', () {
      expect(OctopusColors.cardLine, const Color(0xFFEDF0F7));
    });
  });

  group('OctopusColors 文字色 token（与 preview_theme.dart 一致）', () {
    test('ink = #22303E', () {
      expect(OctopusColors.ink, const Color(0xFF22303E));
    });

    test('sub = #8A97A5', () {
      expect(OctopusColors.sub, const Color(0xFF8A97A5));
    });

    test('dim = #B9C4CF', () {
      expect(OctopusColors.dim, const Color(0xFFB9C4CF));
    });
  });

  group('OctopusTheme.build()', () {
    test('启用 Material 3', () {
      expect(OctopusTheme.build().useMaterial3, isTrue);
    });

    test('colorScheme 由设计主色 #7C6DF7 派生的亮色方案', () {
      final expected = ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C6DF7),
        brightness: Brightness.light,
      );
      final scheme = OctopusTheme.build().colorScheme;

      expect(scheme.primary, expected.primary);
      expect(scheme.brightness, Brightness.light);
      // 旧「清新绿」主色不得残留。
      expect(scheme.primary, isNot(const Color(0xFF5FBE5B)));
    });

    test('scaffoldBackgroundColor = 素卡片底 #F7F8FC', () {
      expect(
        OctopusTheme.build().scaffoldBackgroundColor,
        const Color(0xFFF7F8FC),
      );
    });

    test('appBarTheme：白底 / 深色墨字 / 零阴影', () {
      final appBar = OctopusTheme.build().appBarTheme;

      expect(appBar.backgroundColor, const Color(0xFFFFFFFF));
      expect(appBar.foregroundColor, const Color(0xFF22303E));
      expect(appBar.elevation, 0);
    });
  });

  group('AppColors 兼容别名（零页面改动前提下切到新主色）', () {
    test('AppColors.green == OctopusColors.primary', () {
      expect(AppColors.green, OctopusColors.primary);
    });

    test('AppColors.green 直接等于设计主色字面量 #7C6DF7', () {
      expect(AppColors.green, const Color(0xFF7C6DF7));
    });

    test('AppColors.primary == AppColors.green', () {
      expect(AppColors.primary, AppColors.green);
    });

    test('存量别名逐条指向新设计 token', () {
      expect(AppColors.greenDark, OctopusColors.primaryDeep);
      expect(AppColors.textPrimary, OctopusColors.ink);
      expect(AppColors.textSub, OctopusColors.sub);
      expect(AppColors.mintBg, OctopusColors.cardPlain);
      expect(AppColors.headerTop, OctopusColors.primarySoft);
      expect(AppColors.headerBottom, OctopusColors.primarySoft);
      expect(AppColors.mintCircle, OctopusColors.primarySoft);
    });

    test('新增语义常量与 OctopusColors 同源', () {
      expect(AppColors.primary, OctopusColors.primary);
      expect(AppColors.primaryDark, OctopusColors.primaryDeep);
      expect(AppColors.primarySoft, OctopusColors.primarySoft);
      expect(AppColors.primaryInk, OctopusColors.primaryInk);
      expect(AppColors.titleBlue, OctopusColors.titleBlue);
      expect(AppColors.cardGreen, OctopusColors.cardGreen);
      expect(AppColors.cardRed, OctopusColors.cardRed);
      expect(AppColors.cardOrange, OctopusColors.cardOrange);
      expect(AppColors.cardPlain, OctopusColors.cardPlain);
      expect(AppColors.cardLine, OctopusColors.cardLine);
    });

    test('装饰色与卡片结构常量保留原值', () {
      expect(AppColors.peach, const Color(0xFFFFE9D6));
      expect(AppColors.lavender, const Color(0xFFE9E1FA));
      expect(AppColors.sky, const Color(0xFFDBEDFB));
      expect(AppColors.card, Colors.white);
      expect(AppColors.cardRadius, 16.0);
    });
  });
}
