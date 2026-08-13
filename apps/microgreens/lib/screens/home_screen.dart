import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import '../state/garden_store.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.onAddPlant,
  });

  final GardenStore store;
  final SettingsStore settings;
  final VoidCallback onAddPlant;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Completed reminders kept gray for today after the garden stage changes.
  final Map<String, TodayReminderItem> _completedToday = {};
  String? _completedDayStamp;

  List<TodayReminderItem> get _reminders {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final stamp = SettingsStore.dayStamp(day);
    if (_completedDayStamp != stamp) {
      _completedToday.clear();
      _completedDayStamp = stamp;
    }

    final live = ReminderService.buildTodayReminders(
      plants: widget.store.plants,
      day: day,
      soakReminderHours: widget.settings.soakReminderHours,
      dismissedKeys: widget.settings.dismissedReminderKeys,
    );

    final byKey = <String, TodayReminderItem>{
      for (final item in live) item.key: item,
    };
    for (final snap in _completedToday.values) {
      byKey.putIfAbsent(snap.key, () => snap);
    }

    final ordered = <TodayReminderItem>[];
    final seen = <String>{};
    for (final item in live) {
      ordered.add(byKey[item.key]!);
      seen.add(item.key);
    }
    for (final snap in _completedToday.values) {
      if (seen.add(snap.key)) ordered.add(snap);
    }
    return ordered;
  }

  Future<void> _markDone(TodayReminderItem item) async {
    if (item.done) return;

    await widget.store.completeReminderAction(
      kind: item.kind,
      gardenId: item.gardenId,
    );

    final doneItem = TodayReminderItem(
      key: item.key,
      text: item.text,
      pushText: item.pushText,
      kind: item.kind,
      gardenId: item.gardenId,
      done: true,
    );
    _completedToday[item.key] = doneItem;
    _completedDayStamp = SettingsStore.dayStamp(DateTime.now());

    await widget.settings.dismissReminder(item.key);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.store, widget.settings]),
        builder: (context, _) {
          final reminders = _reminders;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Image.asset(
                  'assets/logo_agronizer.png',
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    'Микрозелень от agronizer',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppColors.forest,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.leaf,
                    foregroundColor: Colors.white,
                    textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: widget.onAddPlant,
                  icon: const Icon(Icons.add_rounded, size: 26),
                  label: const Text('Выращивать'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Выберите вид микрозелени и дату старта',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              SoftPanel(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SettingsScreen(settings: widget.settings),
                    ),
                  );
                },
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.settings.enabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_outlined,
                      color: widget.settings.enabled
                          ? AppColors.meadow
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Настройки уведомлений',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            widget.settings.enabled
                                ? 'Ежедневно в ${widget.settings.reminderTimeLabel}'
                                : 'Выключены · нажмите, чтобы настроить',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.forest,
                    ),
                  ],
                ),
              ),
              if (reminders.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Напоминания на сегодня',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                for (final item in reminders)
                  _ReminderTile(
                    item: item,
                    onDone: () => _markDone(item),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.item,
    required this.onDone,
  });

  final TodayReminderItem item;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final done = item.done;
    final color = done ? AppColors.muted : AppColors.ink;
    final accent = done ? AppColors.muted : AppColors.meadow;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(item.typeIcon, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: color,
                    height: 1.35,
                    decoration: done
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: AppColors.muted,
                  ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: done ? 'Выполнено' : 'Отметить выполненным',
            onPressed: done ? null : onDone,
            icon: Icon(
              done ? Icons.check_circle_rounded : Icons.check_circle_outline,
              color: done ? AppColors.muted : AppColors.meadow,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }
}
