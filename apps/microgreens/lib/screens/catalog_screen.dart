import 'package:flutter/material.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'plant_detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.store});

  final GardenStore store;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _query = '';
  String _tag = 'все';

  static const _filters = [
    'все',
    'быстро',
    'новичкам',
    'острое',
    'мягкое',
    'медленные',
    'злаки',
  ];

  List<Plant> get _filtered {
    return plantsCatalog.where((plant) {
      final q = _query.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          plant.name.toLowerCase().contains(q) ||
          plant.tags.any((t) => t.contains(q));
      final matchesTag = _tag == 'все' || plant.tags.contains(_tag);
      return matchesQuery && matchesTag;
    }).toList();
  }

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
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final tag = _filters[index];
                      final selected = tag == _tag;
                      return ChoiceChip(
                        label: Text(tag),
                        selected: selected,
                        onSelected: (_) => setState(() => _tag = tag),
                        selectedColor: AppColors.sprout,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: AppColors.forest,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
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
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PlantDetailScreen(
                                plant: plant,
                                store: widget.store,
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plant.name,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
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
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            DifficultyBadge(difficulty: plant.difficulty),
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
