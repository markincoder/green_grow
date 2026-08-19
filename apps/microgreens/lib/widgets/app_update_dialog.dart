import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update.dart';
import '../state/access_store.dart';
import '../theme/app_theme.dart';

Future<void> showAppUpdateDialog(BuildContext context, AccessStore access) {
  final auto = kIsWeb;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Доступно обновление'),
      content: Text(_message(access, auto: auto)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (auto) {
              await applyWebAppUpdate();
              return;
            }
            await launchUrl(
              access.updateApkUri,
              mode: LaunchMode.externalApplication,
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.leaf,
            foregroundColor: Colors.white,
          ),
          child: const Text('Обновить'),
        ),
      ],
    ),
  );
}

String _message(AccessStore access, {required bool auto}) {
  final remote = access.remoteVersion?.label;
  final headline = (remote != null && remote.isNotEmpty)
      ? 'Доступна версия $remote.'
      : 'Доступна новая версия приложения.';
  if (auto) {
    return '$headline Нажмите «Обновить» — приложение перезагрузится само.';
  }
  return '$headline Автоматически установить нельзя.\n\n'
      'Нажмите «Обновить», откройте скачанный файл и подтвердите установку '
      'поверх текущей версии.';
}
