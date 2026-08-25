import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import 'stage_icons.dart';

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

class TagBadge extends StatelessWidget {
  const TagBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.leaf.withValues(alpha: 0.14),
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
          'Готовность · ${(progress * 100).round()}%',
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
              padding: EdgeInsets.all(size * 0.06),
              child: Image.asset(
                icon,
                width: size,
                height: size,
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
          glyph: StageGlyphKind.soak,
        ),
      if (plant.hasGerminateStage)
        _StageInfo(
          title: 'Проращивание',
          detail: plant.germinateLabel,
          note: plant.needsPress
              ? 'В темноте, прижим ${plant.pressLabel}'
              : plant.pressLabel,
          glyph: StageGlyphKind.germinate,
        ),
      if (plant.hasGrowStage)
        _StageInfo(
          title: 'Рост',
          detail: plant.growLabel,
          note: 'На свету. Нижний полив: проверить уровень воды',
          glyph: StageGlyphKind.grow,
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
                  child: StageGlyph(
                    kind: stages[i].glyph,
                    color: AppColors.meadow,
                    size: 22,
                  ),
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

/// Result of the start-tray bottom sheet.
class StartTrayResult {
  const StartTrayResult({
    required this.startedAt,
    required this.stage,
    required this.customName,
    required this.seedGrams,
  });

  final DateTime startedAt;
  final GrowthStage stage;
  final String customName;
  final int seedGrams;
}

/// Bottom sheet: name, start date, current stage, seed weight.
Future<StartTrayResult?> showStartDateSheet({
  required BuildContext context,
  required Plant plant,
}) {
  return showModalBottomSheet<StartTrayResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _StartDateSheet(plant: plant),
  );
}

String addedToGardenMessage(String name, DateTime startedAt) {
  final date = formatStartDate(startedAt).replaceAll('.', '');
  return '$name от $date - на Моей грядке';
}

/// Opens the start sheet, saves the tray, shows «Горох от 8 авг - на Моей грядке».
Future<bool> addPlantToGarden({
  required BuildContext context,
  required Plant plant,
  required GardenStore store,
}) async {
  final result = await showStartDateSheet(context: context, plant: plant);
  if (result == null || !context.mounted) return false;

  await store.startPlant(
    plantId: plant.id,
    startedAt: result.startedAt,
    stage: result.stage,
    customName: result.customName,
    seedGrams: result.seedGrams,
  );
  if (!context.mounted) return true;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(addedToGardenMessage(result.customName, result.startedAt)),
      behavior: SnackBarBehavior.floating,
    ),
  );
  return true;
}

class _StartDateSheet extends StatefulWidget {
  const _StartDateSheet({required this.plant});

  final Plant plant;

  @override
  State<_StartDateSheet> createState() => _StartDateSheetState();
}

class _StartDateSheetState extends State<_StartDateSheet> {
  late DateTime _date = DateTime.now();
  late GrowthStage _stage;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plant.name);
    _stage = GardenPlant.initialStageFor(widget.plant);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  DateTime get _resolvedStart {
    final now = DateTime.now();
    final sameDay =
        _date.year == now.year && _date.month == now.month && _date.day == now.day;
    if (sameDay) return now;
    return DateTime(_date.year, _date.month, _date.day, now.hour, now.minute);
  }

  GardenPlant get _previewGarden => GardenPlant(
        id: 'preview',
        plantId: widget.plant.id,
        startedAt: _resolvedStart,
        lastWateredAt: _resolvedStart,
        stage: _stage,
        stageChangedAt: _resolvedStart,
      );

  String get _harvestHint {
    final plant = widget.plant;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final preview = _previewGarden;
    final minDays = preview.daysUntilHarvestMin(plant, now);
    final maxDays = preview.daysUntilHarvest(plant, now);
    if (maxDays <= 0 && minDays <= 0) {
      return 'ожидаем урожай ${GardenPlant.whenPhrase(0, today)}';
    }
    return 'ожидаем урожай ${GardenPlant.daysRangePhrase(minDays, maxDays, today)}';
  }

  Future<void> _editDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final earliest = today.subtract(const Duration(days: 60));
    var selected = DateTime(_date.year, _date.month, _date.day);
    if (selected.isAfter(today)) selected = today;
    if (selected.isBefore(earliest)) selected = earliest;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Дата старта',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Прокрутите день, месяц и год',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                SizedBox(
                  height: 180,
                  child: Localizations.override(
                    context: context,
                    locale: const Locale('ru'),
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        textTheme: CupertinoTextThemeData(
                          dateTimePickerTextStyle: TextStyle(
                            fontSize: 22,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.date,
                        dateOrder: DatePickerDateOrder.dmy,
                        initialDateTime: selected,
                        minimumDate: earliest,
                        maximumDate: today,
                        onDateTimeChanged: (value) {
                          selected = DateTime(
                            value.year,
                            value.month,
                            value.day,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.leaf,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;
    setState(() => _date = selected);
  }

  void _submit() {
    final name = _nameController.text.trim();
    Navigator.of(context).pop(
      StartTrayResult(
        startedAt: _resolvedStart,
        stage: _stage,
        customName: name.isEmpty ? widget.plant.name : name,
        seedGrams: widget.plant.seedGrams,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plant = widget.plant;
    final stages = plant.startableStages;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: SingleChildScrollView(
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
                'Новый цикл выращивания',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Название',
                  hintText: plant.name,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                                'Дата старта',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatStartDate(_date),
                                style: Theme.of(context).textTheme.titleMedium,
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
              if (stages.length > 1) ...[
                const SizedBox(height: 12),
                Text(
                  'Текущая стадия',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final stage in stages)
                      ChoiceChip(
                        label: Text(stageLabel(stage)),
                        selected: _stage == stage,
                        avatar: StageGlyph(
                          kind: stageGlyphKind(stage),
                          size: 18,
                          color: _stage == stage
                              ? Colors.white
                              : AppColors.meadow,
                        ),
                        selectedColor: AppColors.leaf,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _stage == stage
                              ? Colors.white
                              : AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(
                          color: _stage == stage
                              ? AppColors.leaf
                              : AppColors.mist.withValues(alpha: 0.9),
                        ),
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _stage = stage),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  plant.stageHint(_stage),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '${plant.seedGramsLabel} семян на лоток 13×18',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _harvestHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.forest,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.leaf,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Начать'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageInfo {
  const _StageInfo({
    required this.title,
    required this.detail,
    required this.note,
    required this.glyph,
  });

  final String title;
  final String detail;
  final String note;
  final StageGlyphKind glyph;
}
