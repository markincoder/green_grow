import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Контакты',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Скоро здесь появятся способы связаться',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Spacer(),
            Center(
              child: SoftPanel(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mail_outline_rounded,
                      size: 42,
                      color: AppColors.meadow,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Пока пусто',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
