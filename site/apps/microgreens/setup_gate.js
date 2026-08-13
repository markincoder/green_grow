/**
 * Pre-Flutter setup gate — visit modes:
 *   /apps/?setup=1    → full PWA wizard (browser tab / portal link ONLY):
 *                       iOS: icon → notifications
 *                       Android/Chrome: notifications → icon (Install hides site notify UI)
 *   /apps/?icon=1     → same as setup=1 (legacy)
 *   /gate/?notify=1   → notifications only (Android: browser tab)
 *   /gate/?icon=1     → redirect to /apps/?setup=1
 *   /apps/?notify=1   → iOS Home Screen PWA: notifications overlay (stay standalone)
 *   /apps/?src=icon   → Home Screen shortcut → app (skip wizard) EXCEPT iOS first-run
 *   /apps/?setup=done → after wizard → app
 *   /apps/ (any)      → open app
 *
 * iOS: Web Push works ONLY from the Home Screen icon. After «На экран Домой»,
 * the first standalone launch must show the notify step (not the Flutter app).
 * Android/Yandex shortcuts open the app — never the icon/notify wizard.
 * Wizard state lives in sessionStorage; URL is kept clean so shortcuts don't re-open setup.
 *
 * CRITICAL: never put <link rel="manifest"> on /gate/ — Chrome creates dead icons
 * when the current page is outside the service worker scope.
 */
