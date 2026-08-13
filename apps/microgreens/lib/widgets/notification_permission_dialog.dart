import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/reminder_service.dart';
import '../services/web_push_service.dart';
import '../theme/app_theme.dart';

/// Permission prompt for native apps. On web, setup lives on /gate/microgreens/.
abstract final class NotificationPermissionDialog {
  static bool _promptShownThisSession = false;
  static bool _promptInFlight = false;

  /// Shows once per session if notifications are not allowed (native only).
  static Future<bool> maybePrompt(BuildContext context) async {
    if (kIsWeb) {
      // No in-app wizard — gate page owns first-run permission UX.
      return WebPushService.permissionGranted;
    }

    if (_promptInFlight) {
      return ReminderService.instance.areNotificationsEnabled();
    }
    if (_promptShownThisSession) {
      return ReminderService.instance.areNotificationsEnabled();
    }

    final canPrompt = ReminderService.instance.isSupportedPlatform ||
        ReminderService.instance.usesWebPush;
    if (!canPrompt) return false;

    final granted = await ReminderService.instance.areNotificationsEnabled();
    if (granted) return true;
    if (!context.mounted) return false;

    _promptShownThisSession = true;
    return prompt(context);
  }

  /// Native dialog, or redirect to /gate/microgreens/ on web.
  static Future<bool> prompt(BuildContext context) async {
    if (!context.mounted) return false;
    if (_promptInFlight) {
      return ReminderService.instance.areNotificationsEnabled();
    }
    _promptInFlight = true;
    try {
      if (kIsWeb) {
        WebPushService.showSetup();
        return false;
      }

      final allow = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Разрешить уведомления?'),
          content: const Text(
            'Агронайзер присылает напоминания о посеве, свете, поливе и сборе. '
            'Без разрешения Push не придут.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.leaf,
                foregroundColor: Colors.white,
              ),
              child: const Text('Разрешить'),
            ),
          ],
        ),
      );

      if (allow != true || !context.mounted) return false;

      final ok = await ReminderService.instance.ensurePermissions();
      if (ok) return true;
      if (!context.mounted) return false;
      return _showDeniedHelpNative(context);
    } finally {
      _promptInFlight = false;
    }
  }

  static Future<bool> _showDeniedHelpNative(BuildContext context) async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Уведомления отключены'),
        content: const Text(
          'Разрешение не выдано. Откройте настройки приложения '
          'и включите уведомления вручную.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.leaf,
              foregroundColor: Colors.white,
            ),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );

    if (openSettings == true) {
      await ReminderService.instance.openNotificationSettings();
    }
    return ReminderService.instance.areNotificationsEnabled();
  }
}
