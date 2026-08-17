import 'package:flutter/material.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'plant_detail_screen.dart';

class GardenScreen extends StatefulWidget {
  const GardenScreen({
    super.key,
    required this.store,
    required this.onAddPlant,
  });

  final GardenStore store;
  final VoidCallback onAddPlant;

  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  GrowthStage? _stage;

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

  int _countFor(GrowthStage stage, DateTime now) {
    return widget.store.plants.where((g) {
      final plant = plantById(g.plantId);
      return plant != null && g.stageFor(plant, now) == stage;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final all = _byHarvestDate(widget.store.plants, now);
    final plants = _stage == null
        ? all
        : all.where((g) {
            final plant = plantById(g.plantId);
            return plant != null && g.stageFor(plant, now) == _stage;
          }).toList();

    final subtitle = all.isEmpty
        ? 'Пока пусто'
        : _stage == null
            ? '${plants.length} активно'
            : plants.isEmpty
                ? 'Нет посадок на этой стадии'
                : '${plants.length} · ${stageLabel(_stage!)}';

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
                    itemCount: 1 + GrowthStage.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _StageChip(
                          label: 'все',
                          selected: _stage == null,
                          onSelected: () => setState(() => _stage = null),
                        );
                      }
                      final stage = GrowthStage.values[index - 1];
                      final count = _countFor(stage, now);
                      return _StageChip(
                        label: count > 0
                            ? '${stageLabel(stage)} $count'
                            : stageLabel(stage),
                        selected: _stage == stage,
                        onSelected: () => setState(() => _stage = stage),
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
                                : 'На этой стадии пока никого нет.',
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
                      final ready = gardenPlant.completesNext(plant);

                      return SoftPanel(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlantDetailScreen(
                                plant: plant,
                                store: widget.store,
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
                                PlantAvatar(icon: plant.icon, size: 56),
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
                                              color: ready
                                                  ? AppColors.sun
                                                  : AppColors.muted,
                                              fontWeight: ready
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Удалить',
                                  onPressed: () => widget.store
                                      .removePlant(gardenPlant.id),
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
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.sprout,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: AppColors.forest,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}
