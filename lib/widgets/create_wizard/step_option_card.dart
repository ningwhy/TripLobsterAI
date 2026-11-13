import 'package:flutter/material.dart';

import 'wizard_colors.dart';

/// 一个选项卡的数据。组件**不内置任何业务文案**，全部由调用方传入，
/// 保证「所有选项文案沿用现有页面已有文案」这条红线不被组件层破坏。
class StepOptionItem {
  const StepOptionItem({
    required this.title,
    this.subtitle,
    this.leadingEmoji,
  });

  /// 选项主标题（调用方传入既有文案，如「🚗 纯自驾」）。
  final String title;

  /// 可选副行；无可靠数据时应传 null（宁可少显示，不可显示错）。
  final String? subtitle;

  /// 可选前置表情/图标文本。
  final String? leadingEmoji;
}

/// 设计图 `.opt-card`（ui-octopus.css :114-136）两态：
/// 选中 = 紫色实心 + 白字；未选 = 白色描边 + 深灰字。
class StepOptionCard extends StatelessWidget {
  const StepOptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leadingEmoji,
  });

  final String title;
  final String? subtitle;
  final String? leadingEmoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background = selected ? kWizardPurple : Colors.white;
    final Color borderColor = selected ? kWizardPurple : kWizardCardLine;
    final Color titleColor = selected ? Colors.white : kWizardInk;
    final Color subtitleColor =
        selected ? const Color(0xD9FFFFFF) : kWizardInk2;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kWizardPurple.withValues(alpha: 0.28),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            if (leadingEmoji != null) ...[
              Text(leadingEmoji!, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle!,
                        style: TextStyle(fontSize: 11.5, color: subtitleColor),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: selected ? Colors.white : kWizardInk2,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单选组（对齐原型 `selectCard()`：同组只有一个 `.opt-card.on`）。
///
/// 组件只负责「单选」这件事，选中值由调用方持有并跨步保存。
class StepOptionGroup extends StatelessWidget {
  const StepOptionGroup({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.optionKeyPrefix = 'wizardOption',
  });

  final List<StepOptionItem> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 生成每个选项卡的 key：`<prefix><index>`，便于 widget 测试精确定位。
  final String optionKeyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List<Widget>.generate(options.length, (int index) {
        final StepOptionItem option = options[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: StepOptionCard(
            key: Key('$optionKeyPrefix$index'),
            title: option.title,
            subtitle: option.subtitle,
            leadingEmoji: option.leadingEmoji,
            selected: index == selectedIndex,
            onTap: () => onSelected(index),
          ),
        );
      }),
    );
  }
}
