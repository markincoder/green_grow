import 'dart:async';

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

/// Generic leaf icon (same as knowledge-base tab), for places without a photo.
class TrayGlyph extends StatelessWidget {
  const TrayGlyph({super.key, this.size = 56, this.onTap});

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.mist,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        Icons.eco_rounded,
        size: size * 0.48,
        color: AppColors.meadow,
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: child,
      ),
    );
  }
}

Future<DateTime?> showAppDateWheel({
  required BuildContext context,
  required String title,
  required DateTime initialDate,
  required DateTime minimumDate,
  required DateTime maximumDate,
}) async {
  var min = DateTime(minimumDate.year, minimumDate.month, minimumDate.day);
  var max = DateTime(maximumDate.year, maximumDate.month, maximumDate.day);
  if (min.isAfter(max)) min = max;
  var selected = DateTime(initialDate.year, initialDate.month, initialDate.day);
  if (selected.isBefore(min)) selected = min;
  if (selected.isAfter(max)) selected = max;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
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
              Text(title, style: Theme.of(context).textTheme.titleLarge),
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
                      minimumDate: min,
                      maximumDate: max,
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

  if (confirmed != true) return null;
  return selected;
}

Future<void> renameTray(
  BuildContext context, {
  required GardenPlant gardenPlant,
  required Plant plant,
  required Future<void> Function(String name) onRename,
}) async {
  final controller = TextEditingController(
    text: gardenPlant.displayName(plant),
  );
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Название лотка'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Например: Редис Санго, джут',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (result == null) return;
  await onRename(result);
}

/// Tray name with optional pencil edit; start date on the next line.
class TrayTitleBlock extends StatelessWidget {
  const TrayTitleBlock({
    super.key,
    required this.gardenPlant,
    required this.plant,
    required this.onRename,
    this.titleStyle,
    this.dateStyle,
    this.showEditButton = true,
  });

  final GardenPlant gardenPlant;
  final Plant plant;
  final Future<void> Function(String name) onRename;
  final TextStyle? titleStyle;
  final TextStyle? dateStyle;
  final bool showEditButton;

  Future<void> _edit(BuildContext context) => renameTray(
        context,
        gardenPlant: gardenPlant,
        plant: plant,
        onRename: onRename,
      );

  @override
  Widget build(BuildContext context) {
    final nameStyle = titleStyle ?? Theme.of(context).textTheme.titleMedium;
    final date = dateStyle ??
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                gardenPlant.displayName(plant),
                style: nameStyle,
                softWrap: true,
              ),
            ),
            if (showEditButton)
              IconButton(
                tooltip: 'Переименовать',
                onPressed: () => _edit(context),
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.muted,
                ),
              ),
          ],
        ),
        Text(gardenPlant.startDateLine(), style: date),
      ],
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
          note: '',
          glyph: StageGlyphKind.soak,
        ),
      if (plant.hasGerminateStage)
        _StageInfo(
          title: 'Проращивание',
          detail: plant.germinateLabel,
          note: plant.germinateNote,
          glyph: StageGlyphKind.germinate,
        ),
      if (plant.hasGrowStage)
        _StageInfo(
          title: 'Рост',
          detail: plant.growLabel,
          note: plant.growNote,
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
                      if (stages[i].note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          stages[i].note,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
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
    this.trayCount = 1,
  });

  final DateTime startedAt;
  final GrowthStage stage;
  final String customName;
  final int seedGrams;
  final int trayCount;
}

/// Bottom sheet: name, start date, tray count, current stage.
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

/// 3s undo snackbar. A SnackBar with an action defaults to [SnackBar.persist],
/// so it would stay until tap; we set persist: false and also force-close.
///
/// The close timer must survive the screen that showed it: MainShell swaps
/// tabs with AnimatedSwitcher, and cancelling the timer on dispose left the
/// bar stuck across routes until the app was killed.
class UndoSnackBarHost {
  Timer? _autoClose;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _controller;
  int _generation = 0;

  void dispose() {
    // Keep [_autoClose] so the snackbar still hides after a tab switch.
  }

  void show({
    required BuildContext context,
    required String message,
    required Future<void> Function() onUndo,
  }) {
    _autoClose?.cancel();
    _generation++;
    final generation = _generation;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        persist: false,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            if (generation != _generation) return;
            _autoClose?.cancel();
            _autoClose = null;
            await onUndo();
          },
        ),
      ),
    );
    _controller = controller;
    _autoClose = Timer(const Duration(seconds: 3), () {
      if (generation != _generation) return;
      controller.close();
    });
    controller.closed.whenComplete(() {
      if (generation != _generation) return;
      _autoClose?.cancel();
      _autoClose = null;
      if (identical(_controller, controller)) {
        _controller = null;
      }
    });
  }
}

String addedToGardenMessage(String name, DateTime startedAt, {int trayCount = 1}) {
  final date = formatStartDate(startedAt).replaceAll('.', '');
  final base = '$name от $date';
  final withCount = trayCount > 1 ? '$base ($trayCount шт)' : base;
  return '$withCount - на Моей грядке';
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
    trayCount: result.trayCount,
  );
  if (!context.mounted) return true;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        addedToGardenMessage(
          result.customName,
          result.startedAt,
          trayCount: result.trayCount,
        ),
      ),
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
  int _trayCount = 1;

  static const int _trayCountMax = 99;

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

  InputDecoration _fieldDecoration(String labelText) {
    return InputDecoration(
      labelText: labelText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  void _changeTrayCount(int delta) {
    final next = (_trayCount + delta).clamp(1, _trayCountMax);
    if (next == _trayCount) return;
    setState(() => _trayCount = next);
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
                  'Если уже посеяли - выберите дату посева и этап Проращивание.\nЕсли зелень уже растет - выберите дату переноса лотка на свет и этап Рост.',
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
        trayCount: _trayCount,
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
                'Новый лоток',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Название (например, сорт)',
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _editDate,
                        borderRadius: BorderRadius.circular(16),
                        child: InputDecorator(
                          decoration: _fieldDecoration('Дата старта'),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                color: AppColors.meadow,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  formatStartDate(_date),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              const Icon(
                                Icons.edit_calendar_outlined,
                                color: AppColors.leaf,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: InputDecorator(
                      decoration: _fieldDecoration('Число лотков'),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _TrayCountButton(
                            icon: Icons.remove_rounded,
                            onPressed: _trayCount > 1
                                ? () => _changeTrayCount(-1)
                                : null,
                          ),
                          Text(
                            '$_trayCount',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          _TrayCountButton(
                            icon: Icons.add_rounded,
                            onPressed: _trayCount < _trayCountMax
                                ? () => _changeTrayCount(1)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (stages.length > 1) ...[
                const SizedBox(height: 12),
                Text(
                  'Этап старта',
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
                child: const Text('Старт'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrayCountButton extends StatelessWidget {
  const _TrayCountButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        style: IconButton.styleFrom(
          foregroundColor: AppColors.leaf,
          disabledForegroundColor: AppColors.mist,
          minimumSize: const Size(24, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: 20),
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
