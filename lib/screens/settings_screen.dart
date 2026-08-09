import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsStore settings;

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: settings.reminderTime,
      helpText: 'Ежедневное время Push',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      await settings.setReminderTime(picked);
    }
  }

  Future<void> _onEnabledChanged(bool value) async {
    if (value) {
      await ReminderService.instance.ensurePermissions();
    }
    await settings.setEnabled(value);
  }

  Future<void> _sendTestPush(BuildContext context) async {
    final service = ReminderService.instance;
    if (!service.isSupportedPlatform) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Push работает на Android и iOS. На этом устройстве недоступен.',
          ),
        ),
      );
      return;
    }

    final ok = await service.showTestPush();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Push отправлен. Проверьте шторку уведомлений.'
              : 'Не удалось отправить Push. Разрешите уведомления в системе.',
        ),
      ),
    );
  }

  Future<void> _scheduleBackgroundTest(BuildContext context) async {
    final service = ReminderService.instance;
    if (!service.isSupportedPlatform) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Фоновый тест доступен на Android и iOS.',
          ),
        ),
      );
      return;
    }

    final result = await service.scheduleSmokeTest(
      delay: const Duration(seconds: 45),
    );
    if (!context.mounted) return;

    final String message;
    if (!result.ok) {
      message = result.error != null
          ? 'Не удалось запланировать: ${result.error}'
          : 'Не удалось запланировать. Разрешите уведомления в настройках системы.';
    } else if (!result.usedExact) {
      message = 'Запланировано на ${result.fireAtLabel}, но без точных будильников — '
          'в фоне может не сработать. Переустановите APK.';
    } else if (!result.batteryUnrestricted) {
      message = 'Запланировано на ${result.fireAtLabel}. Разрешите работу в фоне '
          '(без ограничений батареи), затем нажмите «Домой» — не свайпайте из недавних.';
    } else {
      message = 'Будильник на ${result.fireAtLabel}. Нажмите «Домой» и подождите ~45 с. '
          'Не свайпайте приложение из недавних — на части телефонов это снимает будильник.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 10)),
    );
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
              const SizedBox(height: 8),
              Text(
                'Ежедневный Push в выбранное время — проращивание, сбор и полив. '
                'Для замачивания «Пора посеять» приходит автоматически по времени '
                'замачивания из карточки культуры.\n\n'
                'Чтобы Push приходил в фоне, разрешите уведомления и работу без '
                'ограничений батареи. Для проверки нажмите «Домой», не свайпайте '
                'из недавних — на части телефонов это снимает будильники.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SoftPanel(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Включить напоминания'),
                  subtitle: const Text('Планировать системные Push'),
                  value: settings.enabled,
                  activeThumbColor: AppColors.meadow,
                  onChanged: _onEnabledChanged,
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
                            'Проращивание, рост, полив',
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
              const SizedBox(height: 12),
              SoftPanel(
                onTap: settings.enabled ? () => _sendTestPush(context) : null,
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      color: settings.enabled
                          ? AppColors.water
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Тестовый Push',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Отправить пример дайджеста сейчас',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: settings.enabled
                          ? AppColors.forest
                          : AppColors.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SoftPanel(
                onTap: settings.enabled
                    ? () => _scheduleBackgroundTest(context)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      color: settings.enabled
                          ? AppColors.water
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Проверка в фоне',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Push через 45 с — нажмите «Домой», не свайпайте',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: settings.enabled
                          ? AppColors.forest
                          : AppColors.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SoftPanel(
                color: AppColors.mist.withValues(alpha: 0.55),
                child: Text(
                  'Примеры Push\n\n'
                  'Замачивание (по времени из карточки, напр. горох 8–12 ч):\n'
                  'Горох от 8авг. Пора посеять.\n\n'
                  'Ежедневно в ${settings.reminderTimeLabel}:\n'
                  'Базилик от 1авг. Время собирать урожай!\n'
                  'Рукола от 5авг. Пора на свет.\n'
                  'Все лотки роста. Проверьте уровень воды',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
