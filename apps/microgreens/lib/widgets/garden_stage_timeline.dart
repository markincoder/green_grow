import 'package:flutter/material.dart';

import '../models/plant.dart';
import '../services/garden_stage_timeline.dart' as timeline;
import '../theme/app_theme.dart';
import 'common_widgets.dart';
import 'stage_icons.dart';

class GardenStageTimeline extends StatelessWidget {
  const GardenStageTimeline({
    super.key,
    required this.periods,
    required this.now,
  });

  final List<timeline.GardenStagePeriod> periods;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) {
      return SoftPanel(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Этапы появятся после действий с лотком',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < periods.length; i++) ...[
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
                    kind: stageGlyphKind(periods[i].stage),
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
                        timeline.gardenStageTitle(periods[i].stage),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        periods[i].durationLabel(now),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: AppColors.forest,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        periods[i].rangeLabel(now),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (i < periods.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}
