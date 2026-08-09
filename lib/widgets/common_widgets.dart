import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.mist.withValues(alpha: 0.9)),
      ),
      child: child,
    );

    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: panel,
      ),
    );
  }
}

class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge({super.key, required this.difficulty});

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (difficulty) {
      Difficulty.easy => ('Легко', AppColors.sprout),
      Difficulty.medium => ('Средне', AppColors.sun),
      Difficulty.hard => ('Сложно', const Color(0xFFE07A5F)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.forest,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class GrowthProgressBar extends StatelessWidget {
  const GrowthProgressBar({
    super.key,
    required this.progress,
    required this.stage,
  });

  final double progress;
  final GrowthStage stage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: AppColors.mist,
                color: stage == GrowthStage.harvest
                    ? AppColors.sun
                    : AppColors.meadow,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${stageLabel(stage)} · ${(progress * 100).round()}%',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class PlantAvatar extends StatelessWidget {
  const PlantAvatar({
    super.key,
    required this.icon,
    this.size = 52,
    this.background,
  });

  final String icon;
  final double size;
  final Color? background;

  bool get _isAsset => icon.startsWith('assets/');

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? AppColors.mist,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      clipBehavior: Clip.antiAlias,
      child: _isAsset
          ? Padding(
              padding: EdgeInsets.all(size * 0.08),
              child: Image.asset(
                icon,
                width: size * 0.84,
                height: size * 0.84,
                fit: BoxFit.contain,
              ),
            )
          : Text(icon, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

class StageTimeline extends StatelessWidget {
  const StageTimeline({super.key, required this.plant});

  final Plant plant;

  @override
  Widget build(BuildContext context) {
    final stages = <_StageInfo>[
      if (plant.needsSoak)
        _StageInfo(
          title: 'Замачивание',
          detail: plant.soakLabel,
          note: 'В воде, до суток',
          icon: Icons.water_drop_outlined,
        ),
      if (plant.hasGerminateStage)
        _StageInfo(
          title: 'Проращивание',
          detail: plant.germinateLabel,
          note: plant.needsPress
              ? 'В темноте, с крышкой, прижим ${plant.pressLabel}'
              : plant.pressLabel,
          icon: Icons.dark_mode_outlined,
        ),
      if (plant.hasGrowStage)
        _StageInfo(
          title: 'Выращивание',
          detail: plant.growLabel,
          note: 'На свету, без крышки. Вода на дне, проверка раз в день',
          icon: Icons.wb_sunny_outlined,
        ),
    ];

    return Column(
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          SoftPanel(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.mist.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(stages[i].icon, color: AppColors.meadow, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stages[i].title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stages[i].detail,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.forest,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stages[i].note,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (i < stages.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

IconData stageIcon(GrowthStage stage) => switch (stage) {
      GrowthStage.soak => Icons.water_drop_outlined,
      GrowthStage.germinate => Icons.dark_mode_outlined,
      GrowthStage.grow => Icons.wb_sunny_outlined,
      GrowthStage.harvest => Icons.content_cut_rounded,
    };

/// Bottom sheet: set planting start date (defaults to today).
Future<DateTime?> showStartDateSheet({
  required BuildContext context,
  required Plant plant,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _StartDateSheet(plant: plant),
  );
}

class _StartDateSheet extends StatefulWidget {
  const _StartDateSheet({required this.plant});

  final Plant plant;

  @override
  State<_StartDateSheet> createState() => _StartDateSheetState();
}

class _StartDateSheetState extends State<_StartDateSheet> {
  late DateTime _date = DateTime.now();

  DateTime get _resolvedStart {
    final now = DateTime.now();
    final sameDay =
        _date.year == now.year && _date.month == now.month && _date.day == now.day;
    if (sameDay) return now;
    return DateTime(_date.year, _date.month, _date.day, now.hour, now.minute);
  }

  DateTime get _expectedHarvest {
    final start = DateTime(_date.year, _date.month, _date.day);
    final days = widget.plant.daysToHarvest > 0
        ? widget.plant.daysToHarvest
        : widget.plant.germinateDaysMax;
    return start.add(Duration(days: days));
  }

  String get _harvestHint {
    final label = formatStartDate(_expectedHarvest).replaceAll('.', '');
    return 'ожидаем урожай ~$label';
  }

  Future<void> _editDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now,
      helpText: 'Дата старта',
      cancelText: 'Отмена',
      confirmText: 'Готово',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.mist,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Дата старта',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Укажите, когда начали ${plant.name}. По умолчанию — сегодня.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _editDate,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppColors.mist.withValues(alpha: 0.9),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.mist.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.calendar_today_rounded,
                        color: AppColors.meadow,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatStartDate(_date),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Нажмите, чтобы изменить',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.edit_calendar_outlined,
                      color: AppColors.leaf,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _harvestHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.forest,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_resolvedStart),
            child: const Text('Начать'),
          ),
        ],
      ),
    );
  }
}

class _StageInfo {
  const _StageInfo({
    required this.title,
    required this.detail,
    required this.note,
    required this.icon,
  });

  final String title;
  final String detail;
  final String note;
  final IconData icon;
}