(function () {
  'use strict';

  var GATE_DONE_KEY = 'agronizer_gate_done_v1';
  var GATE_SKIP_KEY = 'agronizer_gate_skip_push_v1';
  var ENABLE_FLAG = 'agronizer_enable_reminders';
  var INSTALL_SKIP_KEY = 'agronizer_install_skip_v2';
  var ICON_OK_KEY = 'agronizer_icon_ok_v3';
  var BROWSER_OK_KEY = 'agronizer_browser_os_ok_v1';
  var REENTER_KEY = 'agronizer_reenter_gate_v1';
  /** Session (tab) flag: icon step already passed — prevents /apps/↔/gate/ icon loop. */
  var ICON_SESSION_KEY = 'agronizer_icon_session_v1';
  /** This browser tab is running the portal full PWA wizard (setup=1). */
  var FULL_SETUP_SESSION_KEY = 'agronizer_full_setup_v1';
  /** Notify just finished — next /apps/ load should show icon step (same tab). */
  var EXPECT_ICON_SESSION_KEY = 'agronizer_expect_icon_v1';
  /** Debounce apps→gate navigation (WebAPK often re-fires and opens gate twice). */
  var GATE_NAV_TS_KEY = 'agronizer_gate_nav_ts';
  var APP_PATH = '/apps/microgreens/';
  var GATE_PATH = '/gate/microgreens/';

  function ua() {
    return navigator.userAgent || '';
  }

  function isIos() {
    var u = ua();
    if (/iPad|iPhone|iPod/.test(u)) return true;
    return navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
  }

  function isAndroid() {
    return /Android/i.test(ua());
  }

  function isYandex() {
    return /YaBrowser/i.test(ua());
  }

  function isGatePage() {
    return location.pathname.indexOf('/gate/microgreens') === 0;
  }

  /** True only when launched as installed Home Screen / WebAPK (no browser chrome). */
  function isInstalledPwa() {
    return (
      window.matchMedia('(display-mode: standalone)').matches ||
      window.matchMedia('(display-mode: fullscreen)').matches ||
      window.navigator.standalone === true
    );
  }

  /**
   * Android WebAPK / standalone install — hides some Chrome site notification
   * UI. Notifications are configured on /gate/ in a normal browser tab.
   */
  function isAndroidWebApk() {
    return isAndroid() && !isIos() && isInstalledPwa() && !isBrowserTab();
  }

  function isBrowserTab() {
    return (
      window.matchMedia('(display-mode: browser)').matches ||
      window.matchMedia('(display-mode: minimal-ui)').matches
    );
  }

  function isAppShell() {
    return (
      isInstalledPwa() ||
      window.matchMedia('(display-mode: minimal-ui)').matches
    );
  }

  function isStandalone() {
    return isInstalledPwa();
  }

  function appUrl() {
    // After wizard: load app without bouncing back to icon step.
    return APP_PATH + '?setup=done';
  }

  function gateUrl() {
    return GATE_PATH + '?_t=' + Date.now();
  }

  function appsIconUrl() {
    return APP_PATH + '?setup=1&fresh=1&_t=' + Date.now();
  }

  function gateNotifyUrl() {
    return GATE_PATH + '?notify=1&_t=' + Date.now();
  }

  function queryFlag(name) {
    try {
      var v = new URLSearchParams(location.search).get(name);
      return v === '1' || v === 'done' || v === 'icon';
    } catch (_) {
      return false;
    }
  }

  function isSetupDoneEntry() {
    try {
      return new URLSearchParams(location.search).get('setup') === 'done';
    } catch (_) {
      return false;
    }
  }

  function hasFullSetupSession() {
    try {
      return sessionStorage.getItem(FULL_SETUP_SESSION_KEY) === '1';
    } catch (_) {
      return false;
    }
  }

  function beginFullSetupSession() {
    try {
      sessionStorage.setItem(FULL_SETUP_SESSION_KEY, '1');
    } catch (_) {}
  }

  function clearSetupSessionFlags() {
    try {
      sessionStorage.removeItem(FULL_SETUP_SESSION_KEY);
      sessionStorage.removeItem(EXPECT_ICON_SESSION_KEY);
    } catch (_) {}
  }

  /** Keep URL clean so Home Screen / Yandex shortcuts never bookmark ?setup=1. */
  function cleanAppUrl() {
    try {
      if (location.pathname.indexOf(APP_PATH) === 0) {
        history.replaceState(null, '', APP_PATH);
      }
    } catch (_) {}
  }

  /** URL query starts full wizard (portal «Установить PWA»). */
  function isSetupQueryEntry() {
    try {
      var sp = new URLSearchParams(location.search);
      return sp.get('setup') === '1' || sp.get('icon') === '1';
    } catch (_) {
      return false;
    }
  }

  /** Full PWA wizard: portal link or same-tab session after that link. */
  function isIconSetupEntry() {
    if (hasFullSetupSession()) return true;
    return isSetupQueryEntry();
  }

  function isIconPhaseEntry() {
    try {
      if (sessionStorage.getItem(EXPECT_ICON_SESSION_KEY) === '1') return true;
    } catch (_) {}
    try {
      return new URLSearchParams(location.search).get('phase') === 'icon';
    } catch (_) {
      return false;
    }
  }

  function consumeExpectIconPhase() {
    try {
      var ok = sessionStorage.getItem(EXPECT_ICON_SESSION_KEY) === '1';
      sessionStorage.removeItem(EXPECT_ICON_SESSION_KEY);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /**
   * Android/Chrome: notifications BEFORE Install — WebAPK hides site notification UI.
   * iOS: icon FIRST — Web Push only works from Home Screen.
   */
  function notifyBeforeIcon() {
    return !isIos();
  }

  function appsIconPhaseUrl() {
    // Clean path — wizard continues via sessionStorage, not sticky query params.
    return APP_PATH;
  }

  function isHomeIconLaunch() {
    try {
      if (new URLSearchParams(location.search).get('src') === 'icon') return true;
    } catch (_) {}
    if (isIos() && isInstalledPwa()) return true;
    if (isAndroidWebApk()) return true;
    if (isInstalledPwa() && !isBrowserTab()) return true;
    return false;
  }

  function isNotifyOnlyEntry() {
    try {
      var sp = new URLSearchParams(location.search);
      return sp.get('notify') === '1' || sp.get('from') === 'app';
    } catch (_) {
      return false;
    }
  }

  /** iOS standalone, push not finished — first open from Home Screen icon. */
  function iosNeedsNotifyFromIcon() {
    return isIos() && isInstalledPwa() && !gateAlreadyFinished() && !notifGranted();
  }

  var deferredInstallPrompt = null;
  var swReadyForInstall = false;

  function isSamsungBrowser() {
    return /SamsungBrowser/i.test(ua());
  }

  function isFirefoxAndroid() {
    return isAndroid() && /Firefox/i.test(ua());
  }

  function isEdgeAndroid() {
    return isAndroid() && /EdgA/i.test(ua());
  }

  function isChromeAndroid() {
    return (
      isAndroid() &&
      !isIos() &&
      !isYandex() &&
      !isSamsungBrowser() &&
      !isFirefoxAndroid() &&
      !isEdgeAndroid() &&
      /Chrome|CriOS/i.test(ua())
    );
  }

  function bindChromeInstallPrompt() {
    if (window.__agronizerBipBound) return;
    window.__agronizerBipBound = true;
    window.addEventListener('beforeinstallprompt', function (e) {
      e.preventDefault();
      deferredInstallPrompt = e;
      if (step === 'icon' && root) render();
    });
    window.addEventListener('appinstalled', function () {
      deferredInstallPrompt = null;
      markIconStepDone();
      if (step === 'icon' && root) {
        if (notifyBeforeIcon()) {
          step = 'ready';
          setStatus('Chrome установил приложение. Уведомления уже настроены раньше — можно открывать.', 'ok');
          render();
        } else {
          setStatus('Chrome установил приложение. Откройте новую иконку «Микрозелень».', 'ok');
          render();
        }
      }
    });
  }

  function promptChromeInstall() {
    if (!deferredInstallPrompt) return Promise.resolve(false);
    var ev = deferredInstallPrompt;
    deferredInstallPrompt = null;
    return ev
      .prompt()
      .then(function () {
        return ev.userChoice;
      })
      .then(function (choice) {
        return choice && choice.outcome === 'accepted';
      })
      .catch(function () {
        return false;
      });
  }

  /** Ensure SW is registered under /apps/ before user taps Install — required for a working Chrome WebAPK. */
  function ensureAppServiceWorker() {
    if (isGatePage()) return Promise.resolve(false);
    bindChromeInstallPrompt();
    var p;
    try {
      if (window.AgronizerPush && typeof window.AgronizerPush.ensureServiceWorker === 'function') {
        p = window.AgronizerPush.ensureServiceWorker();
      }
    } catch (_) {}
    if (!p) {
      if (!('serviceWorker' in navigator)) return Promise.resolve(false);
      p = navigator.serviceWorker.register(APP_PATH + 'flutter_service_worker.js', {
        scope: APP_PATH,
        updateViaCache: 'none',
      });
    }
    return Promise.resolve(p)
      .then(function () {
        if (!navigator.serviceWorker.controller) {
          // First visit: SW installed but page not controlled until reload.
          return navigator.serviceWorker.ready;
        }
        return navigator.serviceWorker.ready;
      })
      .then(function () {
        swReadyForInstall = true;
        if (step === 'icon' && root) render();
        return true;
      })
      .catch(function () {
        swReadyForInstall = false;
        return false;
      });
  }

  /**
   * Chrome keeps stale site permission on this document.
   * history.back() often fails (we got here via location.replace).
   * Bounce: leave to /apps/… then auto-return to /gate/… — fresh Notification.permission.
   */
  function bounceToRefreshSitePermission() {
    try {
      sessionStorage.setItem(REENTER_KEY, '1');
    } catch (_) {}
    setStatus('Обновляем статус разрешения — сейчас выйдем и сразу вернёмся…');
    var target = APP_PATH + '?_bounce=' + Date.now();
    try {
      location.href = target;
    } catch (_) {
      location.assign(target);
    }
  }

  function notifSupported() {
    return typeof Notification !== 'undefined';
  }

  function notifGranted() {
    return notifSupported() && Notification.permission === 'granted';
  }

  function notifDenied() {
    return notifSupported() && Notification.permission === 'denied';
  }

  function iosVersion() {
    var m = ua().match(/OS (\d+)[._](\d+)/);
    if (!m) return null;
    return { major: parseInt(m[1], 10), minor: parseInt(m[2], 10) };
  }

  function iosSupportsWebPush() {
    if (!isIos()) return true;
    var v = iosVersion();
    if (!v) return true;
    return v.major > 16 || (v.major === 16 && v.minor >= 4);
  }

  function pushDeviceId() {
    var existing = localStorage.getItem('web_push_device_id');
    if (existing) return existing;
    try {
      var flutterVal = localStorage.getItem('flutter.web_push_device_id');
      if (flutterVal) {
        try {
          var parsed = JSON.parse(flutterVal);
          if (typeof parsed === 'string' && parsed) {
            localStorage.setItem('web_push_device_id', parsed);
            return parsed;
          }
        } catch (_) {
          if (flutterVal.indexOf('web-') === 0) {
            localStorage.setItem('web_push_device_id', flutterVal);
            return flutterVal;
          }
        }
      }
    } catch (_) {}
    var id =
      'web-' + Date.now() + '-' + Math.random().toString(36).slice(2, 10);
    localStorage.setItem('web_push_device_id', id);
    try {
      localStorage.setItem('flutter.web_push_device_id', JSON.stringify(id));
    } catch (_) {}
    return id;
  }

  function ensureServiceWorker() {
    if (!('serviceWorker' in navigator)) {
      return Promise.reject(new Error('no sw'));
    }
    // Register under app path. Do NOT use navigator.serviceWorker.ready —
    // it hangs on /gate/microgreens/ (outside SW scope).
    var swUrl = APP_PATH + 'flutter_service_worker.js';
    return navigator.serviceWorker
      .getRegistration(APP_PATH)
      .then(function (reg) {
        if (reg) return reg;
        return navigator.serviceWorker.register(swUrl, { scope: APP_PATH });
      })
      .then(function (reg) {
        if (reg && reg.active) return reg;
        var worker = reg && (reg.installing || reg.waiting);
        if (!worker) return reg;
        return new Promise(function (resolve, reject) {
          var t = setTimeout(function () {
            resolve(reg);
          }, 12000);
          worker.addEventListener('statechange', function () {
            if (worker.state === 'activated' || (reg && reg.active)) {
              clearTimeout(t);
              resolve(reg);
            }
          });
        });
      });
  }

  function subscribePush() {
    if (!window.AgronizerPush || typeof AgronizerPush.subscribeGrantedOnly !== 'function') {
      return Promise.resolve(false);
    }
    var id = pushDeviceId();
    return ensureServiceWorker()
      .catch(function () {
        return null;
      })
      .then(function () {
        if (Notification.permission !== 'granted') return false;
        return AgronizerPush.subscribeGrantedOnly(id);
      })
      .then(function (ok) {
        return !!ok && Notification.permission === 'granted';
      })
      .catch(function () {
        return false;
      });
  }

  /** Gate «Проверить»: fail closed if site permission is not granted. */
  function verifyPushReady() {
    if (!window.AgronizerPush || typeof AgronizerPush.verifyReady !== 'function') {
      var perm = notifSupported() ? Notification.permission : 'unsupported';
      if (perm !== 'granted') {
        return Promise.resolve({
          ok: false,
          message:
            'Нет разрешения сайту (сейчас: ' +
            perm +
            '). Включите уведомления вручную, затем «Проверить».',
        });
      }
      return subscribePush().then(function (ok) {
        return {
          ok: !!ok,
          message: ok
            ? 'Подписка OK.'
            : 'Подписка не удалась при permission=granted.',
        };
      });
    }
    var id = pushDeviceId();
    return ensureServiceWorker()
      .catch(function () {
        return null;
      })
      .then(function () {
        return AgronizerPush.verifyReady(id);
      })
      .catch(function (err) {
        return {
          ok: false,
          message: 'Ошибка проверки: ' + ((err && err.message) || 'неизвестно'),
        };
      });
  }

  function gateAlreadyFinished() {
    // Explicit user completion only — permission alone must NOT skip verify/test.
    if (localStorage.getItem(GATE_SKIP_KEY) === '1') return true;
    if (localStorage.getItem(GATE_DONE_KEY) === '1') return true;
    return false;
  }

  /** True when site permission is granted (may still need subscribe + test). */
  function pushPermissionOk() {
    return notifGranted();
  }

  function markGateDone(opts) {
    opts = opts || {};
    // When Android still needs the icon step, do not mark icon done yet.
    if (opts.markIcon !== false) {
      markIconStepDone();
    }
    localStorage.setItem(GATE_DONE_KEY, '1');
    if (opts.skipPush) {
      localStorage.setItem(GATE_SKIP_KEY, '1');
    } else {
      localStorage.removeItem(GATE_SKIP_KEY);
      localStorage.setItem(ENABLE_FLAG, '1');
      localStorage.setItem(BROWSER_OK_KEY, '1');
    }
    try {
      window.dispatchEvent(
        new CustomEvent('agronizer-notify-granted', {
          detail: { skipped: !!opts.skipPush },
        }),
      );
    } catch (_) {}
  }

  /** After notifications on Android → icon install on /apps/. */
  function continueToIconAfterNotify() {
    iconStepPassedThisPage = false;
    try {
      localStorage.removeItem(ICON_OK_KEY);
      sessionStorage.setItem(EXPECT_ICON_SESSION_KEY, '1');
      sessionStorage.setItem(FULL_SETUP_SESSION_KEY, '1');
    } catch (_) {}
    if (isGatePage() || location.pathname.indexOf(APP_PATH) !== 0) {
      location.assign(appsIconPhaseUrl());
      return;
    }
    cleanAppUrl();
    ensureAppServiceWorker();
    step = 'icon';
    render();
  }

  function afterNotifyWizardDone(opts) {
    opts = opts || {};
    // Android full PWA setup: notifications done → install icon (while still possible).
    if (isIconSetupEntry() && notifyBeforeIcon() && !isInstalledPwa()) {
      markGateDone({ skipPush: !!opts.skipPush, markIcon: false });
      continueToIconAfterNotify();
      return;
    }
    markGateDone({ skipPush: !!opts.skipPush, markIcon: true });
    clearSetupSessionFlags();
    step = 'ready';
    render();
  }

  function enterApp() {
    clearSetupSessionFlags();
    location.href = appUrl();
  }

  function loadFlutter() {
    // On /apps/ Flutter is loaded by index.html <script src="flutter_bootstrap.js">.
    // Keep this for /gate/ → redirect into the app, and as a manual fallback.
    if (isGatePage()) {
      location.href = appUrl();
      return;
    }
    if (window.__agronizerFlutterLoading) return;
    window.__agronizerFlutterLoading = true;
    if (document.querySelector('script[src*="flutter_bootstrap"]')) return;
    var gate = document.getElementById('agronizer-gate');
    if (gate) gate.remove();
    var s = document.createElement('script');
    s.src = 'flutter_bootstrap.js';
    s.async = true;
    s.onerror = function () {
      window.__agronizerFlutterLoading = false;
      document.body.insertAdjacentHTML(
        'beforeend',
        '<p style="padding:24px;font-family:system-ui">Не удалось загрузить приложение. Обновите страницу.</p>',
      );
    };
    document.body.appendChild(s);
  }

  /** Home Screen /app open: Flutter already boots from index.html. */
  function openAppFromHomeIcon() {
    window.__agronizerFlutterLoading = true;
    clearSetupSessionFlags();
    try {
      localStorage.setItem(ICON_OK_KEY, '1');
    } catch (_) {}
    cleanAppUrl();
    if (notifGranted() && localStorage.getItem(GATE_SKIP_KEY) !== '1') {
      try {
        subscribePush().catch(function () {});
      } catch (_) {}
    }
  }

  // —— UI ——
  var root = null;
  var step = 'icon'; // icon | notify | confirm | ready
  var lastTechOkMessage = '';
  var refreshPermOnReturn = false;
  /** How many times user tapped «Повторить тест» on confirm — gate browser-level help. */
  var confirmTestAttempts = 0;
  /** In-memory only: after «Далее» on icon → notify on the same page (no navigation). */
  var iconStepPassedThisPage = false;

  function markIconStepDone() {
    iconStepPassedThisPage = true;
    try {
      localStorage.setItem(ICON_OK_KEY, '1');
      localStorage.removeItem(INSTALL_SKIP_KEY);
      localStorage.removeItem('agronizer_install_skip_v1');
      sessionStorage.removeItem(ICON_SESSION_KEY);
      sessionStorage.removeItem(INSTALL_SKIP_KEY);
      sessionStorage.removeItem('agronizer_icon_session_v1');
    } catch (_) {}
  }

  function iconMarkedOk() {
    try {
      return localStorage.getItem(ICON_OK_KEY) === '1';
    } catch (_) {
      return false;
    }
  }

  function fromAppReentry() {
    return isNotifyOnlyEntry();
  }

  function launchedFromHomeIcon() {
    return isHomeIconLaunch();
  }

  /**
   * Show icon step for website visits.
   * Cookies/localStorage/sessionStorage do NOT skip.
   * Only in-memory flag after «Далее» on this page, or notify/home/setup entry.
   */
  function needsIconStep() {
    if (isHomeIconLaunch()) return false;
    if (isSetupDoneEntry()) return false;
    if (isNotifyOnlyEntry()) return false;
    if (iconStepPassedThisPage) return false;
    return true;
  }

  /** Android notify: /gate/?notify=1 (skips icon via fromAppReentry). */
  function goToGateForNotify() {
    try {
      var prev = parseInt(localStorage.getItem(GATE_NAV_TS_KEY) || '0', 10);
      if (prev && Date.now() - prev < 10000) {
        if (gateAlreadyFinished()) {
          loadFlutter();
          return;
        }
        ensureDom();
        step = 'notify';
        render();
        bindVisibilityRefresh();
        bindPermissionWatcher();
        return;
      }
      localStorage.setItem(GATE_NAV_TS_KEY, String(Date.now()));
    } catch (_) {}
    location.replace(gateNotifyUrl());
  }

  function openMicrogreensInBrowser() {
    var url = location.origin + APP_PATH;
    if (isAndroid()) {
      var hostPath = location.host + APP_PATH;
      var intent =
        'intent://' +
        hostPath +
        '#Intent;scheme=https;package=com.android.chrome;' +
        'S.browser_fallback_url=' +
        encodeURIComponent(url) +
        ';end';
      if (launchAndroidIntent(intent)) return true;
    }
    try {
      window.open(url, '_blank');
      return true;
    } catch (_) {}
    try {
      location.href = url;
      return true;
    } catch (_) {}
    return false;
  }

  function browserAppLabel() {
    if (isYandex()) return 'Яндекс';
    if (/SamsungBrowser/i.test(ua())) return 'Интернет Samsung';
    if (/Firefox/i.test(ua())) return 'Firefox';
    return 'Chrome';
  }

  function browserAppsHelpText() {
    return (
      'Системные настройки → Приложения → «' +
      browserAppLabel() +
      '» → Уведомления → разрешить'
    );
  }

  /** Prefer system Apps list — Chrome-specific intents often blocked in Custom Tabs. */
  function openSystemAppsSettings() {
    if (!isAndroid()) return false;
    var intents = [
      'intent:#Intent;action=android.settings.APPLICATION_SETTINGS;end',
      'intent:#Intent;action=android.settings.MANAGE_APPLICATIONS_SETTINGS;end',
      'intent:#Intent;action=android.settings.SETTINGS;end',
    ];
    for (var i = 0; i < intents.length; i++) {
      if (launchAndroidIntent(intents[i])) return true;
    }
    return false;
  }

  function launchAndroidIntent(url) {
    if (!url || !isAndroid()) return false;
    try {
      var a = document.createElement('a');
      a.href = url;
      a.style.display = 'none';
      document.body.appendChild(a);
      a.click();
      setTimeout(function () {
        try {
          a.remove();
        } catch (_) {}
      }, 0);
      return true;
    } catch (_) {}
    try {
      window.location.href = url;
      return true;
    } catch (_) {}
    try {
      window.location.assign(url);
      return true;
    } catch (_) {}
    return false;
  }

  function sitePermLabel() {
    if (!notifSupported()) return 'недоступны в этом браузере';
    var p = Notification.permission;
    if (p === 'granted') return 'разрешены';
    if (p === 'denied') return 'запрещены';
    return 'ещё не выбраны';
  }

  /** Android: no address-bar lock — use browser menu → site settings → notifications. */
  function androidSiteNotifyStepsHtml() {
    return (
      '<li>Меню браузера <b>⋮</b> / <b>≡</b> → <b>Настройки</b> или <b>Сведения о сайте</b> / <b>Настройки сайта</b></li>' +
      '<li><b>Уведомления</b> (или Разрешения → Уведомления) → <b>Разрешить</b> для <b>agronizer.ru</b></li>' +
      '<li>Останьтесь на этой странице и нажмите кнопку ниже ещё раз — «возвращаться» никуда не нужно</li>' +
      '<li>Настройки самого приложения «' +
      browserAppLabel() +
      '» в Android — только если сайт уже разрешён, а тест всё равно пустой</li>'
    );
  }

  function iosSiteNotifyStepsHtml() {
    return (
      '<li>На iOS Push работает только из иконки на «Домой» — вы уже в этом режиме</li>' +
      '<li>Нажмите «Разрешить уведомления сайту» и в окне выберите <b>Разрешить</b></li>' +
      '<li>Если сайт запрещён: Настройки iPhone → <b>Микрозелень</b> → Уведомления → разрешить</li>'
    );
  }

  function siteNotifyDeniedLead() {
    if (isIos()) {
      return 'Сайту запрещены уведомления. На iOS проверьте иконку на «Домой» и настройки уведомлений приложения.';
    }
    return 'Сайту agronizer.ru запрещены уведомления. Включите их в настройках сайта браузера (меню ⋮), не в настройках Android → Приложения.';
  }

  function siteNotifyDeniedStatus() {
    if (isIos()) {
      return 'iOS: иконка на «Домой» + уведомления для Микрозелень / Safari.';
    }
    return 'Android: ⋮ → Настройки / Сведения о сайте → Уведомления → Разрешить. Замка в адресной строке нет.';
  }

  /** Chrome caches Notification.permission until a real navigation (reload is often not enough). */
  function reloadToRefreshPermission() {
    try {
      var url = location.href.split('#')[0];
      url = url.replace(/([?&])_perm=\d+/g, function (_, sep) {
        return sep === '?' ? '?' : '';
      });
      url = url.replace(/\?&/, '?').replace(/[?&]$/, '');
      var sep = url.indexOf('?') >= 0 ? '&' : '?';
      location.replace(url + sep + '_perm=' + Date.now());
    } catch (_) {
      try {
        location.reload();
      } catch (__) {
        location.href = location.href;
      }
    }
  }

  function bindPermissionWatcher() {
    if (window.__agronizerGatePermBound) return;
    window.__agronizerGatePermBound = true;
    if (!navigator.permissions || typeof navigator.permissions.query !== 'function') {
      return;
    }
    navigator.permissions
      .query({ name: 'notifications' })
      .then(function (status) {
        var last = status.state;
        status.onchange = function () {
          if (status.state === last) return;
          last = status.state;
          // Only reload on notify/confirm — a reload on the icon step re-shows it twice.
          if (step !== 'notify' && step !== 'confirm') {
            if (root) render();
            return;
          }
          // Site settings changed — force fresh document so Notification.permission updates.
          reloadToRefreshPermission();
        };
      })
      .catch(function () {});
  }

  function bindVisibilityRefresh() {
    if (window.__agronizerGateVisBound) return;
    window.__agronizerGateVisBound = true;
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState !== 'visible' || !root) return;
      if (refreshPermOnReturn && (step === 'notify' || step === 'confirm')) {
        refreshPermOnReturn = false;
        reloadToRefreshPermission();
        return;
      }
      render();
    });
    window.addEventListener('focus', function () {
      if (!root) return;
      if (refreshPermOnReturn && (step === 'notify' || step === 'confirm')) {
        refreshPermOnReturn = false;
        reloadToRefreshPermission();
        return;
      }
      render();
    });
    window.addEventListener('pageshow', function (ev) {
      if (!root || step !== 'notify') return;
      if (ev.persisted) reloadToRefreshPermission();
    });
  }

  function el(id) {
    return root.querySelector('[data-id="' + id + '"]');
  }

  function setStatus(text, kind) {
    var s = el('status');
    if (!s) return;
    s.className = 'ag-gate-status' + (kind ? ' ag-' + kind : '');
    if (!text) {
      s.hidden = true;
      s.textContent = '';
      return;
    }
    s.hidden = false;
    s.textContent = text;
  }

  /** Keep the HTML overlay above Flutter canvas and block Flutter taps. */
  function keepGateOnTop() {
    if (!root || !document.body) return;
    try {
      if (document.body.lastElementChild !== root) {
        document.body.appendChild(root);
      }
    } catch (_) {}
    try {
      root.style.zIndex = '2147483000';
    } catch (_) {}
  }

  function bindGateOnTopObserver() {
    if (window.__agronizerGateTopBound) return;
    window.__agronizerGateTopBound = true;
    keepGateOnTop();
    window.addEventListener('agronizer-flutter-ready', keepGateOnTop);
    [50, 300, 1000, 2500].forEach(function (ms) {
      setTimeout(keepGateOnTop, ms);
    });
  }

  /**
   * Show notify wizard on this page (iOS Home Screen PWA).
   * Do not navigate to /gate/ — that leaves standalone and requestPermission fails.
   */
  function showNotifyOverlay(opts) {
    opts = opts || {};
    try {
      window.__agronizerFlutterLoading = true;
      if (opts.resetDone) {
        try {
          localStorage.removeItem(GATE_DONE_KEY);
          localStorage.removeItem(GATE_SKIP_KEY);
        } catch (_) {}
      }
      ensureDom();
      bindGateOnTopObserver();
      step = 'notify';
      render();
      bindVisibilityRefresh();
      bindPermissionWatcher();
      maybeAutoVerifyNotify();
    } catch (err) {
      console.error('AgronizerGate.showNotifyOverlay failed', err);
      if (!isGatePage()) openAppFromHomeIcon();
    }
  }

  /** Icon setup must run on /apps/ (SW scope). Never install from /gate/. */
  function goToAppsForIcon() {
    if (!isGatePage() && isIconSetupEntry()) {
      ensureDom();
      step = 'icon';
      render();
      bindVisibilityRefresh();
      bindPermissionWatcher();
      return;
    }
    location.replace(appsIconUrl());
  }

  function render() {
    if (!root) return;
    keepGateOnTop();
    var title = el('title');
    var lead = el('lead');
    var steps = el('steps');
    var btnPrimary = el('primary');
    var btnSecondary = el('secondary');
    var btnSkip = el('skip');
    var btnEnter = el('enter');

    btnPrimary.hidden = true;
    btnSecondary.hidden = true;
    btnSkip.hidden = true;
    btnEnter.hidden = true;

    if (step === 'icon') {
      title.textContent = notifyBeforeIcon()
        ? '2. Установка иконки (после уведомлений)'
        : '1. Установка PWA: иконка на «Домой»';
      if (isIos()) {
        lead.textContent =
          'Рекомендуемый способ на iPhone: сначала иконка на «Домой», затем уведомления. Без иконки Push на iOS не работает.';
        steps.innerHTML =
          '<li>В Safari нажмите <b>Поделиться</b> (□↑) внизу экрана</li>' +
          '<li>Пролистайте меню и выберите <b>«На экран „Домой“»</b></li>' +
          '<li>Нажмите <b>«Добавить»</b> — имя «Микрозелень»</li>' +
          '<li>Закройте эту вкладку и откройте Микрозелень <b>с новой иконки</b></li>' +
          '<li>Настройка уведомлений откроется <b>уже в приложении с иконки</b></li>';
        btnPrimary.hidden = !isInstalledPwa();
        if (isInstalledPwa()) {
          btnPrimary.textContent = 'Далее — к уведомлениям';
        }
        btnSecondary.hidden = true;
        btnSkip.hidden = true;
        setStatus(
          'Эта вкладка Safari больше не нужна. Откройте иконку на «Домой» — там появятся уведомления.',
          'bad',
        );
      } else if (isYandex()) {
        lead.textContent =
          'В Яндекс.Браузере добавьте ярлык на рабочий стол. После этого открывайте Микрозелень с ярлыка — настройка больше не понадобится.';
        steps.innerHTML =
          '<li>Нажмите <b>≡</b> (меню) внизу или справа</li>' +
          '<li><b>«Добавить на рабочий стол»</b> / <b>«Добавить ярлык»</b> / <b>«Установить»</b></li>' +
          '<li>Имя — <b>«Микрозелень»</b></li>' +
          '<li>Откройте с ярлыка — сразу приложение (без повторной настройки)</li>' +
          '<li>Или нажмите «Далее» здесь, если ярлык уже есть</li>';
        btnPrimary.hidden = false;
        btnPrimary.textContent = notifyBeforeIcon() ? 'Далее — готово' : 'Далее — к уведомлениям';
        btnSecondary.hidden = true;
        btnSkip.hidden = false;
        btnSkip.textContent = 'Пропустить — ярлык уже есть';
        setStatus('Яндекс: ярлык должен открывать приложение, а не мастер установки.', 'ok');
      } else if (isAndroidWebApk()) {
        title.textContent = 'PWA уже установлено';
        lead.textContent =
          'Иконка на экране есть. Дальше можно проверить уведомления во вкладке браузера.';
        steps.innerHTML =
          '<li>Нажмите «К уведомлениям» — проверка Push</li>' +
          '<li>Или сразу откройте приложение</li>';
        btnPrimary.hidden = false;
        btnPrimary.textContent = 'К уведомлениям';
        btnSecondary.hidden = false;
        btnSecondary.textContent = 'Открыть приложение';
        btnSkip.hidden = true;
        setStatus('Иконка есть — осталось проверить уведомления.', 'ok');
      } else if (isChromeAndroid()) {
        lead.textContent = notifyBeforeIcon()
          ? 'Уведомления сайта уже настроены во вкладке. Теперь можно установить приложение — после Install пункты уведомлений сайта в Chrome пропадут.'
          : 'Один мастер: сначала установка в Chrome, затем уведомления. Нужен Install, не обычный ярлык.';
        steps.innerHTML = notifyBeforeIcon()
          ? '<li>Дождитесь статуса: Service Worker готов</li>' +
            '<li>Нажмите <b>«Установить в Chrome»</b> (или ⋮ → Установить приложение)</li>' +
            '<li>Откройте <b>новую</b> иконку</li>' +
            '<li>«Далее» — завершение настройки</li>'
          : '<li>Если раньше ставили — Настройки Android → Приложения → <b>«Микрозелень»</b> → Удалить</li>' +
            '<li>Дождитесь статуса: Service Worker готов</li>' +
            '<li>Нажмите <b>«Установить в Chrome»</b> (или ⋮ → Установить приложение)</li>' +
            '<li>Откройте <b>новую</b> иконку, вернитесь сюда</li>' +
            '<li>«Далее» — настройка уведомлений и тест</li>';
        btnPrimary.hidden = false;
        btnPrimary.textContent = deferredInstallPrompt
          ? 'Установить в Chrome'
          : notifyBeforeIcon()
            ? 'Далее — готово'
            : 'Далее — к уведомлениям';
        btnSecondary.hidden = !deferredInstallPrompt;
        btnSecondary.textContent = notifyBeforeIcon()
          ? 'Пропустить — иконка уже есть'
          : 'Далее — иконка уже есть';
        btnSkip.hidden = false;
        btnSkip.textContent = 'Скачать APK вместо PWA';
        if (!swReadyForInstall) {
          setStatus('Готовим Service Worker для Chrome… подождите 2–3 сек.', 'ok');
        } else if (deferredInstallPrompt) {
          setStatus(
            notifyBeforeIcon()
              ? 'Уведомления готовы. Теперь установите PWA.'
              : 'Chrome готов установить PWA. Нажмите «Установить в Chrome».',
            'ok',
          );
        } else {
          setStatus(
            'SW готов. Если кнопки установки нет: ⋮ → «Установить приложение».',
            'ok',
          );
        }
      } else if (isSamsungBrowser()) {
        lead.textContent =
          'Интернет Samsung: добавьте страницу на экран «Домой», затем уведомления.';
        steps.innerHTML =
          '<li>Меню <b>☰</b> / <b>⋮</b> → <b>«Добавить страницу на»</b> / <b>«На главный экран»</b></li>' +
          '<li>Или <b>«Установить приложение»</b>, если пункт есть</li>' +
          '<li>Имя — <b>«Микрозелень»</b></li>' +
          '<li>«Далее» — уведомления и тест</li>';
        btnPrimary.hidden = false;
        btnPrimary.textContent = notifyBeforeIcon() ? 'Далее — готово' : 'Далее — к уведомлениям';
        btnSecondary.hidden = true;
        btnSkip.hidden = false;
        btnSkip.textContent = 'Пропустить — иконка уже есть';
        setStatus('Samsung: ярлык с этой страницы /apps/microgreens/.', 'ok');
      } else if (isFirefoxAndroid()) {
        lead.textContent =
          'Firefox: ярлык на экран «Домой», затем уведомления.';
        steps.innerHTML =
          '<li>Меню <b>⋮</b> → <b>«Установить»</b> или <b>«Добавить на главный экран»</b></li>' +
          '<li>Имя — <b>«Микрозелень»</b></li>' +
          '<li>«Далее» — уведомления и тест</li>';
        btnPrimary.hidden = false;
        btnPrimary.textContent = notifyBeforeIcon() ? 'Далее — готово' : 'Далее — к уведомлениям';
        btnSecondary.hidden = true;
        btnSkip.hidden = false;
        btnSkip.textContent = 'Пропустить — иконка уже есть';
        setStatus('Firefox: установка с этой же страницы приложения.', 'ok');
      } else if (isEdgeAndroid()) {
        lead.textContent =
          'Microsoft Edge: установите приложение / ярлык, затем уведомления.';
        steps.innerHTML =
          '<li>Меню <b>⋯</b> → <b>«Добавить на телефон»</b> / <b>«Установить приложение»</b></li>' +
          '<li>Имя — <b>«Микрозелень»</b></li>' +
          '<li>«Далее» — уведомления и тест</li>';
        btnPrimary.hidden = false;
        btnPrimary.textContent = notifyBeforeIcon() ? 'Далее — готово' : 'Далее — к уведомлениям';
        btnSecondary.hidden = true;
        btnSkip.hidden = false;
        btnSkip.textContent = 'Пропустить — иконка уже есть';
        setStatus('Edge: ставьте со страницы /apps/microgreens/.', 'ok');
      } else {
        lead.textContent =
          'Сначала иконка или ярлык на экран «Домой» (меню браузера), затем уведомления.';
        steps.innerHTML =
          '<li>Откройте меню браузера (⋮ / ≡ / ⋯)</li>' +
          '<li>Пункт вроде <b>«Установить»</b>, <b>«На главный экран»</b>, <b>«Добавить ярлык»</b></li>' +
          '<li>Имя — <b>«Микрозелень»</b>, страница должна быть /apps/microgreens/</li>' +
          '<li>«Далее» — уведомления и тест</li>';
        btnPrimary.hidden = false;
        btnPrimary.textContent = notifyBeforeIcon() ? 'Далее — готово' : 'Далее — к уведомлениям';
        btnSecondary.hidden = true;
        btnSkip.hidden = false;
        btnSkip.textContent = 'Пропустить — иконка уже есть';
        setStatus('Одна ссылка PWA — шаги подстраиваются под ваш браузер.', 'ok');
      }
      return;
    }

    if (step === 'notify') {
      title.textContent = notifyBeforeIcon()
        ? '1. Уведомления сайта agronizer.ru'
        : '2. Уведомления сайта agronizer.ru';
      lead.textContent = notifyBeforeIcon()
        ? 'В Chrome сначала уведомления сайта, и только потом установка — иначе пункты уведомлений сайта пропадут.'
        : 'Сначала разрешение именно сайту (не браузеру в целом). Сейчас для agronizer.ru: ' +
          sitePermLabel() +
          '.';
      if (notifyBeforeIcon()) {
        lead.textContent +=
          ' Сейчас для agronizer.ru: ' + sitePermLabel() + '.';
      }

      if (notifGranted()) {
        refreshPermOnReturn = false;
        steps.innerHTML =
          '<li>Сайту уже <b>разрешено</b> — это главный шаг</li>' +
          '<li>Нажмите «Проверить» — подписка и тест-баннер на экране</li>' +
          '<li>Настройки приложения браузера в Android — только если тест пустой при разрешённом сайте</li>';
        btnPrimary.hidden = true;
        btnSecondary.hidden = false;
        btnSecondary.textContent = 'Проверить сайт и отправить тест';
        btnEnter.hidden = true;
        setStatus('Шаг 1 OK: сайту разрешено. Проверяем подписку и тест.', 'ok');
      } else if (notifDenied()) {
        refreshPermOnReturn = true;
        lead.textContent = siteNotifyDeniedLead();
        steps.innerHTML = isIos()
          ? iosSiteNotifyStepsHtml()
          : androidSiteNotifyStepsHtml();
        btnPrimary.hidden = true;
        btnSecondary.hidden = true;
        btnEnter.hidden = true;
        setStatus(siteNotifyDeniedStatus(), 'bad');
      } else {
        refreshPermOnReturn = false;
        if (isIos()) {
          steps.innerHTML =
            '<li>Нажмите «Разрешить уведомления сайту»</li>' +
            '<li>В окне выберите <b>Разрешить</b></li>' +
            '<li>Если окна нет или отказали: Настройки iPhone → Микрозелень → Уведомления</li>';
        } else {
          steps.innerHTML =
            '<li>Нажмите «Разрешить уведомления сайту»</li>' +
            '<li>В окне выберите <b>Разрешить</b> — это про agronizer.ru</li>' +
            '<li>Если окна нет: меню <b>⋮</b> → <b>Настройки</b> / <b>Сведения о сайте</b> → <b>Уведомления</b> → Разрешить</li>' +
            '<li>Сразу нажмите кнопку ещё раз на этой же странице</li>';
        }
        btnPrimary.hidden = false;
        btnPrimary.textContent = 'Разрешить уведомления сайту';
        btnSecondary.hidden = true;
        btnEnter.hidden = true;
        setStatus(
          isIos()
            ? 'Вы в приложении с иконки — нажмите «Разрешить уведомления сайту».'
            : 'Android: ⋮ → настройки сайта → Уведомления (замка нет).',
        );
      }

      btnSkip.hidden = false;
      btnSkip.textContent = 'Пропустить — без Push';
      return;
    }

    if (step === 'confirm') {
      title.textContent = '2. Тест уведомлений сайта';
      var siteOk = notifGranted();
      if (siteOk) {
        lead.textContent =
          'Сайту разрешено. Смотрите баннер «Микрозелень — проверка». Если пусто — повторите тест сайта.';
      } else if (isIos()) {
        lead.textContent =
          'Сайт ещё не разрешён. На iOS: иконка на «Домой» и Настройки → Микрозелень → Уведомления.';
      } else {
        lead.textContent =
          'Сайт ещё не разрешён. Меню ⋮ → Настройки / Сведения о сайте → Уведомления → Разрешить, затем «Повторить тест сайта» здесь же.';
      }
      var stepsHtml =
        '<li>Статус сайта: <b>' +
        sitePermLabel() +
        '</b></li>' +
        '<li>Увидели баннер → «Вижу баннер — готово»</li>' +
        '<li>Не увидели → «Повторить тест сайта»</li>';
      if (!siteOk) {
        stepsHtml += isIos()
          ? '<li><b>Сайт не разрешён</b> — иконка на «Домой» + Настройки iPhone → Микрозелень → Уведомления</li>'
          : '<li><b>Сайт не разрешён</b> — ⋮ → Настройки / Сведения о сайте → Уведомления → Разрешить, затем снова тест на этой странице</li>';
      } else if (confirmTestAttempts >= 2) {
        stepsHtml +=
          '<li>Сайт разрешён, тест 2+ раза пустой → тогда: Настройки Android → Приложения → «' +
          browserAppLabel() +
          '» → Уведомления</li>';
      } else {
        stepsHtml +=
          '<li>Пока не открывайте Настройки → Приложения → браузер — сначала повторите тест сайта</li>';
      }
      steps.innerHTML = stepsHtml;
      btnPrimary.hidden = false;
      btnPrimary.textContent = 'Повторить тест сайта';
      btnSecondary.hidden = !(isAndroid() && !isIos() && siteOk && confirmTestAttempts >= 2);
      btnSecondary.textContent =
        'Сайт OK, баннера нет — настройки «' + browserAppLabel() + '»';
      btnEnter.hidden = false;
      btnEnter.textContent = 'Вижу баннер — готово';
      btnSkip.hidden = false;
      btnSkip.textContent = 'Пропустить — без Push';
      if (!siteOk) {
        setStatus(
          isIos()
            ? 'iOS: сначала разрешение с иконки / в Настройках.'
            : 'Android: ⋮ → настройки сайта → Уведомления → Разрешить.',
          'bad',
        );
      } else if (confirmTestAttempts >= 2) {
        setStatus(
          'Сайт разрешён, баннера нет после повторов — можно проверить «' +
            browserAppLabel() +
            '».',
          'bad',
        );
      } else {
        setStatus('Повторите тест сайта. Настройки браузера — только после 2 неудач.', 'ok');
      }
      return;
    }
    // ready
    title.textContent = 'Готово';
    if (notifGranted()) {
      lead.textContent =
        'Уведомления настроены: разрешение есть, подписка и тест пройдены.';
      if (isIos()) {
        steps.innerHTML = isInstalledPwa()
          ? '<li>Иконка на «Домой» есть — уведомления могут работать</li>' +
            '<li>Уведомления включены и проверены</li>'
          : '<li>Открывайте приложение <b>только с иконки на «Домой»</b></li>' +
            '<li>Уведомления включены; без иконки на iOS они не дойдут</li>';
      } else if (isInstalledPwa()) {
        steps.innerHTML =
          '<li>Приложение установлено (иконка на экране)</li>' +
          '<li>Push включён — напоминания могут приходить в фоне</li>';
      } else {
        steps.innerHTML =
          '<li>Push во вкладке настроен и проверен тестом</li>' +
          '<li>Если иконки ещё нет — вернитесь по ссылке «Установить PWA» на портале</li>';
      }
      setStatus('PWA-настройка завершена. Можно открыть приложение.', 'ok');
    } else {
      lead.textContent =
        'Push пропущен. Напоминания в фоне работать не будут, пока не разрешите уведомления.';
      steps.innerHTML = isIos()
        ? '<li>На iOS сначала нужна иконка на «Домой»</li>' +
          '<li>Затем снова откройте установку PWA</li>'
        : '<li>Позже можно снова открыть «Установить PWA» на портале</li>';
      setStatus('Push отключён по вашему выбору.', 'bad');
    }
    btnEnter.hidden = false;
    btnEnter.textContent = 'Открыть приложение';
    btnSecondary.hidden = true;
  }

  function goNotify() {
    markIconStepDone();
    try {
      localStorage.removeItem('agronizer_install_skip_v1');
      localStorage.removeItem(GATE_NAV_TS_KEY);
      localStorage.removeItem(GATE_DONE_KEY);
      localStorage.removeItem(GATE_SKIP_KEY);
    } catch (_) {}

    // Notify-only from app settings (not full setup): Android → /gate/ (browser tab).
    if (!isIos() && !isGatePage() && !isIconSetupEntry() && !isIconPhaseEntry()) {
      location.replace(gateNotifyUrl());
      return;
    }
    // Full setup on /apps/: stay here so Chrome site settings stay available before Install.
    if (isGatePage()) {
      try {
        history.replaceState(
          null,
          '',
          '/gate/microgreens/?notify=1' +
            (isIconSetupEntry() ? '&setup=1' : '') +
            '&_t=' +
            Date.now(),
        );
      } catch (_) {}
    }
    step = 'notify';
    render();
    maybeAutoVerifyNotify();
  }

  var checkInFlight = false;

  /** If permission already granted on notify page — run subscribe + test immediately. */
  function maybeAutoVerifyNotify() {
    if (step !== 'notify' || !notifGranted() || checkInFlight) return;
    checkInFlight = true;
    setStatus('Разрешение есть — проверяем подписку и отправляем тест на экран…', 'ok');
    runVerifyAfterGrant().finally(function () {
      checkInFlight = false;
      var b = el('secondary');
      if (b) b.disabled = false;
      var p = el('primary');
      if (p) p.disabled = false;
    });
  }

  /** Keep status after render() so error text is not wiped. */
  var pendingStatus = null;
  var pendingStatusKind = null;

  function renderWithStatus(text, kind) {
    pendingStatus = text || null;
    pendingStatusKind = kind || null;
    render();
    if (pendingStatus) {
      setStatus(pendingStatus, pendingStatusKind);
      pendingStatus = null;
      pendingStatusKind = null;
    }
  }

  /** Call only from a click handler — must stay in the same sync turn as the tap. */
  function requestSitePermission() {
    if (!notifSupported()) return Promise.resolve('unsupported');
    if (Notification.permission === 'granted') return Promise.resolve('granted');
    if (Notification.permission === 'denied') return Promise.resolve('denied');
    var pending;
    try {
      // Prefer promise API; keep call synchronous with the tap.
      pending = Notification.requestPermission();
    } catch (_) {
      return Promise.resolve(Notification.permission || 'denied');
    }
    // Legacy callback-only browsers
    if (typeof pending === 'undefined') {
      return new Promise(function (resolve) {
        try {
          Notification.requestPermission(function (result) {
            resolve(result || Notification.permission || 'denied');
          });
        } catch (_) {
          resolve(Notification.permission || 'denied');
        }
      });
    }
    return Promise.resolve(pending).then(function (result) {
      return result || Notification.permission || 'denied';
    });
  }

  function finishNotifyOk(message) {
    setStatus(message || 'Подписка OK.', 'ok');
    afterNotifyWizardDone({ skipPush: false });
  }

  function fireTestNotification() {
    if (!window.AgronizerPush || typeof AgronizerPush.showTestNotification !== 'function') {
      return Promise.reject(new Error('showTestNotification недоступен'));
    }
    return AgronizerPush.showTestNotification();
  }

  function enterConfirmStep(techMessage) {
    lastTechOkMessage = techMessage || '';
    confirmTestAttempts = 0;
    step = 'confirm';
    render();
    return fireTestNotification()
      .then(function () {
        setStatus(
          'Тест сайта отправлен. Не увидели — «Повторить тест сайта». Настройки браузера — только после 2 неудачных повторов.',
        );
        return true;
      })
      .catch(function (err) {
        setStatus(
          'Тест сайта не отправился: ' +
            ((err && err.message) || 'неизвестно') +
            '. Проверьте: меню ⋮ → настройки сайта → Уведомления = Разрешить, затем «Повторить тест сайта».',
          'bad',
        );
        return false;
      });
  }

  function runVerifyAfterGrant() {
    return verifyPushReady().then(function (result) {
      if (result && result.ok) {
        return enterConfirmStep(result.message);
      }
      setStatus(
        (result && result.message) ||
          'Разрешение есть, но подписка не зарегистрировалась. Нажмите «Проверить подписку».',
        'bad',
      );
      render();
      return false;
    });
  }

  function onPrimary() {
    if (step === 'icon') {
      if (isChromeAndroid() && deferredInstallPrompt) {
        var btn = el('primary');
        if (btn) btn.disabled = true;
        setStatus('Открываем окно установки Chrome…');
        promptChromeInstall().then(function (ok) {
          if (btn) btn.disabled = false;
          if (ok) {
            markIconStepDone();
            clearSetupSessionFlags();
            if (notifyBeforeIcon()) {
              step = 'ready';
              setStatus(
                'Установлено. Уведомления уже настроены — откройте новую иконку или кнопку ниже.',
                'ok',
              );
            } else {
              setStatus(
                'Установлено. Откройте новую иконку «Микрозелень», затем «Далее» к уведомлениям.',
                'ok',
              );
            }
            render();
          } else {
            setStatus(
              'Установка отменена. Можно снова нажать «Установить» или ⋮ → Установить приложение.',
              'bad',
            );
            render();
          }
        });
        return;
      }
      // Android: notifications were first — icon step finishes the wizard.
      if (notifyBeforeIcon() && (isIconPhaseEntry() || gateAlreadyFinished() || hasFullSetupSession())) {
        markIconStepDone();
        clearSetupSessionFlags();
        step = 'ready';
        render();
        return;
      }
      // Installed WebAPK but user opened full setup — site notify UI is gone; use browser tab.
      if (isAndroidWebApk() && isIconSetupEntry() && notifyBeforeIcon()) {
        location.assign(GATE_PATH + '?notify=1&setup=1&_t=' + Date.now());
        return;
      }
      if (isAndroidWebApk()) {
        goNotify();
        return;
      }
      if (isIos() && !isInstalledPwa()) {
        setStatus(
          'На iOS откройте Микрозелень с иконки на «Домой», затем нажмите «Далее». Без этого уведомления не работают.',
          'bad',
        );
        return;
      }
      // iOS (and icon-first): next = notifications
      goNotify();
      return;
    }
    if (step === 'confirm') {
      // Primary = «Повторить тест сайта»
      if (checkInFlight) return;
      checkInFlight = true;
      confirmTestAttempts += 1;
      var retryBtn = el('primary');
      if (retryBtn) retryBtn.disabled = true;
      setStatus('Снова отправляем тест сайта…');
      fireTestNotification()
        .then(function () {
          if (confirmTestAttempts >= 2 && notifGranted()) {
            setStatus(
              'Тест сайта отправлен снова (попытка ' +
                confirmTestAttempts +
                '). Если баннера нет при разрешённом сайте — тогда настройки «' +
                browserAppLabel() +
                '».',
              'bad',
            );
          } else {
            setStatus(
              'Тест сайта отправлен снова. Увидели → «Вижу баннер». Нет → ещё раз «Повторить тест сайта».',
            );
          }
          render();
        })
        .catch(function (err) {
          setStatus(
            'Тест сайта не отправился: ' +
              ((err && err.message) || 'неизвестно') +
              '. Сначала ⋮ → настройки сайта → Уведомления → Разрешить.',
            'bad',
          );
          render();
        })
        .finally(function () {
          checkInFlight = false;
          var b = el('primary');
          if (b) b.disabled = false;
        });
      return;
    }
    if (step !== 'notify') return;
    if (checkInFlight) return;

    if (!notifSupported()) {
      setStatus('Этот браузер не поддерживает уведомления.', 'bad');
      return;
    }
    if (isIos() && !isStandalone()) {
      setStatus('Сначала откройте Микрозелень с иконки на «Домой».', 'bad');
      return;
    }
    if (notifDenied()) {
      renderWithStatus(
        isIos()
          ? 'Сайт запрещён. На iOS: иконка на «Домой» и Настройки → Микрозелень → Уведомления.'
          : 'Сайт запрещён. ⋮ → Настройки / Сведения о сайте → Уведомления → Разрешить, затем снова кнопка на этой странице.',
        'bad',
      );
      return;
    }
    if (notifGranted()) {
      checkInFlight = true;
      var btnGranted = el('primary');
      if (btnGranted) btnGranted.disabled = true;
      runVerifyAfterGrant().finally(function () {
        checkInFlight = false;
        var b = el('primary');
        if (b) b.disabled = false;
      });
      return;
    }

    // CRITICAL: requestPermission in the same synchronous turn as the tap.
    checkInFlight = true;
    var btn = el('primary');
    if (btn) btn.disabled = true;
    setStatus('Ждём ответ системного окна…');
    requestSitePermission()
      .then(function (perm) {
        if (perm === 'granted') {
          return runVerifyAfterGrant();
        }
        if (perm === 'denied') {
          renderWithStatus(
            isIos()
              ? 'Сайт запретил уведомления. iOS: Настройки → Микрозелень → Уведомления.'
              : 'Сайт запретил уведомления. ⋮ → Настройки / Сведения о сайте → Уведомления → Разрешить. Настройки браузера в Android пока не трогайте.',
            'bad',
          );
          return;
        }
        // default / dismissed / quiet UI — Chrome may show nothing
        renderWithStatus(
          isIos()
            ? 'Окно не появилось. Откройте с иконки на «Домой» и нажмите кнопку ещё раз.'
            : 'Окно не появилось. Нажмите кнопку ещё раз. Если тихо: ⋮ → настройки сайта → Уведомления → Разрешить.',
          'bad',
        );
      })
      .catch(function (err) {
        renderWithStatus(
          'Не удалось показать запрос: ' + ((err && err.message) || 'неизвестно'),
          'bad',
        );
      })
      .finally(function () {
        checkInFlight = false;
        var b = el('primary');
        if (b) b.disabled = false;
      });
  }

  function onSecondary() {
    if (step === 'ready') {
      location.assign(appsIconUrl());
      return;
    }
    if (step === 'icon') {
      if (isAndroidWebApk() && !(notifyBeforeIcon() && isIconPhaseEntry())) {
        openAppFromHomeIcon();
        return;
      }
      if (notifyBeforeIcon() && (isIconPhaseEntry() || gateAlreadyFinished() || hasFullSetupSession())) {
        markIconStepDone();
        clearSetupSessionFlags();
        step = 'ready';
        render();
        return;
      }
      goNotify();
      return;
    }
    if (step === 'confirm') {
      // Secondary = browser app notifications — only after site OK + retries.
      if (!notifGranted()) {
        setStatus(
          isIos()
            ? 'Сначала разрешите уведомления сайту (иконка / Настройки iPhone), потом тест.'
            : 'Сначала ⋮ → настройки сайта → Уведомления → Разрешить, потом тест. Настройки браузера пока не нужны.',
          'bad',
        );
        return;
      }
      if (confirmTestAttempts < 2) {
        setStatus(
          'Сначала 2 раза нажмите «Повторить тест сайта». К настройкам «' +
            browserAppLabel() +
            '» перейдём только если баннера всё ещё нет.',
          'ok',
        );
        return;
      }
      if (openSystemAppsSettings()) {
        setStatus(
          'Сайт уже разрешён. Открыли «Приложения»: найдите «' +
            browserAppLabel() +
            '» → Уведомления → включить. Затем снова «Повторить тест сайта» на этой странице.',
          'ok',
        );
      } else {
        setStatus(
          'Сайт разрешён. Вручную: ' + browserAppsHelpText() + '.',
          'bad',
        );
      }
      return;
    }
    if (step === 'notify') {
      if (notifGranted()) {
        if (checkInFlight) return;
        checkInFlight = true;
        var checkBtn = el('secondary');
        if (checkBtn) checkBtn.disabled = true;
        setStatus('Проверяем… Статус сайту: granted');
        verifyPushReady()
          .then(function (result) {
            if (result && result.ok) {
              return enterConfirmStep(result.message);
            }
            renderWithStatus(
              (result && result.message) ||
                'Проверка не пройдена. Смотрите статус разрешения выше.',
              'bad',
            );
          })
          .catch(function (err) {
            renderWithStatus(
              'Ошибка проверки: ' + ((err && err.message) || 'неизвестно'),
              'bad',
            );
          })
          .finally(function () {
            checkInFlight = false;
            var b = el('secondary');
            if (b) b.disabled = false;
          });
        return;
      }
      renderWithStatus(
        isIos()
          ? 'Статус сайта ещё не обновился. Настройки iPhone → Микрозелень → Уведомления, затем снова «Проверить» здесь.'
          : 'Статус сайта ещё не обновился. ⋮ → Настройки / Сведения о сайте → Уведомления → Разрешить, затем снова «Проверить» на этой странице.',
        'bad',
      );
    }
  }

  function onSkip() {
    if (step === 'icon') {
      if (isChromeAndroid()) {
        location.href = APP_PATH + 'microgreens.apk';
        return;
      }
      // Android notify-first: icon already exists / skip → finish, do not re-open notify.
      if (notifyBeforeIcon() && (gateAlreadyFinished() || hasFullSetupSession())) {
        markIconStepDone();
        clearSetupSessionFlags();
        step = 'ready';
        render();
        return;
      }
      if (isAndroidWebApk()) {
        location.replace(gateNotifyUrl());
        return;
      }
      if (isIos() && !isInstalledPwa()) {
        setStatus(
          'На iOS без открытия с иконки «Домой» уведомления не работают. Создайте иконку по шагам, откройте с неё, затем «Далее».',
          'bad',
        );
        return;
      }
      goNotify();
      return;
    }
    if (step === 'notify' || step === 'confirm') {
      var ok = window.confirm(
        'Без разрешения Push-напоминания работать не будут.\n\nПропустить настройку уведомлений?',
      );
      if (!ok) return;
      afterNotifyWizardDone({ skipPush: true });
      return;
    }
  }

  function onEnter() {
    if (step === 'confirm') {
      finishNotifyOk(
        (lastTechOkMessage ? lastTechOkMessage + ' ' : '') +
          'Пользователь подтвердил, что тестовый баннер виден.',
      );
      return;
    }
    if (notifGranted()) {
      subscribePush().finally(function () {
        markGateDone({ skipPush: false });
        enterApp();
      });
      return;
    }
    markGateDone({ skipPush: true });
    enterApp();
  }

  function ensureDom() {
    if (root) return root;
    root = document.createElement('div');
    root.id = 'agronizer-gate';
    root.innerHTML =
      '<div class="ag-gate-card">' +
      '  <h1 data-id="title">Настройка</h1>' +
      '  <p class="ag-gate-lead" data-id="lead"></p>' +
      '  <ol class="ag-gate-steps" data-id="steps"></ol>' +
      '  <p class="ag-gate-status" data-id="status" hidden></p>' +
      '  <div class="ag-gate-actions">' +
      '    <button type="button" class="ag-gate-primary" data-id="primary" hidden></button>' +
      '    <button type="button" class="ag-gate-secondary" data-id="secondary" hidden></button>' +
      '    <button type="button" class="ag-gate-enter" data-id="enter" hidden></button>' +
      '    <button type="button" class="ag-gate-skip" data-id="skip" hidden></button>' +
      '  </div>' +
      '</div>';

    var style = document.createElement('style');
    style.textContent =
      'html,body{margin:0;min-height:100%;background:#E8F5EE}' +
      '#agronizer-gate{position:fixed;inset:0;z-index:2147483000;min-height:100vh;display:flex;align-items:flex-start;justify-content:center;' +
      'padding:24px 16px 40px;box-sizing:border-box;font-family:system-ui,-apple-system,sans-serif;background:#E8F5EE;overflow:auto}' +
      '#agronizer-gate .ag-gate-card{width:100%;max-width:440px;background:#F3FAF5;color:#1A2E24;' +
      'border-radius:20px;padding:24px 20px 20px;box-shadow:0 12px 32px rgba(27,67,50,.18)}' +
      '#agronizer-gate h1{margin:0 0 10px;font-size:1.35rem;color:#1B4332}' +
      '#agronizer-gate .ag-gate-lead{margin:0 0 14px;font-size:.98rem;line-height:1.45;color:#5C7268}' +
      '#agronizer-gate .ag-gate-steps{margin:0 0 16px;padding-left:1.2rem;font-size:.94rem;line-height:1.45}' +
      '#agronizer-gate .ag-gate-steps li{margin:0 0 8px}' +
      '#agronizer-gate .ag-gate-status{margin:0 0 14px;padding:10px 12px;border-radius:12px;' +
      'font-size:.9rem;line-height:1.4;background:rgba(45,106,79,.1);color:#2D6A4F}' +
      '#agronizer-gate .ag-gate-status.ag-bad{background:rgba(155,34,38,.1);color:#9B2226}' +
      '#agronizer-gate .ag-gate-status.ag-ok{background:rgba(64,145,108,.18);color:#1B4332}' +
      '#agronizer-gate .ag-gate-actions{display:flex;flex-direction:column;gap:8px}' +
      '#agronizer-gate button{font:600 15px/1.2 system-ui,sans-serif;border:none;border-radius:14px;' +
      'padding:14px;cursor:pointer;width:100%}' +
      '#agronizer-gate .ag-gate-primary,#agronizer-gate .ag-gate-enter{background:#1B4332;color:#fff}' +
      '#agronizer-gate .ag-gate-secondary{background:#2D6A4F;color:#fff}' +
      '#agronizer-gate .ag-gate-skip{background:transparent;color:#5C7268;font-weight:500}' +
      '#agronizer-gate button:disabled{opacity:.55;cursor:wait}' +
      '#agronizer-gate [hidden]{display:none!important}';
    document.head.appendChild(style);
    document.body.appendChild(root);

    el('primary').onclick = onPrimary;
    el('secondary').onclick = onSecondary;
    el('skip').onclick = onSkip;
    el('enter').onclick = onEnter;
    bindGateOnTopObserver();
    keepGateOnTop();
    return root;
  }

  function start() {
    try {
      startInner();
    } catch (err) {
      console.error('AgronizerGate.start failed', err);
      try {
        if (!isGatePage()) openAppFromHomeIcon();
      } catch (_) {}
    }
  }

  function startInner() {
    try {
      localStorage.removeItem(INSTALL_SKIP_KEY);
      localStorage.removeItem('agronizer_install_skip_v1');
      sessionStorage.removeItem(ICON_SESSION_KEY);
      sessionStorage.removeItem('agronizer_icon_session_v1');
      sessionStorage.removeItem(INSTALL_SKIP_KEY);
    } catch (_) {}

    // —— /apps/* : Flutter boots from index.html; gate overlays when needed ——
    if (!isGatePage()) {
      ensureAppServiceWorker();

      // Home Screen / shortcut / WebAPK: open the app — except iOS first-run notify.
      if (isHomeIconLaunch() || isInstalledPwa()) {
        // Settings → «Уведомления сайта»: stay in the PWA and show notify overlay.
        if (isIos() && isNotifyOnlyEntry()) {
          showNotifyOverlay({ resetDone: true });
          return;
        }
        // First open from Home Screen icon: continue to notifications (Web Push only here).
        if (iosNeedsNotifyFromIcon()) {
          showNotifyOverlay({ resetDone: false });
          return;
        }
        openAppFromHomeIcon();
        return;
      }

      // Stale ?phase=icon from an old Yandex/Chrome shortcut → app (not icon step).
      // Icon step only if this tab just finished notifications (session flag).
      if (notifyBeforeIcon() && isIconPhaseEntry()) {
        var expectIcon = consumeExpectIconPhase();
        if (!expectIcon && !hasFullSetupSession()) {
          openAppFromHomeIcon();
          return;
        }
        beginFullSetupSession();
        try {
          sessionStorage.setItem(EXPECT_ICON_SESSION_KEY, '1');
        } catch (_) {}
        cleanAppUrl();
        window.__agronizerFlutterLoading = true;
        ensureDom();
        step = 'icon';
        render();
        bindVisibilityRefresh();
        bindPermissionWatcher();
        return;
      }

      // Notify-only from app settings → /gate/ in a normal browser tab.
      if (isNotifyOnlyEntry() && !isSetupQueryEntry() && !hasFullSetupSession()) {
        if (isIos()) {
          try {
            localStorage.removeItem(GATE_DONE_KEY);
            localStorage.removeItem(GATE_SKIP_KEY);
          } catch (_) {}
          ensureDom();
          step = 'notify';
          render();
          bindVisibilityRefresh();
          bindPermissionWatcher();
          maybeAutoVerifyNotify();
          return;
        }
        location.replace(gateNotifyUrl());
        return;
      }

      // Full PWA setup ONLY from portal web link (?setup=1 / ?icon=1), not from icon.
      if (isSetupQueryEntry()) {
        var freshSetup = false;
        try {
          freshSetup = new URLSearchParams(location.search).get('fresh') === '1';
        } catch (_) {}
        // Old Yandex shortcuts often saved ?setup=1 — don't re-run wizard after success.
        if (
          !freshSetup &&
          !hasFullSetupSession() &&
          (gateAlreadyFinished() || iconMarkedOk())
        ) {
          openAppFromHomeIcon();
          return;
        }
        beginFullSetupSession();
        cleanAppUrl();
        window.__agronizerFlutterLoading = true;
        ensureDom();
        try {
          localStorage.removeItem(GATE_DONE_KEY);
          localStorage.removeItem(GATE_SKIP_KEY);
        } catch (_) {}
        // iOS: icon first. Android/Chrome: notifications first (Install hides site UI).
        step = notifyBeforeIcon() ? 'notify' : 'icon';
        render();
        bindVisibilityRefresh();
        bindPermissionWatcher();
        if (step === 'notify') maybeAutoVerifyNotify();
        return;
      }

      // Same-tab wizard continuation after clean URL (session only).
      if (hasFullSetupSession()) {
        window.__agronizerFlutterLoading = true;
        ensureDom();
        step = notifyBeforeIcon() ? 'notify' : 'icon';
        render();
        bindVisibilityRefresh();
        bindPermissionWatcher();
        if (step === 'notify') maybeAutoVerifyNotify();
        return;
      }

      // Stale ?setup=1 shortcuts are handled above; any other visit → app.
      openAppFromHomeIcon();
      return;
    }

    // —— /gate/* : notify (no Install here) ——
    try {
      localStorage.removeItem(GATE_NAV_TS_KEY);
    } catch (_) {}

    // From Home Screen / installed app: iOS must stay in the PWA for Web Push.
    if (isHomeIconLaunch() || isInstalledPwa()) {
      if (isIos()) {
        location.replace(APP_PATH + '?from=app&notify=1&_t=' + Date.now());
        return;
      }
      enterApp();
      return;
    }

    // Gate + setup without notify → apps (iOS icon or Android notify-first on apps).
    if (isSetupQueryEntry() && !isNotifyOnlyEntry()) {
      beginFullSetupSession();
      location.replace(appsIconUrl());
      return;
    }

    if (isIos() && !isNotifyOnlyEntry()) {
      if (isSetupQueryEntry() || hasFullSetupSession()) {
        beginFullSetupSession();
        location.replace(appsIconUrl());
        return;
      }
      location.replace(APP_PATH);
      return;
    }

    if (gateAlreadyFinished() && !isNotifyOnlyEntry() && !isIconSetupEntry()) {
      enterApp();
      return;
    }

    if (isNotifyOnlyEntry() || isIconSetupEntry() || iconStepPassedThisPage) {
      try {
        localStorage.removeItem(GATE_DONE_KEY);
        localStorage.removeItem(GATE_SKIP_KEY);
      } catch (_) {}
      ensureDom();
      step = 'notify';
      render();
      bindVisibilityRefresh();
      bindPermissionWatcher();
      maybeAutoVerifyNotify();
      return;
    }

    location.replace(APP_PATH);
  }
  window.AgronizerGate = {
    start: start,
    loadFlutter: loadFlutter,
    enterApp: enterApp,
    isDone: gateAlreadyFinished,
    isGatePage: isGatePage,
    showNotify: function () {
      showNotifyOverlay({ resetDone: true });
    },
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
