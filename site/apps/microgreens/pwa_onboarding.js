/**
 * PWA setup wizard — clear separate steps:
 * 1) Icon on Home Screen (required on iOS, recommended on Android)
 * 2) Browser OS notifications (Android) — skip if site already granted
 * 3) Site permission for agronizer.ru — skip if granted
 * Continue last.
 */
(function () {
  'use strict';

  var DISMISS_KEY = 'agronizer_setup_dismissed_v3';
  var DONE_KEY = 'agronizer_setup_done_v1';
  var ENABLE_FLAG = 'agronizer_enable_reminders';
  var BROWSER_OK_KEY = 'agronizer_browser_os_ok_v1';
  // Yandex rarely fires beforeinstallprompt; standalone display-mode is unreliable.
  // Skip install step only after user taps «Далее» (or we saw a real native install).
  var INSTALL_SKIP_KEY = 'agronizer_install_skip_v1';

  var deferredPrompt = null;
  var root = null;
  var stepIds = [];
  var stepIndex = 0;
  var checkAgainAt = 0;

  function ua() {
    return navigator.userAgent || '';
  }

  function isStandalone() {
    return (
      window.matchMedia('(display-mode: standalone)').matches ||
      window.matchMedia('(display-mode: fullscreen)').matches ||
      window.navigator.standalone === true
    );
  }

  /** True when Chrome hides address bar (installed WebAPK / app shell). */
  function isAppShell() {
    try {
      if (window.matchMedia('(display-mode: standalone)').matches) return true;
      if (window.matchMedia('(display-mode: fullscreen)').matches) return true;
      if (window.matchMedia('(display-mode: minimal-ui)').matches) return true;
    } catch (_) {}
    if (window.navigator.standalone === true) return true;
    return false;
  }

  function browserSetupUrl() {
    var u = new URL(window.location.href);
    u.searchParams.set('browser', '1');
    return u.toString();
  }

  /**
   * Break out of WebAPK into a Chrome Custom Tab / tab (has URL bar).
   * Inside an installed Chrome app there is NO way to show the address bar.
   */
  function openInBrowserTab() {
    var url = browserSetupUrl();
    setStatus('Открываем вкладку Chrome с адресной строкой…', 'ok');
    var opened = null;
    try {
      opened = window.open(url, '_blank', 'noopener,noreferrer');
    } catch (_) {}
    if (!opened) {
      try {
        var a = document.createElement('a');
        a.href = url;
        a.target = '_blank';
        a.rel = 'noopener noreferrer';
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
      } catch (_) {}
    }
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText('https://agronizer.ru/apps/microgreens/');
      }
    } catch (_) {}
    setTimeout(function () {
      setStatus(
        'Если вкладка не появилась: откройте Chrome → вставьте скопированный адрес agronizer.ru/apps/microgreens/ (не открывайте с иконки).',
        'ok',
      );
    }, 600);
  }

  /** Whether to show the Home Screen icon step. */
  function needsInstallStep() {
    if (localStorage.getItem(INSTALL_SKIP_KEY) === '1') return false;
    // Yandex: do NOT trust display-mode alone — it often looks "standalone" in a tab,
    // and beforeinstallprompt usually never fires. Offer until user skips.
    if (isYandex()) return true;
    return !isStandalone();
  }

  function markInstallSkipped() {
    localStorage.setItem(INSTALL_SKIP_KEY, '1');
  }

  function isIos() {
    var u = ua();
    if (/iPad|iPhone|iPod/.test(u)) return true;
    return navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
  }

  function isYandex() {
    return /YaBrowser/i.test(ua());
  }

  function isAndroid() {
    return /Android/i.test(ua());
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

  function browserAppLabel() {
    var u = ua();
    if (/YaBrowser/i.test(u)) return 'Яндекс.Браузер';
    if (/SamsungBrowser/i.test(u)) return 'Samsung Internet';
    if (/Firefox\//i.test(u)) return 'Firefox';
    if (/EdgA\//i.test(u)) return 'Edge';
    if (/OPR\//i.test(u) || /Opera/i.test(u)) return 'Opera';
    if (/Brave/i.test(u)) return 'Brave';
    if (/HuaweiBrowser|HBPC\//i.test(u)) return 'Huawei Browser';
    if (/MiuiBrowser/i.test(u)) return 'Mi Browser';
    return 'Chrome';
  }

  function browserPackage() {
    var u = ua();
    if (/YaBrowser/i.test(u)) return 'com.yandex.browser';
    if (/SamsungBrowser/i.test(u)) return 'com.sec.android.app.sbrowser';
    if (/Firefox\//i.test(u)) return 'org.mozilla.firefox';
    if (/EdgA\//i.test(u)) return 'com.microsoft.emmx';
    if (/OPR\//i.test(u) || /Opera/i.test(u)) return 'com.opera.browser';
    if (/Brave/i.test(u)) return 'com.brave.browser';
    if (/HuaweiBrowser|HBPC\//i.test(u)) return 'com.huawei.browser';
    if (/MiuiBrowser/i.test(u)) return 'com.mi.globalbrowser';
    if (/Chromium/i.test(u) && !/Chrome\//i.test(u)) return 'org.chromium.chrome';
    return 'com.android.chrome';
  }

  function androidAppsListIntent() {
    return 'intent:#Intent;action=android.settings.APPLICATION_SETTINGS;end';
  }

  /** Chrome app notification settings — works from WebAPK better than chrome:// intents. */
  function chromeAppNotificationSettingsIntent() {
    if (!isAndroid()) return null;
    return (
      'intent:#Intent;action=android.settings.APP_NOTIFICATION_SETTINGS;' +
      'S.android.provider.extra.APP_PACKAGE=com.android.chrome;end'
    );
  }

  function chromeAppDetailsIntent() {
    if (!isAndroid()) return null;
    return (
      'intent:#Intent;action=android.settings.APPLICATION_DETAILS_SETTINGS;' +
      'data=package:com.android.chrome;end'
    );
  }

  function launchAndroidIntent(url) {
    if (!url) return false;
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

  // Legacy names used below — map to intents that actually work from fullscreen PWA.
  function siteNotificationSettingsIntent() {
    return chromeAppNotificationSettingsIntent();
  }

  function openInChromeBrowserIntent() {
    return chromeAppDetailsIntent();
  }

  function ensureServiceWorker() {
    if (!('serviceWorker' in navigator)) {
      return Promise.reject(new Error('no sw'));
    }
    return navigator.serviceWorker
      .getRegistration()
      .then(function (reg) {
        if (reg) return reg;
        return navigator.serviceWorker.register('flutter_service_worker.js', {
          scope: './',
        });
      })
      .then(function () {
        return navigator.serviceWorker.ready;
      });
  }

  function setFlutterClicks(enabled) {
    var i;
    var children = document.body ? document.body.children : [];
    for (i = 0; i < children.length; i++) {
      var n = children[i];
      if (n.id === 'agronizer-setup') {
        n.style.pointerEvents = 'auto';
        continue;
      }
      if (!enabled) {
        if (n.dataset.agPe === undefined) {
          n.dataset.agPe = n.style.pointerEvents || '';
        }
        n.style.pointerEvents = 'none';
      } else if (n.dataset.agPe !== undefined) {
        n.style.pointerEvents = n.dataset.agPe;
        delete n.dataset.agPe;
      }
    }
    var sel =
      'flt-glass-pane, flutter-view, flt-scene-host, flt-semantics-host, .flutter-view';
    document.querySelectorAll(sel).forEach(function (el) {
      el.style.pointerEvents = enabled ? '' : 'none';
    });
  }

  function pushDeviceId() {
    var existing = localStorage.getItem('web_push_device_id');
    if (existing) return existing;
    // Flutter SharedPreferences on web: flutter.<key> with JSON string value.
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
      'web-' +
      Date.now() +
      '-' +
      Math.random().toString(36).slice(2, 10);
    localStorage.setItem('web_push_device_id', id);
    try {
      localStorage.setItem('flutter.web_push_device_id', JSON.stringify(id));
    } catch (_) {}
    return id;
  }

  /** Register Web Push with agronizer-push (permission alone is not enough). */
  function subscribePushNow() {
    if (!window.AgronizerPush || typeof AgronizerPush.subscribe !== 'function') {
      console.warn('AgronizerPush missing');
      return Promise.resolve(false);
    }
    if (!AgronizerPush.isSupported()) {
      console.warn('AgronizerPush not supported in this browser/context');
      return Promise.resolve(false);
    }
    var id = pushDeviceId();
    var run = function () {
      if (typeof AgronizerPush.ensureSubscribedIfNeeded === 'function') {
        return AgronizerPush.ensureSubscribedIfNeeded(id);
      }
      return AgronizerPush.subscribe(id);
    };
    return ensureServiceWorker()
      .catch(function () {
        return null;
      })
      .then(run)
      .then(function (ok) {
        console.log('AgronizerPush.ensureSubscribed', ok ? 'ok' : 'fail', id);
        return !!ok;
      })
      .catch(function (err) {
        console.warn('AgronizerPush.ensureSubscribed failed', err);
        return false;
      });
  }

  /**
   * If site notifications already granted — ensure push subscription exists
   * (browser + server), without opening the wizard.
   */
  function autoEnsurePushIfPermitted() {
    if (!notifGranted()) return Promise.resolve(false);
    localStorage.setItem(ENABLE_FLAG, '1');
    markBrowserOsOk();
    return subscribePushNow().then(function (ok) {
      if (ok) {
        window.dispatchEvent(new CustomEvent('agronizer-notify-granted'));
      }
      return ok;
    });
  }

  function enableInApp() {
    localStorage.setItem(ENABLE_FLAG, '1');
    window.dispatchEvent(new CustomEvent('agronizer-notify-granted'));
    subscribePushNow();
  }

  function browserOsMarkedOk() {
    return localStorage.getItem(BROWSER_OK_KEY) === '1';
  }

  function markBrowserOsOk() {
    localStorage.setItem(BROWSER_OK_KEY, '1');
  }

  /** Build step list; skip finished ones. */
  function computeSteps() {
    var steps = [];
    // Chrome WebAPK without site permission: only breakout + check matter.
    if (isAndroid() && !isYandex() && isAppShell() && !notifGranted()) {
      steps.push('site');
      return steps;
    }
    if (needsInstallStep()) {
      steps.push('install');
    }
    // Android OS notifications for the browser app — skip if site already granted
    // or user already confirmed this step.
    if (isAndroid() && !notifGranted() && !browserOsMarkedOk()) {
      steps.push('browser');
    }
    if (!notifGranted()) {
      // iOS: site permission only works from Home Screen PWA.
      if (isIos() && !isStandalone()) {
        // keep install only; site step after reopen from icon
      } else {
        steps.push('site');
      }
    }
    if (notifGranted() || steps.length === 0) {
      steps.push('done');
    }
    return steps;
  }

  function ensureDom() {
    if (root) return root;
    root = document.createElement('div');
    root.id = 'agronizer-setup';
    root.innerHTML =
      '<div class="ag-setup-card" role="dialog" aria-modal="true" aria-labelledby="ag-setup-title">' +
      '  <button type="button" class="ag-setup-x" aria-label="Закрыть" data-action="dismiss">×</button>' +
      '  <p class="ag-setup-progress" data-role="progress"></p>' +
      '  <h2 id="ag-setup-title" data-role="title">Настройка</h2>' +
      '  <p class="ag-setup-lead" data-role="lead"></p>' +
      '  <ol class="ag-setup-steps" data-role="steps"></ol>' +
      '  <div class="ag-setup-actions">' +
      '    <button type="button" class="ag-setup-install" data-role="install" data-action="install" hidden>Установить на экран</button>' +
      '    <button type="button" class="ag-setup-browser" data-role="apps-settings" data-action="apps-settings" hidden>Открыть настройки приложений</button>' +
      '    <button type="button" class="ag-setup-browser" data-role="site-settings" data-action="site-settings" hidden>Настройки уведомлений Chrome</button>' +
      '    <button type="button" class="ag-setup-browser" data-role="open-browser" data-action="open-browser" hidden>Открыть с адресной строкой</button>' +
      '    <button type="button" class="ag-setup-notify" data-role="allow-site" data-action="allow-site" hidden>Разрешить уведомления сайта</button>' +
      '    <button type="button" class="ag-setup-notify" data-role="check-again" data-action="check-again" hidden>Проверить снова</button>' +
      '    <p class="ag-setup-status" data-role="status" hidden></p>' +
      '    <button type="button" class="ag-setup-continue" data-role="next" data-action="next" hidden>Далее</button>' +
      '    <button type="button" class="ag-setup-continue" data-role="continue" data-action="continue" hidden>Готово</button>' +
      '    <button type="button" class="ag-setup-later" data-action="dismiss">Позже</button>' +
      '  </div>' +
      '</div>';
    document.body.appendChild(root);

    function bindTap(node, fn) {
      if (!node) return;
      var last = 0;
      function run(e) {
        var now = Date.now();
        if (now - last < 600) return;
        last = now;
        if (e) {
          e.preventDefault();
          e.stopPropagation();
          if (e.stopImmediatePropagation) e.stopImmediatePropagation();
        }
        fn();
      }
      node.onclick = function (e) {
        run(e);
      };
      node.addEventListener(
        'pointerup',
        function (e) {
          if (e.pointerType === 'mouse' && e.button !== 0) return;
          run(e);
        },
        true,
      );
    }

    bindTap(root.querySelector('[data-role="install"]'), onInstall);
    bindTap(root.querySelector('[data-role="allow-site"]'), onAllowSite);
    bindTap(root.querySelector('[data-role="apps-settings"]'), onOpenAppsSettings);
    bindTap(root.querySelector('[data-role="site-settings"]'), onOpenSiteSettings);
    bindTap(root.querySelector('[data-role="open-browser"]'), openInBrowserTab);
    bindTap(root.querySelector('[data-role="check-again"]'), onCheckAgain);
    bindTap(root.querySelector('[data-role="next"]'), onNext);
    bindTap(root.querySelector('[data-role="continue"]'), onContinue);

    if (!document.getElementById('agronizer-setup-css')) {
      var style = document.createElement('style');
      style.id = 'agronizer-setup-css';
      style.textContent =
        '#agronizer-setup{display:none;position:fixed;inset:0;z-index:2147483646;' +
        'background:rgba(26,46,36,.45);align-items:flex-end;justify-content:center;' +
        'padding:16px;font-family:system-ui,-apple-system,sans-serif;' +
        'pointer-events:auto;-webkit-tap-highlight-color:transparent}' +
        '#agronizer-setup.ag-open{display:flex}' +
        '#agronizer-setup .ag-setup-card{position:relative;width:100%;max-width:420px;' +
        'background:#F3FAF5;color:#1A2E24;border-radius:20px 20px 16px 16px;' +
        'padding:22px 20px 18px;box-shadow:0 16px 40px rgba(27,67,50,.28);' +
        'pointer-events:auto;animation:ag-up .28s ease-out}' +
        '@keyframes ag-up{from{transform:translateY(24px);opacity:0}to{transform:none;opacity:1}}' +
        '#agronizer-setup h2{margin:0 36px 8px 0;font-size:1.25rem;font-weight:700;color:#1B4332}' +
        '#agronizer-setup .ag-setup-progress{margin:0 36px 6px 0;font-size:.8rem;font-weight:600;color:#40916C;letter-spacing:.02em}' +
        '#agronizer-setup .ag-setup-lead{margin:0 0 12px;font-size:.95rem;line-height:1.45;color:#5C7268}' +
        '#agronizer-setup .ag-setup-steps{margin:0 0 16px;padding-left:1.2rem;font-size:.92rem;line-height:1.45;color:#1A2E24}' +
        '#agronizer-setup .ag-setup-steps li{margin:0 0 8px}' +
        '#agronizer-setup .ag-setup-actions{display:flex;flex-direction:column;gap:8px}' +
        '#agronizer-setup button,#agronizer-setup a.ag-setup-browser{' +
        'font:600 15px/1.2 system-ui,sans-serif;border-radius:14px;padding:14px 14px;' +
        'cursor:pointer;border:none;text-align:center;display:block;width:100%;box-sizing:border-box;' +
        'pointer-events:auto;touch-action:manipulation;text-decoration:none;-webkit-user-select:none;user-select:none}' +
        '#agronizer-setup .ag-setup-install{background:#2D6A4F;color:#fff}' +
        '#agronizer-setup .ag-setup-notify{background:#1B4332;color:#fff}' +
        '#agronizer-setup .ag-setup-browser{background:#2D6A4F;color:#fff}' +
        '#agronizer-setup .ag-setup-continue{background:#40916C;color:#fff}' +
        '#agronizer-setup .ag-setup-later{background:transparent;color:#5C7268;font-weight:500}' +
        '#agronizer-setup .ag-setup-x{position:absolute;top:10px;right:12px;width:36px;height:36px;' +
        'border-radius:99px;background:transparent;color:#5C7268;font-size:22px;line-height:1;padding:0}' +
        '#agronizer-setup .ag-setup-status{margin:4px 0 0;font-size:.9rem;line-height:1.4;color:#2D6A4F;' +
        'min-height:1.2em;padding:8px 4px;background:rgba(45,106,79,.08);border-radius:10px}' +
        '#agronizer-setup .ag-setup-status.ag-bad{color:#9B2226;background:rgba(155,34,38,.08)}' +
        '#agronizer-setup .ag-setup-status.ag-ok{color:#1B4332;background:rgba(64,145,108,.15)}' +
        '#agronizer-setup [hidden]{display:none!important}';
      document.head.appendChild(style);
    }

    root.addEventListener(
      'click',
      function (e) {
        var t = e.target;
        if (t === root) {
          dismiss();
          return;
        }
        var btn = t && t.closest ? t.closest('[data-action="dismiss"]') : null;
        if (btn) {
          e.preventDefault();
          e.stopPropagation();
          dismiss();
        }
      },
      true,
    );

    return root;
  }

  function el(role) {
    return ensureDom().querySelector('[data-role="' + role + '"]');
  }

  function hideAllActions() {
    [
      'install',
      'apps-settings',
      'site-settings',
      'open-browser',
      'allow-site',
      'check-again',
      'next',
      'continue',
    ].forEach(function (role) {
      var n = el(role);
      if (n) n.hidden = true;
    });
  }

  function setStatus(text, kind) {
    var s = el('status');
    if (!s) return;
    s.classList.remove('ag-bad', 'ag-ok');
    if (!text) {
      s.hidden = true;
      s.textContent = '';
      return;
    }
    s.hidden = false;
    s.removeAttribute('hidden');
    s.textContent = text;
    if (kind === 'bad') s.classList.add('ag-bad');
    if (kind === 'ok') s.classList.add('ag-ok');
  }

  function openSiteSettingsHelp() {
    if (isIos()) {
      setStatus(
        'Настройки iPhone → Уведомления → Агронайзер → Допуск уведомлений.',
        'bad',
      );
      try {
        window.location.href = 'app-settings:';
      } catch (_) {}
      return;
    }
    if (isYandex()) {
      setStatus(
        'Яндекс: ≡ → Настройки → Сайты → Уведомления → agronizer.ru → Разрешить. Затем вернитесь и «Проверить снова».',
        'bad',
      );
      return;
    }
    setStatus(
      'В браузере: Настройки → Сайты → Уведомления → agronizer.ru → Разрешить.',
      'bad',
    );
  }

  function onOpenAppsSettings() {
    setStatus(
      'Настройки Android → Приложения. Найдите «Chrome» или «Микрозелень» → Уведомления → вкл. Затем вернитесь и «Проверить»/«Далее».',
      'ok',
    );
    launchAndroidIntent(androidAppsListIntent());
  }

  function onOpenSiteSettings() {
    setStatus(
      'Открываем уведомления Chrome. Включите их, при необходимости зайдите в «Дополнительно / Сайты». Затем вернитесь и «Проверить».',
      'ok',
    );
    if (!launchAndroidIntent(chromeAppNotificationSettingsIntent())) {
      openSiteSettingsHelp();
    }
  }

  function onOpenChromeAppDetails() {
    setStatus(
      'Открываем «О приложении Chrome». Зайдите в Уведомления → разрешите. Затем вернитесь и «Проверить».',
      'ok',
    );
    if (!launchAndroidIntent(chromeAppDetailsIntent())) {
      launchAndroidIntent(androidAppsListIntent());
    }
  }

  function renderStep() {
    ensureDom();
    document.body.appendChild(root);

    stepIds = computeSteps();
    if (stepIndex >= stepIds.length) stepIndex = Math.max(0, stepIds.length - 1);
    var id = stepIds[stepIndex] || 'done';

    // Recompute may have skipped steps — snap index to current id list.
    hideAllActions();
    setStatus('');

    var progress = el('progress');
    var title = el('title');
    var lead = el('lead');
    var steps = el('steps');
    var installBtn = el('install');
    var appsBtn = el('apps-settings');
    var siteBtn = el('site-settings');
    var allowBtn = el('allow-site');
    var checkBtn = el('check-again');
    var nextBtn = el('next');
    var continueBtn = el('continue');

    if (progress) {
      progress.textContent =
        'Шаг ' + (stepIndex + 1) + ' из ' + stepIds.length;
    }

    if (id === 'install') {
      title.textContent = 'Иконка на экране «Домой»';
      if (isIos()) {
        if (!iosSupportsWebPush()) {
          lead.textContent =
            'Для напоминаний нужна iOS 16.4+. Сначала обновите iPhone, затем добавьте иконку.';
        } else {
          lead.textContent =
            'На iPhone уведомления работают только из иконки на «Домой», не из вкладки Safari.';
        }
        steps.innerHTML =
          '<li>В Safari нажмите «Поделиться» (□↑)</li>' +
          '<li>Выберите «На экран „Домой“» → «Добавить»</li>' +
          '<li>Откройте Агронайзер с новой иконки и продолжите настройку</li>';
        if (installBtn) installBtn.hidden = true;
        setStatus('Без иконки на iPhone Push недоступен.', 'bad');
      } else if (isYandex()) {
        lead.textContent =
          'В Яндекс.Браузере нет системного окна «Установить». Иконку нужно добавить из меню — так удобнее открывать Микрозелень.';
        steps.innerHTML =
          '<li>Нажмите ≡ (меню) слева или справа внизу / вверху</li>' +
          '<li>Выберите «Добавить на рабочий стол» или «Добавить ярлык»</li>' +
          '<li>Подтвердите «Добавить»</li>' +
          '<li>Откройте с новой иконки (по желанию) и нажмите «Далее»</li>';
        if (installBtn) {
          installBtn.hidden = false;
          installBtn.textContent = 'Показать, куда нажать';
        }
        if (nextBtn) {
          nextBtn.hidden = false;
          nextBtn.textContent = 'Далее — иконка есть / пропустить';
        }
        setStatus(
          'Яндекс сам не предлагает установку — только через меню ≡.',
        );
      } else if (isAndroid()) {
        // Chrome: fullscreen WebAPK hides address bar — prefer a normal tab.
        lead.textContent =
          'В Chrome лучше открывать сайт во вкладке (с адресной строкой) — так можно разрешить уведомления через замок. Старую иконку «на весь экран» удалите.';
        steps.innerHTML =
          '<li>Удалите старую иконку «Микрозелень» с экрана «Домой» (долгое нажатие → Удалить)</li>' +
          '<li>Откройте https://agronizer.ru/apps/microgreens/ во вкладке Chrome</li>' +
          '<li>По желанию: ⋮ → «Добавить на главный экран» / ярлык (должен открываться с адресной строкой)</li>' +
          '<li>Нажмите «Далее»</li>';
        if (installBtn) installBtn.hidden = true;
        if (nextBtn) {
          nextBtn.hidden = false;
          nextBtn.textContent = 'Далее';
        }
        setStatus(
          'Если открыли со старой иконки — будет снова без меню. Нужна вкладка Chrome или новый ярлык.',
          'bad',
        );
      } else {
        lead.textContent =
          'Так удобнее открывать приложение и стабильнее работают напоминания.';
        steps.innerHTML =
          '<li>Нажмите «Установить на экран» (или ⋮ → «На экран Домой»)</li>' +
          '<li>Откройте с иконки по желанию, затем «Далее»</li>';
        if (installBtn) {
          installBtn.hidden = false;
          installBtn.textContent = deferredPrompt
            ? 'Установить на экран'
            : 'Как установить';
        }
        if (nextBtn) {
          nextBtn.hidden = false;
          nextBtn.textContent = 'Далее';
        }
      }
      return;
    }

    if (id === 'browser') {
      title.textContent = 'Уведомления браузера';
      lead.textContent =
        'Сначала система должна разрешить уведомления самому приложению «' +
        browserAppLabel() +
        '». Без этого сайт не сможет присылать Push.';
      steps.innerHTML =
        '<li>Нажмите «Открыть настройки приложений»</li>' +
        '<li>Найдите «' +
        browserAppLabel() +
        '»</li>' +
        '<li>«Уведомления» → включите</li>' +
        '<li>Вернитесь сюда и нажмите «Далее»</li>';
      if (appsBtn) {
        appsBtn.hidden = false;
        appsBtn.removeAttribute('href');
        appsBtn.textContent = 'Открыть список приложений';
      }
      if (nextBtn) {
        nextBtn.hidden = false;
        nextBtn.textContent = 'Далее — уже включено';
      }
      setStatus('Если уведомления браузера уже включены — сразу «Далее».');
      return;
    }

    if (id === 'site') {
      title.textContent = 'Разрешение для сайта';
      var openBrowserBtn = el('open-browser');

      if (isIos()) {
        lead.textContent =
          'Нужно разрешить уведомления для Агронайзера в настройках iPhone.';
        steps.innerHTML =
          '<li>Настройки iPhone → Уведомления → Агронайзер</li>' +
          '<li>Включите «Допуск уведомлений»</li>' +
          '<li>Вернитесь сюда и нажмите «Проверить»</li>';
        if (openBrowserBtn) openBrowserBtn.hidden = true;
      } else if (isYandex()) {
        lead.textContent =
          'Нужно разрешить уведомления для agronizer.ru в настройках Яндекса.';
        steps.innerHTML =
          '<li>≡ → Настройки → Сайты → Уведомления</li>' +
          '<li>Найдите agronizer.ru → Разрешить</li>' +
          '<li>Вернитесь сюда и нажмите «Проверить»</li>';
        if (openBrowserBtn) openBrowserBtn.hidden = true;
      } else {
        // Chrome WebAPK cannot show address bar — must open a real tab / Custom Tab.
        lead.textContent = isAppShell()
          ? 'Вы внутри приложения Chrome без адресной строки — так устроен Android. Включить «замок» здесь нельзя. Откройте сайт во вкладке.'
          : 'Разрешите уведомления для agronizer.ru через замок в адресной строке. Если строки нет — вы в приложении: нажмите кнопку ниже.';
        steps.innerHTML =
          '<li>Нажмите «Открыть с адресной строкой»</li>' +
          '<li>В новой вкладке: замок / ⓘ слева от адреса → Уведомления → Разрешить</li>' +
          '<li>Вернитесь в это окно и нажмите «Проверить»</li>' +
          '<li>Если вкладка не открылась: Chrome → введите agronizer.ru/apps/microgreens/ вручную (не с иконки)</li>';
        if (openBrowserBtn) {
          openBrowserBtn.hidden = false;
          openBrowserBtn.textContent = 'Открыть с адресной строкой';
        }
      }

      if (allowBtn) allowBtn.hidden = true;
      if (siteBtn) siteBtn.hidden = true;
      if (appsBtn) appsBtn.hidden = true;

      if (checkBtn) {
        checkBtn.hidden = false;
        checkBtn.disabled = false;
        checkBtn.textContent = 'Проверить';
      }
      setStatus(
        notifDenied()
          ? 'Сейчас сайту запрещено. Откройте вкладку с адресной строкой, разрешите, затем «Проверить».'
          : 'После разрешения во вкладке вернитесь и нажмите «Проверить».',
        notifDenied() ? 'bad' : undefined,
      );
      return;
    }

    // done
    title.textContent = 'Готово';
    if (notifGranted()) {
      enableInApp();
      lead.textContent = 'Уведомления разрешены. Регистрируем Push на сервере…';
      steps.innerHTML =
        '<li>Иконка на экране — ' +
        (isStandalone() ? 'установлена' : 'по желанию') +
        '</li>' +
        '<li>Уведомления сайта включены</li>' +
        '<li>Подписка Push…</li>';
      setStatus('Сохраняем подписку на agronizer.ru/push…');
      if (checkBtn) {
        checkBtn.hidden = false;
        checkBtn.disabled = false;
        checkBtn.textContent = 'Повторить подписку';
      }
      subscribePushNow().then(function (ok) {
        if (!root || !root.classList.contains('ag-open')) return;
        if (stepIds[stepIndex] !== 'done') return;
        if (ok) {
          lead.textContent =
            'Уведомления разрешены, Push зарегистрирован. Можно пользоваться напоминаниями.';
          steps.innerHTML =
            '<li>Иконка на экране — ' +
            (isStandalone() ? 'установлена' : 'по желанию') +
            '</li>' +
            '<li>Уведомления сайта включены</li>' +
            '<li>Подписка на сервере сохранена</li>';
          setStatus('Подписка OK. На /push/health должно быть subscriptions ≥ 1.', 'ok');
          if (checkBtn) checkBtn.hidden = true;
        } else {
          lead.textContent =
            'Разрешение есть, но подписка на сервер не сохранилась.';
          steps.innerHTML =
            '<li>Проверьте сеть и https://agronizer.ru</li>' +
            '<li>В Яндексе лучше открыть с иконки на рабочем столе</li>' +
            '<li>Нажмите «Повторить подписку»</li>';
          setStatus('Подписка не удалась — без неё Push не придёт.', 'bad');
        }
      });
    } else {
      lead.textContent = 'Основные шаги пройдены. Уведомления сайта ещё не включены.';
      steps.innerHTML = '<li>Можно закрыть и включить позже в Настройках приложения</li>';
      setStatus('Напоминания заработают после разрешения сайту.', 'bad');
    }
    if (continueBtn) {
      continueBtn.hidden = false;
      continueBtn.textContent = 'Готово';
    }
  }

  function goNext() {
    stepIndex += 1;
    stepIds = computeSteps();
    // After marking browser ok / install, recompute may shrink list —
    // keep going to the first remaining needed step.
    if (stepIndex >= stepIds.length) {
      stepIds = computeSteps();
      stepIndex = Math.max(0, stepIds.length - 1);
    }
    renderStep();
  }

  function onNext() {
    var id = stepIds[stepIndex];
    if (id === 'browser') {
      markBrowserOsOk();
    }
    if (id === 'install') {
      markInstallSkipped();
    }

    stepIds = computeSteps();

    if (id === 'install') {
      var afterInstall = stepIds.indexOf('browser');
      if (afterInstall < 0) afterInstall = stepIds.indexOf('site');
      if (afterInstall < 0) afterInstall = stepIds.indexOf('done');
      stepIndex = afterInstall >= 0 ? afterInstall : 0;
      renderStep();
      return;
    }

    if (id === 'browser') {
      var afterBrowser = stepIds.indexOf('site');
      if (afterBrowser < 0) afterBrowser = stepIds.indexOf('done');
      stepIndex = afterBrowser >= 0 ? afterBrowser : 0;
      renderStep();
      return;
    }

    goNext();
  }

  function onContinue() {
    if (notifGranted()) {
      enableInApp();
      localStorage.setItem(DONE_KEY, '1');
    }
    hide();
  }

  function dismiss() {
    sessionStorage.setItem(DISMISS_KEY, '1');
    hide();
  }

  function show(opts) {
    opts = opts || {};
    // Still show if icon step is needed (Yandex / not installed).
    if (
      localStorage.getItem(DONE_KEY) === '1' &&
      notifGranted() &&
      !needsInstallStep() &&
      !opts.force
    ) {
      return;
    }
    ensureDom();
    stepIds = computeSteps();
    stepIndex = 0;
    if (opts.step) {
      var idx = stepIds.indexOf(opts.step);
      if (idx >= 0) stepIndex = idx;
    }
    // Prefer install when forced / Yandex and step still in list.
    if (!opts.step && needsInstallStep() && stepIds.indexOf('install') >= 0) {
      stepIndex = stepIds.indexOf('install');
    }
    renderStep();
    root.classList.add('ag-open');
    setFlutterClicks(false);
    ensureServiceWorker().catch(function () {});
  }

  function hide() {
    if (root) root.classList.remove('ag-open');
    setFlutterClicks(true);
  }

  async function onInstall() {
    if (deferredPrompt) {
      try {
        deferredPrompt.prompt();
        await deferredPrompt.userChoice;
      } catch (_) {}
      deferredPrompt = null;
      markInstallSkipped();
      renderStep();
      return;
    }
    if (isIos()) {
      setStatus('Safari: Поделиться → На экран «Домой» → Добавить.', 'bad');
      return;
    }
    if (isYandex()) {
      setStatus(
        'Откройте меню ≡ → пролистайте → «Добавить на рабочий стол» / «Добавить ярлык» → Добавить. Затем вернитесь и нажмите «Далее».',
        'ok',
      );
      return;
    }
    setStatus(
      'Меню браузера ⋮ → «Установить приложение» или «На экран Домой».',
      'ok',
    );
  }

  function requestSitePermission() {
    if (!notifSupported()) return Promise.resolve('unsupported');
    if (Notification.permission === 'granted') return Promise.resolve('granted');
    if (Notification.permission === 'denied') return Promise.resolve('denied');
    var pending;
    try {
      pending = Notification.requestPermission();
    } catch (_) {
      return Promise.resolve(Notification.permission || 'denied');
    }
    return Promise.resolve(pending).then(function (result) {
      return result || Notification.permission || 'denied';
    });
  }

  function onAllowSite() {
    var btn = el('allow-site');
    if (btn) btn.disabled = true;

    if (!notifSupported()) {
      if (btn) btn.disabled = false;
      setStatus('Этот браузер не поддерживает уведомления.', 'bad');
      return;
    }

    if (isIos() && !isStandalone()) {
      if (btn) btn.disabled = false;
      setStatus('Сначала откройте Агронайзер с иконки на «Домой».', 'bad');
      return;
    }

    if (Notification.permission === 'granted') {
      if (btn) btn.disabled = false;
      enableInApp();
      markBrowserOsOk();
      stepIds = computeSteps();
      stepIndex = stepIds.indexOf('done');
      if (stepIndex < 0) stepIndex = stepIds.length - 1;
      renderStep();
      return;
    }

    // Already denied: browser will NOT show a prompt — open settings / show howto.
    if (Notification.permission === 'denied') {
      if (btn) btn.disabled = false;
      setStatus(
        'Окно «Разрешить» недоступно: сайт уже запрещён. Включите вручную в настройках.',
        'bad',
      );
      onOpenSiteSettings();
      return;
    }

    // CRITICAL: call requestPermission in the same synchronous turn as the tap.
    // Any await (service worker) before this breaks the user-gesture on Android/Yandex.
    setStatus('В окне браузера нажмите «Разрешить»…');
    var pending;
    try {
      pending = Notification.requestPermission();
    } catch (_) {
      if (btn) btn.disabled = false;
      setStatus('Не удалось показать запрос. Откройте настройки сайта.', 'bad');
      return;
    }

    Promise.resolve(pending)
      .then(function (result) {
        var perm = result || Notification.permission || 'denied';
        if (btn) btn.disabled = false;
        if (perm === 'granted') {
          // SW can be ensured after grant — gesture no longer needed.
          ensureServiceWorker().catch(function () {});
          enableInApp();
          markBrowserOsOk();
          stepIds = computeSteps();
          stepIndex = stepIds.indexOf('done');
          if (stepIndex < 0) stepIndex = stepIds.length - 1;
          renderStep();
          return;
        }
        if (perm === 'denied') {
          setStatus(
            'Запрещено. Включите уведомления для agronizer.ru в настройках сайта, затем «Проверить снова».',
            'bad',
          );
          return;
        }
        setStatus(
          'Окно закрыто без разрешения. Нажмите кнопку ещё раз.',
          'bad',
        );
      })
      .catch(function () {
        if (btn) btn.disabled = false;
        setStatus('Ошибка запроса. Попробуйте «Открыть настройки сайта».', 'bad');
      });
  }

  function onCheckAgain() {
    var now = Date.now();
    if (now - checkAgainAt < 400) return;
    checkAgainAt = now;

    var checkBtn = el('check-again');
    if (checkBtn) checkBtn.disabled = true;

    // On done step: retry server subscription only.
    if (stepIds[stepIndex] === 'done' && notifGranted()) {
      setStatus('Повторная регистрация Push…');
      subscribePushNow().then(function (ok) {
        if (checkBtn) checkBtn.disabled = false;
        if (ok) {
          setStatus('Подписка OK.', 'ok');
          if (checkBtn) checkBtn.hidden = true;
        } else {
          setStatus('Подписка не удалась. Попробуйте ещё раз.', 'bad');
        }
      });
      return;
    }

    setStatus('Проверяем…');
    var perm = notifSupported() ? Notification.permission : 'unsupported';

    function finishGranted() {
      if (checkBtn) checkBtn.disabled = false;
      enableInApp();
      markBrowserOsOk();
      stepIds = computeSteps();
      stepIndex = stepIds.indexOf('done');
      if (stepIndex < 0) stepIndex = stepIds.length - 1;
      renderStep();
    }

    if (perm === 'granted') {
      finishGranted();
      return;
    }

    if (perm === 'unsupported') {
      if (checkBtn) checkBtn.disabled = false;
      setStatus('Этот браузер не поддерживает уведомления.', 'bad');
      return;
    }

    // default: try native prompt from this tap (same user gesture).
    if (perm === 'default') {
      var pending;
      try {
        pending = Notification.requestPermission();
      } catch (_) {
        if (checkBtn) checkBtn.disabled = false;
        setStatus('Не удалось запросить разрешение. Включите вручную по инструкции выше.', 'bad');
        return;
      }
      Promise.resolve(pending).then(function (result) {
        var p = result || Notification.permission;
        if (p === 'granted') {
          finishGranted();
          return;
        }
        if (checkBtn) checkBtn.disabled = false;
        setStatus(
          p === 'denied'
            ? 'Запрещено. Включите agronizer.ru в настройках сайта, затем снова «Проверить».'
            : 'Ещё не разрешено. Выполните шаги выше и нажмите «Проверить».',
          'bad',
        );
      });
      return;
    }

    // denied
    if (checkBtn) checkBtn.disabled = false;
    setStatus(
      isYandex()
        ? 'Ещё запрещено. ≡ → Настройки → Сайты → Уведомления → agronizer.ru → Разрешить, затем «Проверить».'
        : 'Ещё запрещено. Включите уведомления для agronizer.ru по инструкции выше, затем «Проверить».',
      'bad',
    );
  }

  function refreshAfterReturn() {
    if (!root || !root.classList.contains('ag-open')) return;
    setFlutterClicks(false);
    document.body.appendChild(root);
    if (notifGranted()) {
      enableInApp();
      markBrowserOsOk();
      stepIds = computeSteps();
      stepIndex = stepIds.indexOf('done');
      if (stepIndex < 0) stepIndex = 0;
    }
    renderStep();
  }

  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault();
    deferredPrompt = e;
    if (sessionStorage.getItem(DISMISS_KEY) === '1') return;
    if (localStorage.getItem(DONE_KEY) === '1' && notifGranted()) return;
    // Show wizard with install step available
    if (!root || !root.classList.contains('ag-open')) {
      show();
    } else {
      renderStep();
    }
  });

  window.addEventListener('appinstalled', function () {
    deferredPrompt = null;
    markInstallSkipped();
    if (root && root.classList.contains('ag-open')) {
      stepIds = computeSteps();
      stepIndex = 0;
      renderStep();
    }
  });

  window.addEventListener('focus', refreshAfterReturn);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'visible') refreshAfterReturn();
  });
  window.addEventListener('pageshow', refreshAfterReturn);

  var mo = new MutationObserver(function () {
    if (root && root.classList.contains('ag-open')) setFlutterClicks(false);
  });
  mo.observe(document.documentElement, { childList: true, subtree: true });

  window.AgronizerPwa = {
    isStandalone: isStandalone,
    showSetup: function () {
      show();
    },
    hideSetup: hide,
    /** Open wizard on site-permission step (no Flutter extra dialogs). */
    openNotificationSettings: function () {
      show({ step: notifGranted() ? 'done' : 'site' });
    },
    canInstallNatively: function () {
      return !!deferredPrompt;
    },
    /** Re-check browser permission and (re)register push on server. */
    ensurePushSubscription: function () {
      return autoEnsurePushIfPermitted();
    },
  };

  function boot() {
    // Setup gate on index.html owns first-run UX (icon + notifications).
    // Do not open the in-app sheet again after the gate finished / skipped.
    if (
      localStorage.getItem('agronizer_gate_done_v1') === '1' ||
      localStorage.getItem('agronizer_gate_skip_push_v1') === '1'
    ) {
      autoEnsurePushIfPermitted();
      return;
    }

    // Always: permissions already granted → ensure Push subscription silently.
    autoEnsurePushIfPermitted();

    if (sessionStorage.getItem(DISMISS_KEY) === '1') return;

    if (localStorage.getItem(DONE_KEY) === '1' && notifGranted()) {
      if (needsInstallStep()) {
        show({ step: 'install', force: true });
      }
      return;
    }

    var started = false;
    function afterFlutterReady() {
      if (started) return;
      started = true;
      if (localStorage.getItem('agronizer_gate_done_v1') === '1') return;
      if (sessionStorage.getItem(DISMISS_KEY) === '1') return;
      autoEnsurePushIfPermitted();
      if (notifGranted()) {
        if (needsInstallStep()) {
          show({ step: 'install', force: true });
        }
        return;
      }
      // Gate should have handled first run; only show if user landed without gate.
      if (!window.AgronizerGate) show({ force: true });
    }

    window.addEventListener('agronizer-flutter-ready', afterFlutterReady, {
      once: true,
    });
    window.addEventListener('agronizer-notify-flow-done', function () {
      if (notifGranted()) {
        autoEnsurePushIfPermitted();
        if (root && root.classList.contains('ag-open')) {
          stepIds = computeSteps();
          if (needsInstallStep() && stepIds.indexOf('install') >= 0) {
            stepIndex = stepIds.indexOf('install');
          } else {
            stepIndex = stepIds.indexOf('done');
            if (stepIndex < 0) stepIndex = 0;
          }
          renderStep();
        }
      }
    });
    setTimeout(afterFlutterReady, 4000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
