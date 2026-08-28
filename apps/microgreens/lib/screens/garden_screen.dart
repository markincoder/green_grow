import 'dart:async' as async;

import 'package:flutter/material.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../state/favorites_store.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/stage_icons.dart';
import 'plant_detail_screen.dart';

class GardenScreen extends StatefulWidget {
  const GardenScreen({
    super.key,
    required this.store,
    required this.favorites,
    required this.onAddPlant,
  });

  final GardenStore store;
  final FavoritesStore favorites;
  final VoidCallback onAddPlant;

  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  _GardenFilter _filter = _GardenFilter.all;

  Future<void> _deletePlant(GardenPlant gardenPlant, Plant plant) async {
    final undo = await widget.store.removePlant(gardenPlant.id);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(gardenPlant.titleWithDate(plant)),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down,
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () async {
            if (undo != null) {
              await widget.store.undoReminderAction(undo);
            }
          },
        ),
      ),
    );
    async.unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        controller.close();
      }),
    );
  }

  /// Soonest harvest date first.
  static List<GardenPlant> _byHarvestDate(
    List<GardenPlant> source,
    DateTime now,
  ) {
    final sorted = List<GardenPlant>.from(source);
    sorted.sort((a, b) {
      final plantA = plantById(a.plantId);
      final plantB = plantById(b.plantId);
      if (plantA == null && plantB == null) return 0;
      if (plantA == null) return 1;
      if (plantB == null) return -1;

      return a
          .harvestAtMin(plantA, now)
          .compareTo(b.harvestAtMin(plantB, now));
    });
    return sorted;
  }

  int _countForStage(GrowthStage stage, DateTime now) {
    return widget.store.plants.where((g) {
      final plant = plantById(g.plantId);
      return plant != null && g.stageFor(plant, now) == stage;
    }).length;
  }

  int _countDueToday(DateTime now) {
    return widget.store.plants.where((g) {
      final plant = plantById(g.plantId);
      if (plant == null) return false;
      return g.isStatusActionDueToday(plant, now);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final all = _byHarvestDate(widget.store.plants, now);
    final plants = all.where((g) {
      final plant = plantById(g.plantId);
      if (plant == null) return false;
      return switch (_filter) {
        _GardenFilter.all => true,
        _GardenFilter.soak => g.stageFor(plant, now) == GrowthStage.soak,
        _GardenFilter.germinate =>
          g.stageFor(plant, now) == GrowthStage.germinate,
        _GardenFilter.grow => g.stageFor(plant, now) == GrowthStage.grow,
        _GardenFilter.dueToday => g.isStatusActionDueToday(plant, now),
      };
    }).toList();

    final subtitle = all.isEmpty
        ? 'Пока пусто'
        : _filter == _GardenFilter.all
            ? '${plants.length} активно'
            : plants.isEmpty
                ? 'Нет активных по выбранному фильтру'
                : _filter == _GardenFilter.dueToday
                    ? '${plants.length} · требуют действия сегодня'
                    : '${plants.length} · ${stageLabel(switch (_filter) {
                        _GardenFilter.soak => GrowthStage.soak,
                        _GardenFilter.germinate => GrowthStage.germinate,
                        _GardenFilter.grow => GrowthStage.grow,
                        _ => GrowthStage.grow,
                      })}';

    const filters = [
      _FilterChipData(
        filter: _GardenFilter.all,
        tooltip: 'Все',
      ),
      _FilterChipData(
        filter: _GardenFilter.soak,
        glyph: StageGlyphKind.soak,
        tooltip: 'Замачивание',
      ),
      _FilterChipData(
        filter: _GardenFilter.germinate,
        glyph: StageGlyphKind.germinate,
        tooltip: 'Проращивание',
      ),
      _FilterChipData(
        filter: _GardenFilter.grow,
        glyph: StageGlyphKind.grow,
        tooltip: 'Рост',
      ),
      _FilterChipData(
        filter: _GardenFilter.dueToday,
        glyph: StageGlyphKind.dueToday,
        tooltip: 'Требуют действия сегодня',
      ),
    ];

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Моя грядка',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.leaf,
                      foregroundColor: Colors.white,
                      textStyle:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: widget.onAddPlant,
                    icon: const Icon(Icons.add_rounded, size: 24),
                    label: const Text('Выращивать'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final chip = filters[index];
                      final count = switch (chip.filter) {
                        _GardenFilter.all => all.length,
                        _GardenFilter.soak => _countForStage(GrowthStage.soak, now),
                        _GardenFilter.germinate =>
                          _countForStage(GrowthStage.germinate, now),
                        _GardenFilter.grow => _countForStage(GrowthStage.grow, now),
                        _GardenFilter.dueToday => _countDueToday(now),
                      };
                      return _StageChip(
                        glyph: chip.glyph,
                        tooltip: chip.tooltip,
                        count: count,
                        selected: _filter == chip.filter,
                        onSelected: () => setState(() => _filter = chip.filter),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: plants.isEmpty
                ? Center(
                    child: SoftPanel(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🌱', style: TextStyle(fontSize: 42)),
                          const SizedBox(height: 12),
                          Text(
                            all.isEmpty
                                ? 'Нажмите «Выращивать» — выберите культуру в базе знаний.'
                                : 'Нет активных',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: plants.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final gardenPlant = plants[index];
                      final plant = plantById(gardenPlant.plantId);
                      if (plant == null) return const SizedBox.shrink();
                      final stage = gardenPlant.stageFor(plant, now);
                      final progress = gardenPlant.progressFor(plant, now);
                      final actionDueToday =
                          gardenPlant.isStatusActionDueToday(plant, now);

                      return SoftPanel(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlantDetailScreen(
                                plant: plant,
                                store: widget.store,
                                favorites: widget.favorites,
                                gardenPlant: gardenPlant,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                PlantAvatar(icon: plant.listAvatar, size: 56),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        gardenPlant.titleWithDate(plant),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        gardenPlant.statusLine(plant, now),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: actionDueToday
                                                  ? AppColors.sun
                                                  : AppColors.muted,
                                              fontWeight: actionDueToday
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Удалить',
                                  onPressed: () => async.unawaited(
                                    _deletePlant(gardenPlant, plant),
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            GrowthProgressBar(
                              progress: progress,
                              stage: stage,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              gardenPlant.harvestLine(plant, now),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonal(
                                onPressed: () => widget.store
                                    .advancePlant(gardenPlant.id),
                                child: Text(
                                  gardenPlant.nextActionLabel(plant),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    this.glyph,
    required this.tooltip,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final StageGlyphKind? glyph;
  final String tooltip;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.forest;
    final isAll = glyph == null;
    return ChoiceChip(
      tooltip: tooltip,
      avatar: isAll
          ? null
          : StageGlyph(kind: glyph!, size: 18, color: color),
      label: Text(
        isAll ? 'Все' : '$count',
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.sprout,
      backgroundColor: Colors.white,
      labelPadding: isAll
          ? const EdgeInsets.symmetric(horizontal: 4)
          : const EdgeInsets.only(left: 2, right: 6),
      avatarBoxConstraints: const BoxConstraints(minWidth: 20),
    );
  }
}

enum _GardenFilter { all, soak, germinate, grow, dueToday }

class _FilterChipData {
  const _FilterChipData({
    required this.filter,
    this.glyph,
    required this.tooltip,
  });

  final _GardenFilter filter;
  final StageGlyphKind? glyph;
  final String tooltip;
}
