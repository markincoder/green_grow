import 'dart:async' as async;

import 'package:flutter/material.dart';
import '../models/plant.dart';
import '../services/reminder_service.dart';
import '../state/access_store.dart';
import '../state/garden_store.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/common_widgets.dart';
import '../widgets/stage_icons.dart';
import '../widgets/trial_access_card.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.settings,
    required this.access,
    required this.onAddPlant,
  });

  final GardenStore store;
  final SettingsStore settings;
  final AccessStore access;
  final VoidCallback onAddPlant;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UndoSnackBarHost _undoSnackBar = UndoSnackBarHost();

  @override
  void dispose() {
    _undoSnackBar.dispose();
    super.dispose();
  }

  List<TodayReminderItem> get _reminders {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return ReminderService.buildTodayReminders(
      plants: widget.store.plants,
      day: day,
      dismissedKeys: widget.settings.dismissedReminderKeys,
      now: now,
    );
  }

  Future<void> _markDone(TodayReminderItem item) async {
    if (item.done) return;
    try {
      final undo = await widget.store.completeReminderAction(
        kind: item.kind,
        gardenId: item.gardenId,
      );
      await widget.settings.dismissReminder(item.key);
      if (!mounted) return;

      _undoSnackBar.show(
        context: context,
        message: item.title,
        onUndo: () async {
          await widget.settings.restoreReminder(item.key);
          if (undo != null) {
            await widget.store.undoReminderAction(undo);
          }
        },
      );
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('HomeScreen: mark reminder failed: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить напоминание.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.store,
          widget.settings,
          widget.access,
        ]),
        builder: (context, _) {
          final reminders = _reminders;
          // Paid line lives in Contacts — keep home free when activated.
          final showAccess = !widget.access.isPaid &&
              (widget.access.trialEndsAt != null ||
                  widget.access.paidExpiresAt != null ||
                  widget.access.canActivateAccess);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: [
                    const BrandLogo(maxWidth: 240),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.leaf,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          textStyle: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
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
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: AppColors.mist.withValues(alpha: 0.9),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(
                                settings: widget.settings,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                          child: Row(
                            children: [
                              Icon(
                                widget.settings.enabled
                                    ? Icons.notifications_active_rounded
                                    : Icons.notifications_off_outlined,
                                color: widget.settings.enabled
                                    ? AppColors.meadow
                                    : AppColors.muted,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Напоминания',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      widget.settings.enabled
                                          ? 'Ежедневно в ${widget.settings.reminderTimeLabel}'
                                          : 'Выключены',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.forest,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (reminders.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Планируется',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: _PlanningScroll(
                    reminders: reminders,
                    onMarkDone: (item) => async.unawaited(_markDone(item)),
                  ),
                ),
              ] else
                const Spacer(),
              if (showAccess)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: TrialAccessCard(
                    key: const ValueKey('trial-access'),
                    access: widget.access,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Scrollable reminders list with a bottom arrow when more content is below.
class _PlanningScroll extends StatefulWidget {
  const _PlanningScroll({
    required this.reminders,
    required this.onMarkDone,
  });

  final List<TodayReminderItem> reminders;
  final ValueChanged<TodayReminderItem> onMarkDone;

  @override
  State<_PlanningScroll> createState() => _PlanningScrollState();
}

class _PlanningScrollState extends State<_PlanningScroll> {
  final _controller = ScrollController();
  var _canScrollMore = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateHint);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHint());
  }

  @override
  void didUpdateWidget(covariant _PlanningScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHint());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateHint);
    _controller.dispose();
    super.dispose();
  }

  void _updateHint() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final more = position.maxScrollExtent > 8 &&
        position.pixels < position.maxScrollExtent - 8;
    if (more != _canScrollMore) {
      setState(() => _canScrollMore = more);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _updateHint();
            return false;
          },
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            itemCount: widget.reminders.length,
            itemBuilder: (context, index) {
              final item = widget.reminders[index];
              return _ReminderTile(
                item: item,
                onMarkDone: item.done ? null : () => widget.onMarkDone(item),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _canScrollMore ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Container(
                height: 36,
                alignment: Alignment.bottomCenter,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.canvas.withValues(alpha: 0),
                      AppColors.canvas.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.forest.withValues(alpha: 0.75),
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.item,
    this.onMarkDone,
  });

  final TodayReminderItem item;
  final VoidCallback? onMarkDone;

  @override
  Widget build(BuildContext context) {
    final done = item.done;
    final titleStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: done ? AppColors.muted : AppColors.ink,
          height: 1.35,
          decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
        );
    final actionStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: done ? AppColors.muted : AppColors.forest,
          height: 1.3,
          decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: StageGlyph(
              kind: reminderGlyphKind(item.kind),
              color: done ? AppColors.muted : AppColors.meadow,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: titleStyle),
                Text(item.actionLabel, style: actionStyle),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: done ? 'Выполнено' : 'Отметить выполненным',
            child: InkWell(
              onTap: onMarkDone,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _ReminderCheck(done: done),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCheck extends StatelessWidget {
  const _ReminderCheck({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.meadow : Colors.transparent,
        border: Border.all(
          color: done ? AppColors.meadow : AppColors.muted,
          width: 2,
        ),
      ),
      child: done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}
