import 'package:flutter/material.dart';

import '../state/access_store.dart';
import '../theme/app_theme.dart';
import 'activation_code_form.dart';
import 'common_widgets.dart';

class TrialAccessCard extends StatelessWidget {
  const TrialAccessCard({super.key, required this.access});

  final AccessStore access;

  @override
  Widget build(BuildContext context) {
    // Paid state always wins — never show trial text alongside activation.
    final Widget? status;
    if (access.isPaid && access.paidExpiresAt != null) {
      status = _StatusLine(
        icon: Icons.verified_rounded,
        prefix: 'Доступ активирован до ',
        date: formatRuAccessDate(access.paidExpiresAt!),
      );
    } else if (access.paidExpired && access.paidExpiresAt != null) {
      status = _StatusLine(
        icon: Icons.verified_rounded,
        prefix: 'Доступ действовал до ',
        date: formatRuAccessDate(access.paidExpiresAt!),
      );
    } else if (access.trialEndsAt != null) {
      status = _StatusLine(
        icon: Icons.eco_rounded,
        prefix: 'Пробная бесплатная версия до ',
        date: formatRuAccessDate(access.trialEndsAt!),
      );
    } else {
      status = null;
    }

    if (status == null && !access.canActivateAccess) {
      return const SizedBox.shrink();
    }

    return SoftPanel(
      color: const Color(0xFFECF8F0),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null) status,
          if (access.canActivateAccess) ...[
            if (status != null) const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => showActivationSheet(context, access),
              icon: const Icon(Icons.key_rounded, size: 18),
              label: const Text('Активировать доступ'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.prefix,
    required this.date,
  });

  final IconData icon;
  final String prefix;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.meadow, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    height: 1.35,
                  ),
              children: [
                TextSpan(text: prefix),
                TextSpan(
                  text: date,
                  style: const TextStyle(
                    color: AppColors.forest,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
