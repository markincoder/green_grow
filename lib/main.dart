import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/catalog_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/garden_screen.dart';
import 'screens/home_screen.dart';
import 'services/reminder_service.dart';
import 'state/garden_store.dart';
import 'state/settings_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  // Init plugin only — runtime permissions need an Activity (after runApp).
  await ReminderService.instance.init();
  runApp(const GreenGrowApp());
}

class GreenGrowApp extends StatefulWidget {
  const GreenGrowApp({super.key});

  @override
  State<GreenGrowApp> createState() => _GreenGrowAppState();
}

class _GreenGrowAppState extends State<GreenGrowApp>
    with WidgetsBindingObserver {
  final GardenStore _store = GardenStore();
  final SettingsStore _settings = SettingsStore();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_syncReminders);
    _settings.addListener(_syncReminders);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_store.load(), _settings.load()]);
    // Activity is attached after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareAndSync();
    });
  }

  Future<void> _prepareAndSync() async {
    if (_settings.enabled) {
      await ReminderService.instance.ensurePermissions();
    }
    await _syncReminders();
  }

  Future<void> _syncReminders() async {
    if (!_store.loaded || !_settings.loaded) return;
    await ReminderService.instance.sync(
      plants: _store.plants,
      reminderTime: _settings.reminderTime,
      enabled: _settings.enabled,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User may have granted exact-alarm / notification permission in Settings.
      _prepareAndSync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_syncReminders);
    _settings.removeListener(_syncReminders);
    _store.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_store, _settings]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Микрозелень',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: _store.loaded && _settings.loaded
              ? MainShell(store: _store, settings: _settings)
              : const Scaffold(
                  backgroundColor: AppColors.canvas,
                  body: Center(
                    child: CircularProgressIndicator(color: AppColors.meadow),
                  ),
                ),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.store,
    required this.settings,
  });

  final GardenStore store;
  final SettingsStore settings;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        settings: widget.settings,
        onAddPlant: () => setState(() => _index = 1),
      ),
      CatalogScreen(store: widget.store),
      GardenScreen(store: widget.store),
      const ContactsScreen(),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: pages[_index],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.mist,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Главная',
          ),
          NavigationDestination(
            icon: Icon(Icons.eco_outlined),
            selectedIcon: Icon(Icons.eco_rounded),
            label: 'Справочник',
          ),
          NavigationDestination(
            icon: Icon(Icons.yard_outlined),
            selectedIcon: Icon(Icons.yard_rounded),
            label: 'Моя зелень',
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline_rounded),
            selectedIcon: Icon(Icons.mail_rounded),
            label: 'Контакты',
          ),
        ],
      ),
    );
  }
}
