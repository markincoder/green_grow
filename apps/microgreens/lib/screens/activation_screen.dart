import 'package:flutter/material.dart';

import '../state/access_store.dart';
import '../theme/app_theme.dart';
import '../widgets/trial_access_card.dart';

class ActivationScreen extends StatelessWidget {
  const ActivationScreen({super.key, required this.access});

  final AccessStore access;

  @override
  Widget build(BuildContext context) {
    final title = access.paidExpired
        ? 'Срок доступа закончился'
        : 'Пробный период закончился';
    final subtitle = access.paidExpired
        ? 'Оформите новый код на сайте или активируйте уже купленный.'
        : 'Активируйте купленный код или оформите доступ на сайте.';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 32),
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 10),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 22),
                  TrialAccessCard(
                    access: access,
                    activateLabel: 'Активировать код доступа',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
