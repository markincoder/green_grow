import 'package:flutter/material.dart';

import '../state/settings_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.settings,
    required this.onAddPlant,
  });

  final SettingsStore settings;
  final VoidCallback onAddPlant;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Доброе утро'
        : hour < 18
            ? 'Добрый день'
            : 'Добрый вечер';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Микрозелень',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: AppColors.forest,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '$greeting. Добавьте лоток или настройте напоминания.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.muted,
                  ),
            ),
            const SizedBox(height: 20),
            SoftPanel(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(settings: settings),
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
                    settings.enabled
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined,
                    color: settings.enabled
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
                          settings.enabled
                              ? 'Ежедневно в ${settings.reminderTimeLabel}'
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
            const Spacer(),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.96, end: 1),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: SizedBox(
                width: double.infinity,
                height: 64,
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
                  onPressed: onAddPlant,
                  icon: const Icon(Icons.add_rounded, size: 28),
                  label: const Text('Добавить'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Выберите культуру и укажите дату старта',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
