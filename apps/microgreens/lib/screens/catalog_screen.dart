import 'package:flutter/material.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'plant_detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.store,
    this.onListPlantAdded,
    this.onDetailPlantAdded,
  });

  final GardenStore store;
  final VoidCallback? onListPlantAdded;
  final VoidCallback? onDetailPlantAdded;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _query = '';
  Difficulty? _difficulty;

  List<Plant> get _filtered {
    final q = _query.trim().toLowerCase();
    final items = plantsCatalog.where((plant) {
      final matchesQuery = q.isEmpty ||
          plant.name.toLowerCase().contains(q) ||
          plant.tags.any((t) => t.contains(q));
      final matchesDifficulty =
          _difficulty == null || plant.difficulty == _difficulty;
      return matchesQuery && matchesDifficulty;
    }).toList();
    items.sort((a, b) => _nameKey(a.name).compareTo(_nameKey(b.name)));
    return items;
  }

  static String _nameKey(String name) =>
      name.toLowerCase().replaceAll('ё', 'е');

  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'База знаний',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Выберите вид микрозелени для выращивания',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Поиск: редис, горох…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 1 + Difficulty.values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _DifficultyChip(
                          label: 'все',
                          selected: _difficulty == null,
                          onSelected: () => setState(() => _difficulty = null),
                        );
                      }
                      final level = Difficulty.values[index - 1];
                      return _DifficultyChip(
                        label: switch (level) {
                          Difficulty.easy => 'Легко',
                          Difficulty.medium => 'Средне',
                          Difficulty.hard => 'Сложно',
                        },
                        selected: _difficulty == level,
                        onSelected: () => setState(() => _difficulty = level),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'Ничего не найдено',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final plant = items[index];
                      return SoftPanel(
                        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PlantDetailScreen(
                                          plant: plant,
                                          store: widget.store,
                                          onPlantAdded:
                                              widget.onDetailPlantAdded,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      PlantAvatar(icon: plant.icon, size: 58),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              plant.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            Text(
                                              plant.tags.take(3).join(' · '),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: AppColors.muted,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '${plant.seedGrams} г на лоток · Полный цикл ${plant.cycleDaysLabel}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton.filled(
                              tooltip: 'Добавить на грядку',
                              onPressed: () async {
                                final added = await addPlantToGarden(
                                  context: context,
                                  plant: plant,
                                  store: widget.store,
                                );
                                if (added) widget.onListPlantAdded?.call();
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.leaf,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(40, 40),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.add_rounded, size: 22),
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

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({
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
