import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import '../services/web_push_service.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/notification_permission_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsStore settings;

  Future<void> _pickTime(BuildContext context) async {
    var hour = settings.reminderTime.hour;
    var minute = settings.reminderTime.minute;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ежедневное время Push',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  kIsWeb
                      ? 'Выберите час и минуту'
                      : 'Прокрутите часы и минуты',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (kIsWeb)
                  _WebTimePicker(
                    hour: hour,
                    minute: minute,
                    onChanged: (h, m) {
                      hour = h;
                      minute = m;
                    },
                  )
                else
                  SizedBox(
                    height: 180,
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        textTheme: CupertinoTextThemeData(
                          dateTimePickerTextStyle: TextStyle(
                            fontSize: 22,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        use24hFormat: true,
                        initialDateTime: DateTime(2026, 1, 1, hour, minute),
                        onDateTimeChanged: (value) {
                          hour = value.hour;
                          minute = value.minute;
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.leaf,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await settings.setReminderTime(TimeOfDay(hour: hour, minute: minute));
    }
  }

  Future<void> _onEnabledChanged(BuildContext context, bool value) async {
    if (value) {
      final already =
          await ReminderService.instance.areNotificationsEnabled();
      if (!already) {
        if (!context.mounted) return;
        final granted = await NotificationPermissionDialog.prompt(context);
        if (!granted) return;
      } else {
        await ReminderService.instance.ensurePermissions();
      }
    } else if (kIsWeb) {
      await WebPushService.unsubscribe();
    }
    await settings.setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Настройки')),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                'Напоминания',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 12),
                SoftPanel(
                  onTap: () => WebPushService.showSetup(),
                  child: Row(
                    children: [
                      Icon(
                        WebPushService.permissionGranted
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_outlined,
                        color: AppColors.meadow,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Уведомления сайта',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              WebPushService.permissionGranted
                                  ? 'Разрешены · нажмите, чтобы проверить снова'
                                  : 'Настроить разрешение в браузере',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.open_in_new_rounded,
                        color: AppColors.forest,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SoftPanel(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Включить напоминания'),
                  subtitle: const Text('Планировать системные Push'),
                  value: settings.enabled,
                  activeThumbColor: AppColors.meadow,
                  onChanged: (v) => _onEnabledChanged(context, v),
                ),
              ),
              const SizedBox(height: 12),
              SoftPanel(
                onTap: settings.enabled ? () => _pickTime(context) : null,
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded, color: AppColors.meadow),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ежедневное время Push',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Рост и полив',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      settings.reminderTimeLabel,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: settings.enabled
                                ? AppColors.forest
                                : AppColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// CupertinoDatePicker wheels often paint blank on Flutter web / Safari.
/// Plain ListView + stepper controls stay visible.
class _WebTimePicker extends StatefulWidget {
  const _WebTimePicker({
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  @override
  State<_WebTimePicker> createState() => _WebTimePickerState();
}

class _WebTimePickerState extends State<_WebTimePicker> {
  static const _extent = 48.0;

  late int _hour;
  late int _minute;
  late final ScrollController _hourCtrl;
  late final ScrollController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    _hour = widget.hour;
    _minute = widget.minute;
    _hourCtrl = ScrollController(initialScrollOffset: _hour * _extent);
    _minuteCtrl = ScrollController(initialScrollOffset: _minute * _extent);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _set({int? hour, int? minute}) {
    setState(() {
      if (hour != null) _hour = (hour + 24) % 24;
      if (minute != null) _minute = (minute + 60) % 60;
    });
    widget.onChanged(_hour, _minute);
    _ensureVisible(_hourCtrl, _hour);
    _ensureVisible(_minuteCtrl, _minute);
  }

  void _ensureVisible(ScrollController controller, int index) {
    if (!controller.hasClients) return;
    final target = index * _extent;
    controller.animateTo(
      target.clamp(0, controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.forest,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 248,
          child: Row(
            children: [
              Expanded(
                child: _column(
                  label: 'Часы',
                  controller: _hourCtrl,
                  count: 24,
                  selected: _hour,
                  onSelect: (v) => _set(hour: v),
                  onStep: (d) => _set(hour: _hour + d),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _column(
                  label: 'Минуты',
                  controller: _minuteCtrl,
                  count: 60,
                  selected: _minute,
                  onSelect: (v) => _set(minute: v),
                  onStep: (d) => _set(minute: _minute + d),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _column({
    required String label,
    required ScrollController controller,
    required int count,
    required int selected,
    required ValueChanged<int> onSelect,
    required ValueChanged<int> onStep,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: () => onStep(-1),
              icon: const Icon(Icons.remove_rounded),
            ),
            IconButton.filledTonal(
              onPressed: () => onStep(1),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListView.builder(
              controller: controller,
              itemExtent: _extent,
              itemCount: count,
              itemBuilder: (context, i) {
                final isSelected = i == selected;
                return Material(
                  color: isSelected ? AppColors.mist : Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: Center(
                      child: Text(
                        i.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: isSelected ? 24 : 18,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.forest : AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
