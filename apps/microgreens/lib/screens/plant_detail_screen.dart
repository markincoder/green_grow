import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class PlantDetailScreen extends StatelessWidget {
  const PlantDetailScreen({
    super.key,
    required this.plant,
    required this.store,
    this.gardenPlant,
  });

  final Plant plant;
  final GardenStore store;
  final GardenPlant? gardenPlant;

  Future<void> _start(BuildContext context) async {
    final added = await addPlantToGarden(
      context: context,
      plant: plant,
      store: store,
    );
    if (added && context.mounted) Navigator.of(context).pop();
  }

  Future<void> _advance(BuildContext context) async {
    final gp = gardenPlant;
    if (gp == null) return;
    final completes = gp.completesNext(plant);
    await store.advancePlant(gp.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          completes ? 'Собрано — убрано с Моей грядки' : 'Этап обновлён',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (completes) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final now = DateTime.now();
        final gpId = gardenPlant?.id;
        final gp = gpId == null
            ? null
            : store.plants.where((p) => p.id == gpId).firstOrNull;

        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: Text(plant.name),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              SoftPanel(
                color: AppColors.mist.withValues(alpha: 0.65),
                child: Row(
                  children: [
                    PlantAvatar(
                      icon: plant.icon,
                      size: 72,
                      background: Colors.white,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plant.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          DifficultyBadge(difficulty: plant.difficulty),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (gp == null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => _start(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.leaf,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Добавить на грядку'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                plant.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (gp != null) ...[
                const SizedBox(height: 20),
                SoftPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gp.titleWithDate(plant),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        gp.statusLine(plant, now),
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: gp.completesNext(plant)
                                      ? AppColors.sun
                                      : AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 14),
                      GrowthProgressBar(
                        progress: gp.progressFor(plant, now),
                        stage: gp.stageFor(plant, now),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        gp.harvestLine(plant, now),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _advance(context),
                          icon: Icon(
                            gp.completesNext(plant)
                                ? Icons.content_cut_rounded
                                : Icons.arrow_forward_rounded,
                          ),
                          label: Text(gp.nextActionLabel(plant)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text('Стадии', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              StageTimeline(plant: plant),
              const SizedBox(height: 24),
              Text('Условия', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(
                    icon: Icons.scale_outlined,
                    label: '${gp?.seedGrams ?? plant.seedGrams} г на лоток 13×18',
                  ),
                  _InfoChip(icon: Icons.wb_sunny_outlined, label: plant.light),
                  _InfoChip(icon: Icons.thermostat, label: plant.temperature),
                  _InfoChip(icon: Icons.grass, label: plant.soil),
                  _InfoChip(
                    icon: Icons.schedule,
                    label: 'Полный цикл ${plant.cycleDaysLabel}',
                  ),
                  if (plant.feature != null)
                    _InfoChip(
                      icon: Icons.info_outline_rounded,
                      label: plant.feature!,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Советы', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              ...plant.tips.map(
                (tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftPanel(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '•  ',
                          style: TextStyle(color: AppColors.meadow),
                        ),
                        Expanded(
                          child: Text(
                            tip,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.ink,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.mist),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.meadow),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}
