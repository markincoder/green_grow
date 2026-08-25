import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  static const _supportLinks = <_ContactLink>[
    _ContactLink(
      title: 'Почта',
      subtitle: 'agronizer@yandex.ru',
      url: 'mailto:agronizer@yandex.ru',
      icon: Icons.mail_outline_rounded,
    ),
  ];

  static const _links = <_ContactLink>[
    _ContactLink(
      title: 'Телеграм',
      subtitle: 't.me/agronizer',
      url: 'https://t.me/agronizer',
      icon: Icons.send_rounded,
    ),
    _ContactLink(
      title: 'Max',
      subtitle: 'max.ru/channel_agronizer',
      url: 'https://max.ru/channel_agronizer',
      icon: Icons.chat_bubble_outline_rounded,
    ),
    _ContactLink(
      title: 'ВКонтакте',
      subtitle: 'vk.com/agronizer',
      url: 'https://vk.com/agronizer',
      icon: Icons.groups_rounded,
    ),
    _ContactLink(
      title: 'Наш сайт',
      subtitle: 'agronizer.ru',
      url: 'https://agronizer.ru',
      icon: Icons.language_rounded,
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Text(
                  'Контакты',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                _ContactList(
                  links: _links,
                  onOpen: (url) => _open(context, url),
                ),
                const SizedBox(height: 22),
                Text(
                  'Есть вопросы? Напишите нам',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _ContactList(
                  links: _supportLinks,
                  onOpen: (url) => _open(context, url),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                if (info == null) return const SizedBox.shrink();
                return Text(
                  'Версия ${info.version}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 72,
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
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String url;
  final IconData icon;
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.link, required this.onTap});

  final _ContactLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.mist,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(link.icon, color: AppColors.leaf),
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
    );
  }
}
