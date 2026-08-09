import 'package:flutter/material.dart';

import '../data/plants_data.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'plant_detail_screen.dart';

class GardenScreen extends StatelessWidget {
  const GardenScreen({super.key, required this.store});

  final GardenStore store;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final plants = store.plants;

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
                  'Моя зелень',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  plants.isEmpty
                      ? 'Пока пусто'
                      : '${plants.length} лотков в работе',
                  style: Theme.of(context).textTheme.bodyMedium,
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
                            'Выберите культуру в справочнике и нажмите «Начать» на её экране.',
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
                                store: store,
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
                                  onPressed: () =>
                                      store.removePlant(gardenPlant.id),
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
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonal(
                                onPressed: () =>
                                    store.advancePlant(gardenPlant.id),
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
