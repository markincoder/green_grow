import 'package:flutter/material.dart';

import '../services/tray_history_store.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// Tray action history: date/time on the first line, `действие → этап` on the second.
class GardenActionHistory extends StatelessWidget {
  const GardenActionHistory({
    super.key,
    required this.events,
  });

  final List<TrayHistoryEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return SoftPanel(
        padding: const EdgeInsets.all(14),
        child: Text(
          'История появится после действий с лотком',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < events.length; i++) ...[
          SoftPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatHistoryStamp(events[i].at),
                    textAlign: TextAlign.left,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    trayHistoryActionLine(events[i]),
                    textAlign: TextAlign.left,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                  ),
                ],
              ),
            ),
          ),
          if (i < events.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}
