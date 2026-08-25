import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/activation_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/garden_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_update.dart';
import 'services/foreground.dart';
import 'services/reminder_service.dart';
import 'services/web_push_service.dart';
import 'state/access_store.dart';
import 'state/favorites_store.dart';
import 'state/garden_store.dart';
import 'state/settings_store.dart';
import 'theme/app_theme.dart';
import 'widgets/activation_code_form.dart';
import 'widgets/app_update_dialog.dart';
import 'widgets/notification_permission_dialog.dart';

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
  final FavoritesStore _favorites = FavoritesStore();
  final AccessStore _access = AccessStore();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  static const _deviceChannel = MethodChannel('com.agronizer.greengrow/device');
  var _startupDialogsScheduled = false;
  var _updateDialogVisible = false;
  var _startupDialogRetries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    listenPageForeground(_access.recheck);
    if (!kIsWeb) {
      _deviceChannel.setMethodCallHandler((call) async {
        if (call.method == 'timeChanged') {
          _access.recheck();
          _syncReminders();
        }
      });
    }
    _store.addListener(_syncReminders);
    _settings.addListener(_syncReminders);
    _access.addListener(_syncReminders);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _store.load(),
      _settings.load(),
      _favorites.load(),
      _access.load(),
    ]);
    _showStartupDialogs();
    if (kIsWeb) {
      WebPushService.onNotifyGranted(_onWebNotifyGranted);
      if (_access.unlocked && WebPushService.permissionGranted) {
        await _onWebNotifyGranted();
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncReminders();
      if (kIsWeb && _access.unlocked && WebPushService.permissionGranted) {
        _onWebNotifyGranted();
      }
    });
  }

  void _showStartupDialogs() {
    if (_startupDialogsScheduled) return;
    _startupDialogsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupDialogs();
    });
  }

  Future<void> _runStartupDialogs() async {
    if (!mounted) return;

    if (kIsWeb) {
      await _offerWaitingPwaUpdate();
    }

    final ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      if (_startupDialogRetries >= 20) return;
      _startupDialogRetries++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runStartupDialogs();
      });
      return;
    }

    if (!_updateDialogVisible &&
        !htmlPwaUpdatePromptShown() &&
        _access.consumeUpdateOffer()) {
      _updateDialogVisible = true;
      try {
        await showAppUpdateDialog(ctx, _access);
      } finally {
        _updateDialogVisible = false;
      }
    }

    if (!mounted) return;
    if (_access.consumeStartupActivationOffer()) {
      final activationContext = _navigatorKey.currentContext;
      if (activationContext == null || !activationContext.mounted) return;
      await showActivationSheet(activationContext, _access);
    }
  }

  Future<void> _offerWaitingPwaUpdate() async {
    if (htmlPwaUpdatePromptShown()) return;
    if (_access.updateAvailable) return;
    // Let the HTML overlay claim a waiting worker first.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || htmlPwaUpdatePromptShown()) return;
    if (_access.updateAvailable) return;
    try {
      if (await hasWaitingWebAppUpdate()) {
        _access.offerUpdate();
      }
    } catch (_) {}
  }

  Future<void> _onWebNotifyGranted() async {
    if (!_access.unlocked) return;
    if (!_settings.loaded) return;
    if (!_settings.enabled) {
      await _settings.setEnabled(true);
    }
    final subscribed = await ReminderService.instance.ensurePermissions();
    if (kIsWeb && !subscribed && WebPushService.permissionGranted) {
      // Retry once — SW may not have been ready on first attempt.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await ReminderService.instance.ensurePermissions();
    }
    await _syncReminders();
  }

  Future<void> _syncReminders() async {
    if (!_store.loaded || !_settings.loaded || !_access.unlocked) return;
    await _settings.pruneDismissals(_store.plants.map((p) => p.id).toSet());
    await ReminderService.instance.sync(
      plants: _store.plants,
      reminderTime: _settings.reminderTime,
      enabled: _settings.enabled,
      dismissedKeys: _settings.dismissedReminderKeys,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _access.recheck();
      if (kIsWeb) {
        unawaited(_onWebResume());
      } else {
        // User may have granted exact-alarm / notification permission in Settings.
        _syncReminders();
      }
    }
  }

  Future<void> _onWebResume() async {
    if (WebPushService.permissionGranted) {
      await _onWebNotifyGranted();
    } else {
      await _syncReminders();
    }
    if (!mounted || !_access.loaded) return;
    if (htmlPwaUpdatePromptShown() || _updateDialogVisible) return;
    await _offerWaitingPwaUpdate();
    if (!_access.consumeUpdateOffer()) return;
    final ctx = _navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    _updateDialogVisible = true;
    try {
      await showAppUpdateDialog(ctx, _access);
    } finally {
      _updateDialogVisible = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_syncReminders);
    _settings.removeListener(_syncReminders);
    _access.removeListener(_syncReminders);
    _store.dispose();
    _settings.dispose();
    _favorites.dispose();
    _access.dispose();
    if (!kIsWeb) {
      _deviceChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_store, _settings, _favorites, _access]),
      builder: (context, _) {
        final ready = _store.loaded &&
            _settings.loaded &&
            _favorites.loaded &&
            _access.loaded;
        Widget home;
        if (!ready) {
          home = const Scaffold(
            backgroundColor: AppColors.canvas,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.meadow),
            ),
          );
        } else if (!_access.unlocked) {
          home = ActivationScreen(access: _access);
        } else {
          home = MainShell(
            store: _store,
            settings: _settings,
            favorites: _favorites,
            access: _access,
          );
        }
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Микрозелень',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
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
    required this.favorites,
    required this.access,
  });

  final GardenStore store;
  final SettingsStore settings;
  final FavoritesStore favorites;
  final AccessStore access;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _returnIndex = 0;

  void _openCatalogRememberReturn() {
    _returnIndex = _index;
    setState(() => _index = 2);
  }

  void _goToGarden() {
    if (!mounted) return;
    setState(() => _index = 1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptNotificationsIfNeeded();
    });
  }

  Future<void> _promptNotificationsIfNeeded() async {
    if (!mounted) return;
    // Web: permission UX is only on /gate/microgreens/ — do not open in-app sheets.
    if (kIsWeb) return;
    final granted =
        await NotificationPermissionDialog.maybePrompt(context);
    if (!mounted) return;
    if (granted && !widget.settings.enabled) {
      await widget.settings.setEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        store: widget.store,
        settings: widget.settings,
        access: widget.access,
        onAddPlant: _openCatalogRememberReturn,
      ),
      GardenScreen(
        store: widget.store,
        favorites: widget.favorites,
        onAddPlant: _openCatalogRememberReturn,
      ),
      CatalogScreen(
        store: widget.store,
        favorites: widget.favorites,
        onListPlantAdded: () {
          // «Выращивать» с Главной / Моей грядки — после Начать в Моя грядка.
          // Добавление из списка Базы знаний — остаёмся здесь.
          if (_returnIndex == 2) return;
          _goToGarden();
        },
        onDetailPlantAdded: _goToGarden,
      ),
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
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
            _returnIndex = value;
          });
        },
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
            label: 'Моя грядка',
          ),
          NavigationDestination(
            icon: Icon(Icons.yard_outlined),
            selectedIcon: Icon(Icons.yard_rounded),
            label: 'База знаний',
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
