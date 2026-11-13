import 'package:flutter/material.dart';

import 'wizard_colors.dart';

/// 设计图 `.step-dots`（ui-trip-create.html :119-124）：
/// 4 个步骤圆点，当前步为紫色长条，其余为浅灰圆点；**点击可直接跳步**。
///
/// 颜色来自 `wizard_colors.dart`（字面量，来源 `ui-octopus.css`），
/// 不引用并行批次正在新建的 `OctopusColors`。
class WizardStepIndicator extends StatelessWidget {
  const WizardStepIndicator({
    super.key,
    required this.current,
    this.total = 4,
    this.onStepTap,
  });

  /// 当前步（0-based）。
  final int current;

  /// 步骤总数。
  final int total;

  /// 圆点点击回调，回传目标步索引（0-based）；为 null 时不可点。
  final ValueChanged<int>? onStepTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(total, (int index) {
        final bool selected = index == current;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3.5),
          child: GestureDetector(
            key: Key('wizardStepDot$index'),
            behavior: HitTestBehavior.opaque,
            onTap: onStepTap == null ? null : () => onStepTap!(index),
            child: Semantics(
              button: onStepTap != null,
              selected: selected,
              label: '第 ${index + 1} 步',
              child: SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Container(
                    width: selected ? 16 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: selected ? kWizardPurple : kWizardDotIdle,
                      borderRadius: BorderRadius.circular(selected ? 3 : 4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
