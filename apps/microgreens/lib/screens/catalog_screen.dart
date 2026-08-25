import 'package:flutter/material.dart';

import '../data/plants_data.dart';
import '../models/plant.dart';
import '../state/favorites_store.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/favorite_star.dart';
import 'plant_detail_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.store,
    required this.favorites,
    this.onListPlantAdded,
    this.onDetailPlantAdded,
  });

  final GardenStore store;
  final FavoritesStore favorites;
  final VoidCallback? onListPlantAdded;
  final VoidCallback? onDetailPlantAdded;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _query = '';
  String? _tag;
  bool _favoritesOnly = false;

  List<Plant> get _filtered {
    final q = _query.trim().toLowerCase();
    final items = plantsCatalog.where((plant) {
      final matchesQuery =
          q.isEmpty || plant.name.toLowerCase().contains(q);
      final matchesTag = _tag == null || plant.tags.contains(_tag);
      final matchesFavorites =
          !_favoritesOnly || widget.favorites.isFavorite(plant.id);
      return matchesQuery && matchesTag && matchesFavorites;
    }).toList();
    items.sort((a, b) => _nameKey(a.name).compareTo(_nameKey(b.name)));
    return items;
  }

  static String _nameKey(String name) =>
      name.toLowerCase().replaceAll('ё', 'е');

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favorites,
      builder: (context, _) {
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
                      'Выберите культуру для выращивания',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: 'Поиск',
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
                        itemCount: 2 + catalogFilterTags.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _FilterChip(
                              label: 'все',
                              selected: !_favoritesOnly && _tag == null,
                              onSelected: () => setState(() {
                                _favoritesOnly = false;
                                _tag = null;
                              }),
                            );
                          }
                          if (index == 1) {
                            return _FavoriteFilterChip(
                              selected: _favoritesOnly,
                              onSelected: () => setState(() {
                                _favoritesOnly = true;
                                _tag = null;
                              }),
                            );
                          }
                          final tag = catalogFilterTags[index - 2];
                          return _FilterChip(
                            label: tag,
                            selected: !_favoritesOnly && _tag == tag,
                            onSelected: () => setState(() {
                              _favoritesOnly = false;
                              _tag = tag;
                            }),
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
                          _favoritesOnly
                              ? 'Нет избранных культур'
                              : 'Ничего не найдено',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final plant = items[index];
                          final isFavorite =
                              widget.favorites.isFavorite(plant.id);
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
                                              favorites: widget.favorites,
                                              onPlantAdded:
                                                  widget.onDetailPlantAdded,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Row(
                                        children: [
                                          PlantAvatar(
                                            icon: plant.listAvatar,
                                            size: 58,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        plant.name,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleMedium,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    GestureDetector(
                                                      onTap: () => widget
                                                          .favorites
                                                          .toggle(plant.id),
                                                      behavior:
                                                          HitTestBehavior
                                                              .opaque,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(4),
                                                        child: FavoriteStar(
                                                          filled: isFavorite,
                                                          size: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Полный цикл ${plant.cycleDaysLabel}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                                Text(
                                                  '${plant.seedGramsLabel} на лоток',
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
                                    if (added) {
                                      widget.onListPlantAdded?.call();
                                    }
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.leaf,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(40, 40),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(
                                    Icons.add_rounded,
                                    size: 22,
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
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.leaf.withValues(alpha: 0.18),
      checkmarkColor: AppColors.leaf,
      labelStyle: TextStyle(
        color: selected ? AppColors.forest : AppColors.ink,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.leaf.withValues(alpha: 0.45)
            : AppColors.mist,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _FavoriteFilterChip extends StatelessWidget {
  const _FavoriteFilterChip({
    required this.selected,
    required this.onSelected,
  });

  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Избранное',
      child: Material(
        color: selected
            ? AppColors.leaf.withValues(alpha: 0.18)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? AppColors.leaf.withValues(alpha: 0.45)
                : AppColors.mist,
          ),
        ),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 40,
            width: 44,
            child: Center(
              child: FavoriteStar(
                filled: selected,
                size: 16,
                color: selected ? AppColors.sun : AppColors.leaf,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
