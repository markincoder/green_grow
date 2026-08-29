import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../services/garden_stage_timeline.dart';
import '../state/favorites_store.dart';
import '../state/garden_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/favorite_star.dart';
import '../widgets/garden_stage_timeline.dart';

class PlantDetailScreen extends StatefulWidget {
  const PlantDetailScreen({
    super.key,
    required this.plant,
    required this.store,
    required this.favorites,
    this.gardenPlant,
    this.onPlantAdded,
  });

  final Plant plant;
  final GardenStore store;
  final FavoritesStore favorites;
  final GardenPlant? gardenPlant;
  final VoidCallback? onPlantAdded;

  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  String? _stagePeriodsKey;
  Future<List<GardenStagePeriod>>? _stagePeriodsFuture;

  void _reloadStagePeriods(GardenPlant gp, Plant plant) {
    _stagePeriodsFuture = loadGardenStagePeriods(garden: gp, plant: plant);
  }

  Future<void> _start(BuildContext context) async {
    final added = await addPlantToGarden(
      context: context,
      plant: widget.plant,
      store: widget.store,
    );
    if (added && context.mounted) {
      Navigator.of(context).pop();
      widget.onPlantAdded?.call();
    }
  }

  Future<void> _advance(BuildContext context, GardenPlant gp) async {
    final completes = gp.completesNext(widget.plant);
    await widget.store.advancePlant(gp.id);
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

  void _openCultureCard(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlantDetailScreen(
          plant: widget.plant,
          store: widget.store,
          favorites: widget.favorites,
          onPlantAdded: widget.onPlantAdded,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.store, widget.favorites]),
      builder: (context, _) {
        final now = DateTime.now();
        final plant = widget.plant;
        final gpId = widget.gardenPlant?.id;
        final gp = gpId == null
            ? null
            : widget.store.plants.where((p) => p.id == gpId).firstOrNull;
        final isFavorite = widget.favorites.isFavorite(plant.id);
        final isTray = gp != null;

        if (isTray) {
          final periodsKey =
              '${gp.id}|${gp.stage.name}|${gp.stageChangedAt.millisecondsSinceEpoch}';
          if (_stagePeriodsKey != periodsKey) {
            _stagePeriodsKey = periodsKey;
            _reloadStagePeriods(gp, plant);
          }
        }

        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: isTray
                ? Row(
                    children: [
                      TrayGlyph(
                        size: 34,
                        onTap: () => _openCultureCard(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          plant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : Text(plant.name),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (isTray)
                SoftPanel(
                  color: AppColors.mist.withValues(alpha: 0.65),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TrayTitleBlock(
                        gardenPlant: gp,
                        plant: plant,
                        onRename: (name) =>
                            widget.store.updateCustomName(gp.id, name),
                        titleStyle: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        gp.statusLine(plant, now),
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: gp.isStatusActionDueToday(plant, now)
                                      ? AppColors.sun
                                      : AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 12),
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
                          onPressed: () => _advance(context, gp),
                          icon: gp.completesNext(plant)
                              ? const Icon(Icons.content_cut_rounded)
                              : const SizedBox.shrink(),
                          label: Text(gp.nextActionLabel(plant)),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                SoftPanel(
                  color: AppColors.mist.withValues(alpha: 0.65),
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PlantPhotoCarousel(photos: plant.cardPhotos),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    plant.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: isFavorite
                                      ? 'Убрать из избранного'
                                      : 'В избранное',
                                  onPressed: () =>
                                      widget.favorites.toggle(plant.id),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(36, 36),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.all(4),
                                  ),
                                  icon: FavoriteStar(
                                    filled: isFavorite,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            if (plant.tags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: plant.tags
                                    .map(
                                      (tag) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.leaf
                                              .withValues(alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          tag,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: AppColors.forest,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                const SizedBox(height: 16),
                Text(
                  plant.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (plant.taste != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.restaurant_rounded,
                          size: 20,
                          color: AppColors.forest,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          plant.taste!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ],
                if (plant.benefit != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Польза: ${plant.benefit}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ],
              const SizedBox(height: 24),
              Text(
                'Этапы',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (isTray)
                FutureBuilder<List<GardenStagePeriod>>(
                  future: _stagePeriodsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SoftPanel(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return GardenStageTimeline(
                      periods: snapshot.data ?? const [],
                      now: now,
                    );
                  },
                )
              else
                StageTimeline(plant: plant),
              if (!isTray) ...[
                const SizedBox(height: 24),
                Text('Условия', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoChip(
                      icon: Icons.schedule,
                      label: 'Полный цикл ${plant.cycleDaysLabel}',
                    ),
                    _InfoChip(
                      icon: Icons.scale_outlined,
                      label:
                          '${plant.seedGramsLabel} · Вес семян на лоток 19×11 или 18×13 см',
                    ),
                    if (plant.tray != null)
                      _InfoChip(
                        glyph: _ConditionGlyph.tray,
                        label: plant.tray!,
                      ),
                    _InfoChip(
                      glyph: _ConditionGlyph.mat,
                      label: plant.soil,
                    ),
                    if (plant.feature != null)
                      _InfoChip(
                        icon: Icons.info_outline_rounded,
                        label: plant.feature!,
                      ),
                    _InfoChip(
                      icon: Icons.wb_sunny_outlined,
                      label: plant.light,
                    ),
                    _InfoChip(
                      icon: Icons.thermostat,
                      label: plant.temperature,
                    ),
                    if (plant.storage != null)
                      _InfoChip(
                        glyph: _ConditionGlyph.jar,
                        label: plant.storage!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    this.icon,
    this.glyph,
    required this.label,
  }) : assert(icon != null || glyph != null);

  final IconData? icon;
  final _ConditionGlyph? glyph;
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
          if (glyph != null)
            _ConditionGlyphIcon(kind: glyph!)
          else
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

enum _ConditionGlyph { tray, jar, mat }

class _ConditionGlyphIcon extends StatelessWidget {
  const _ConditionGlyphIcon({required this.kind});

  final _ConditionGlyph kind;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(
        painter: _ConditionGlyphPainter(kind: kind, color: AppColors.meadow),
      ),
    );
  }
}

class _ConditionGlyphPainter extends CustomPainter {
  const _ConditionGlyphPainter({required this.kind, required this.color});

  final _ConditionGlyph kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.scale(s / 24, s / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    switch (kind) {
      case _ConditionGlyph.tray:
        _paintTray(canvas, stroke);
      case _ConditionGlyph.jar:
        _paintJar(canvas, stroke, fill);
      case _ConditionGlyph.mat:
        _paintMat(canvas, stroke);
    }
    canvas.restore();
  }

  void _paintTray(Canvas canvas, Paint stroke) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 10, 18, 9),
      const Radius.circular(2.2),
    );
    canvas.drawRRect(body, stroke);
    canvas.drawLine(const Offset(5, 10), const Offset(7, 5.5), stroke);
    canvas.drawLine(const Offset(19, 10), const Offset(17, 5.5), stroke);
    canvas.drawLine(const Offset(7, 5.5), const Offset(17, 5.5), stroke);
  }

  void _paintJar(Canvas canvas, Paint stroke, Paint fill) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(6.5, 7.5, 11, 13),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, stroke);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5.5, 4, 13, 3.8),
        const Radius.circular(1.2),
      ),
      stroke,
    );
    canvas.drawCircle(const Offset(12, 13.5), 1.1, fill);
  }

  void _paintMat(Canvas canvas, Paint stroke) {
    final mat = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.5, 6.5, 17, 11),
      const Radius.circular(2),
    );
    canvas.drawRRect(mat, stroke);
    canvas.drawLine(const Offset(6.5, 10), const Offset(17.5, 10), stroke);
    canvas.drawLine(const Offset(6.5, 14), const Offset(17.5, 14), stroke);
  }

  @override
  bool shouldRepaint(covariant _ConditionGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

class _PlantPhotoCarousel extends StatefulWidget {
  const _PlantPhotoCarousel({required this.photos});

  final List<String> photos;

  @override
  State<_PlantPhotoCarousel> createState() => _PlantPhotoCarouselState();
}

class _PlantPhotoCarouselState extends State<_PlantPhotoCarousel> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openGallery(int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _PlantPhotoLightbox(
              photos: widget.photos,
              initialIndex: initialIndex,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final multi = photos.length > 1;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: PageView.builder(
                controller: _controller,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openGallery(i),
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          photos[i],
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (multi)
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(photos.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 16 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.leaf
                            : AppColors.mist.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PlantPhotoLightbox extends StatefulWidget {
  const _PlantPhotoLightbox({
    required this.photos,
    required this.initialIndex,
  });

  final List<String> photos;
  final int initialIndex;

  @override
  State<_PlantPhotoLightbox> createState() => _PlantPhotoLightboxState();
}

class _PlantPhotoLightboxState extends State<_PlantPhotoLightbox> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.photos.length > 1;
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const ColoredBox(color: Colors.transparent),
          ),
          PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              return Center(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Image.asset(
                    widget.photos[i],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          if (multi)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.photos.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 16 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
            ),
          Positioned(
            top: topPad + 12,
            right: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _close,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
