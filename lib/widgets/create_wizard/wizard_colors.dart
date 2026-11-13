import 'package:flutter/material.dart';

/// 创建行程四步引导的配色。
///
/// ⛔ 这里刻意**不 import** `lib/theme/octopus_theme.dart`：该文件由另一并行批次
///    正在新建，此刻可能尚不存在。所有值都是字面常量，来源 `trip/ui-octopus.css`
///    `:root` 变量表（:10-30），避免跨批次文件冲突。
const Color kWizardPurple = Color(0xFF7C6DF7); // --purple: #7C6DF7
const Color kWizardPurpleDeep = Color(0xFF6A58E8); // --purple-deep: #6A58E8
const Color kWizardInk = Color(0xFF2E3552); // --ink: #2E3552
const Color kWizardInk2 = Color(0xFF8A93AB); // --ink-2: #8A93AB
const Color kWizardDotIdle = Color(0xFFDEE2EF); // .step-dots i: #DEE2EF（:149）
const Color kWizardCardLine = Color(0xFFEDF0F7); // --card-line
