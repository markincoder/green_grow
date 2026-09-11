import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_version.dart';
import '../state/access_store.dart';
import '../theme/app_theme.dart';
import '../widgets/activation_code_form.dart';
import '../widgets/common_widgets.dart';
import '../widgets/social_brand_icon.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key, required this.access});

  final AccessStore access;

  static const _supportLinks = <_ContactLink>[
    _ContactLink(
      title: 'Почта',
      subtitle: 'agronizer@yandex.ru',
      url: 'mailto:agronizer@yandex.ru',
      materialIcon: Icons.mail_outline_rounded,
    ),
  ];

  static const _links = <_ContactLink>[
    _ContactLink(
      title: 'Телеграм',
      subtitle: 't.me/agronizer',
      url: 'https://t.me/agronizer',
      brand: SocialBrand.telegram,
    ),
    _ContactLink(
      title: 'ВКонтакте',
      subtitle: 'vk.ru/agronizer',
      url: 'https://vk.ru/agronizer',
      brand: SocialBrand.vk,
    ),
    _ContactLink(
      title: 'Max',
      subtitle: 'max.ru/channel_agronizer',
      url: 'https://max.ru/channel_agronizer',
      brand: SocialBrand.max,
    ),
    _ContactLink(
      title: 'Наш сайт',
      subtitle: 'agronizer.ru',
      url: 'https://agronizer.ru',
      materialIcon: Icons.language_rounded,
    ),
  ];

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                Text(
                  'Контакты',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                _ContactList(
                  links: _links,
                  onOpen: (url) => _open(context, url),
                ),
                const SizedBox(height: 14),
                Text(
                  'Есть вопросы/замечания/предложения?\nНапишите нам',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                _ContactList(
                  links: _supportLinks,
                  onOpen: (url) => _open(context, url),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: AnimatedBuilder(
              animation: access,
              builder: (context, _) {
                final footerStyle =
                    Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontSize: 13.5,
                        );
                return Column(
                  children: [
                    FutureBuilder<AppVersion>(
                      future: AppVersion.fromPlatform(),
                      builder: (context, snapshot) {
                        final label = snapshot.data?.label.trim() ?? '';
                        if (label.isEmpty) return const SizedBox.shrink();
                        return Text(
                          'Версия $label',
                          textAlign: TextAlign.center,
                          style: footerStyle,
                        );
                      },
                    ),
                    if (access.isPaid && access.paidExpiresAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Доступ активирован до ${formatRuAccessDate(access.paidExpiresAt!)}',
                        textAlign: TextAlign.center,
                        style: footerStyle,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactList extends StatelessWidget {
  const _ContactList({required this.links, required this.onOpen});

  final List<_ContactLink> links;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return SoftPanel(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 64,
                color: AppColors.mist.withValues(alpha: 0.9),
              ),
            _ContactTile(
              link: links[i],
              onTap: () => onOpen(links[i].url),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactLink {
  const _ContactLink({
    required this.title,
    required this.subtitle,
    required this.url,
    this.brand,
    this.materialIcon,
  }) : assert(brand != null || materialIcon != null);

  final String title;
  final String subtitle;
  final String url;
  final SocialBrand? brand;
  final IconData? materialIcon;
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.link, required this.onTap});

  final _ContactLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.mist,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: link.brand != null
              ? SocialBrandIcon(
                  brand: link.brand!,
                  size: link.brand == SocialBrand.vk ? 24 : 22,
                  color: AppColors.leaf,
                )
              : Icon(link.materialIcon, size: 22, color: AppColors.leaf),
        ),
        title: Text(
          link.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          link.subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
        ),
        trailing: Icon(
          Icons.open_in_new_rounded,
          size: 18,
          color: AppColors.muted.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
