import 'package:flutter/material.dart';

import '../state/access_store.dart';
import '../theme/app_theme.dart';
import 'activation_code_form.dart';
import 'common_widgets.dart';

class TrialAccessCard extends StatelessWidget {
  const TrialAccessCard({
    super.key,
    required this.access,
    this.activateLabel = 'Продлить доступ',
  });

  final AccessStore access;
  final String activateLabel;

  @override
  Widget build(BuildContext context) {
    // Paid state always wins — never show trial text alongside activation.
    final Widget? status;
    if (access.isPaid && access.paidExpiresAt != null) {
      status = _StatusLine(
        icon: Icons.check_circle_rounded,
        prefix: 'Доступ активирован до ',
        date: formatRuAccessDate(access.paidExpiresAt!),
      );
    } else if (access.paidExpired && access.paidExpiresAt != null) {
      status = _StatusLine(
        icon: Icons.check_circle_rounded,
        prefix: 'Доступ действовал до ',
        date: formatRuAccessDate(access.paidExpiresAt!),
      );
    } else if (access.trialEndsAt != null) {
      status = _StatusLine(
        icon: Icons.eco_rounded,
        prefix: 'Бесплатный доступ до ',
        date: formatAccessDateNumeric(access.trialEndsAt!),
      );
    } else {
      status = null;
    }

    if (status == null && !access.canActivateAccess) {
      return const SizedBox.shrink();
    }

    return SoftPanel(
      color: const Color(0xFFECF8F0),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null) status,
          if (access.canActivateAccess) ...[
            if (status != null) const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => showActivationSheet(context, access),
              icon: const Icon(Icons.key_rounded, size: 18),
              label: Text(activateLabel),
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
      children: [
        Icon(icon, color: AppColors.meadow, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.ink,
                    height: 1.3,
                  ),
              children: [
                TextSpan(text: prefix),
                TextSpan(
                  text: date,
                  style: const TextStyle(
                    color: AppColors.forest,
                    fontWeight: FontWeight.w700,
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
