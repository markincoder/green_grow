/**
 * Browser helper for Agronizer Web Push (loaded from index.html on web).
 * Talks to https://agronizer.ru/push/ (see agronizer-push service).
 */
(function () {
  const DEFAULT_API = '/push';
  const APP_SCOPE = '/apps/microgreens/';

  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(base64);
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  async function apiBase(explicit) {
    if (explicit) return explicit.replace(/\/$/, '');
    return (window.location.origin + DEFAULT_API).replace(/\/$/, '');
  }

  /**
   * Resolve the app SW registration without navigator.serviceWorker.ready.
   * .ready hangs forever on pages outside APP_SCOPE (e.g. /gate/microgreens/).
   */
  function waitForActive(reg, timeoutMs) {
    if (reg.active) return Promise.resolve(reg);
    var worker = reg.installing || reg.waiting;
    if (!worker) return Promise.resolve(reg);
    return new Promise(function (resolve, reject) {
      var done = false;
      var t = setTimeout(function () {
        if (done) return;
        done = true;
        if (reg.active) resolve(reg);
        else reject(new Error('Service Worker не активировался'));
      }, timeoutMs || 15000);
      worker.addEventListener('statechange', function () {
        if (done) return;
        if (worker.state === 'activated' || reg.active) {
          done = true;
          clearTimeout(t);
          resolve(reg);
        } else if (worker.state === 'redundant') {
          done = true;
          clearTimeout(t);
          reject(new Error('Service Worker redundant'));
        }
      });
    });
  }

  async function getRegistration() {
    if (!('serviceWorker' in navigator)) {
      throw new Error('Service Worker недоступен');
    }
    var reg = await navigator.serviceWorker.getRegistration(APP_SCOPE);
    if (!reg) {
      reg = await navigator.serviceWorker.register(APP_SCOPE + 'flutter_service_worker.js', {
        scope: APP_SCOPE,
        updateViaCache: 'none',
      });
    }
    await waitForActive(reg, 15000);
    if (!reg.active && !reg.pushManager) {
      throw new Error('Service Worker не готов');
    }
    return reg;
  }

  function isIosDevice() {
    var u = navigator.userAgent || '';
    if (/iPad|iPhone|iPod/.test(u)) return true;
    return navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
  }

  function isStandalone() {
    return (
      window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true
    );
  }

  window.AgronizerPush = {
    isSupported: function () {
      if (typeof window === 'undefined') return false;
      if (!('serviceWorker' in navigator)) return false;
      if (!('Notification' in window)) return false;
      // iOS: Web Push only inside Home Screen PWA (16.4+)
      if (isIosDevice() && !isStandalone()) return false;
      if (!('PushManager' in window)) return false;
      return true;
    },

    permission: function () {
      return typeof Notification !== 'undefined' ? Notification.permission : 'denied';
    },

    /** Open notification setup. iOS Home Screen PWA must stay standalone. */
    openSetupGate: function (opts) {
      opts = opts || {};
      try {
        if (opts.reset !== false) {
          localStorage.removeItem('agronizer_gate_done_v1');
          localStorage.removeItem('agronizer_gate_skip_push_v1');
          localStorage.removeItem('agronizer_gate_nav_ts');
          // Notification-only reentry keeps icon confirmation.
          if (opts.resetIcon) {
            localStorage.removeItem('agronizer_install_skip_v1');
            localStorage.removeItem('agronizer_install_skip_v2');
            localStorage.removeItem('agronizer_icon_ok_v3');
            try {
              sessionStorage.removeItem('agronizer_install_skip_v2');
            } catch (_) {}
          }
        }
      } catch (_) {}
      // iOS: requestPermission + Push only work inside the Home Screen app.
      // Navigating to /gate/ looks like a no-op (bounces back) and loses standalone.
      if (isIosDevice() && isStandalone()) {
        if (window.AgronizerGate && typeof window.AgronizerGate.showNotify === 'function') {
          window.AgronizerGate.showNotify();
          return;
        }
        var stay = APP_SCOPE + '?from=app&notify=1&_t=' + Date.now();
        try {
          window.location.assign(stay);
        } catch (_) {
          window.location.href = stay;
        }
        return;
      }
      var url;
      if (opts.resetIcon) {
        url = '/apps/microgreens/?setup=1&fresh=1&_t=' + Date.now();
      } else {
        var q = 'from=app&_perm=' + Date.now();
        if (opts.notifyOnly || opts.reset === false || !opts.resetIcon) {
          q += '&notify=1';
        }
        url = '/gate/microgreens/?' + q;
      }
      try {
        window.location.assign(url);
      } catch (_) {
        window.location.href = url;
      }
    },

    /** Register SW under /apps/ so Chrome Install creates a working Home Screen icon. */
    ensureServiceWorker: function () {
      return getRegistration();
    },

    ensurePermission: async function () {
      if (!this.isSupported()) return false;
      if (Notification.permission === 'granted') return true;
      if (Notification.permission === 'denied') return false;
      // Do not prompt from background/app code — user configures on /gate/.
      return false;
    },

    /** Core subscribe. Requires Notification.permission === 'granted'. Never prompts. */
    subscribeGrantedOnly: async function (deviceId, base) {
      if (!deviceId) throw new Error('deviceId required');
      if (typeof Notification === 'undefined' || Notification.permission !== 'granted') {
        return false;
      }
      if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
        return false;
      }

      const root = await apiBase(base);
      const keyRes = await fetch(root + '/api/vapid-public-key');
      if (!keyRes.ok) throw new Error('Не удалось получить VAPID-ключ');
      const { publicKey } = await keyRes.json();

      const reg = await getRegistration();
      if (!reg || !reg.pushManager) {
        throw new Error('Service Worker без PushManager');
      }
      let sub = await reg.pushManager.getSubscription();
      const keyMarker = 'agronizer_vapid_' + publicKey.slice(0, 16);
      const prevKey = localStorage.getItem('agronizer_vapid_marker');
      if (sub && prevKey !== keyMarker) {
        try {
          await sub.unsubscribe();
        } catch (_) {}
        sub = null;
      }
      if (!sub) {
        try {
          sub = await reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(publicKey),
          });
        } catch (e) {
          // Common when site permission was revoked / blocked.
          if (Notification.permission !== 'granted') return false;
          throw e;
        }
      }
      // Permission can flip during subscribe — fail closed.
      if (Notification.permission !== 'granted') return false;
      if (!sub || !sub.endpoint) return false;

      localStorage.setItem('agronizer_vapid_marker', keyMarker);

      const save = await fetch(root + '/api/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId: deviceId, subscription: sub.toJSON() }),
      });
      if (!save.ok) throw new Error('Не удалось сохранить подписку');

      if (Notification.permission !== 'granted') return false;
      return true;
    },

    subscribe: async function (deviceId, base) {
      if (!deviceId) throw new Error('deviceId required');
      if (typeof Notification === 'undefined' || Notification.permission !== 'granted') {
        throw new Error('Нет разрешения на уведомления');
      }
      const ok = await this.subscribeGrantedOnly(deviceId, base);
      if (!ok) throw new Error('Нет разрешения на уведомления');
      return true;
    },

    /** true if browser already has a PushSubscription (may still be missing on server). */
    hasBrowserSubscription: async function () {
      try {
        const reg = await getRegistration();
        const sub = await reg.pushManager.getSubscription();
        return !!(sub && sub.endpoint);
      } catch (_) {
        return false;
      }
    },

    /**
     * Strict readiness check for the setup gate.
     * Success only if: permission granted AND PushSubscription exists AND saved to server.
     * Never calls requestPermission.
     */
    verifyReady: async function (deviceId, base) {
      const perm =
        typeof Notification !== 'undefined' ? Notification.permission : 'unsupported';
      if (perm !== 'granted') {
        return {
          ok: false,
          permission: perm,
          message:
            perm === 'denied'
              ? 'Разрешение сайту отозвано (denied). Включите уведомления для agronizer.ru в замке / настройках сайта, затем снова «Проверить».'
              : 'Разрешение не выдано (сейчас: ' +
                perm +
                '). Сначала разрешите уведомления для agronizer.ru вручную.',
        };
      }

      if (navigator.permissions && navigator.permissions.query) {
        try {
          const status = await navigator.permissions.query({ name: 'notifications' });
          if (status.state !== 'granted') {
            return {
              ok: false,
              permission: status.state,
              message:
                'В браузере уведомления не разрешены (Permissions: ' +
                status.state +
                '). Разрешите для agronizer.ru и нажмите «Проверить».',
            };
          }
        } catch (_) {
          /* Safari / unsupported — rely on Notification.permission */
        }
      }

      // Re-read after async gap.
      if (Notification.permission !== 'granted') {
        return {
          ok: false,
          permission: Notification.permission,
          message:
            'Разрешение не активно (сейчас: ' +
            Notification.permission +
            ').',
        };
      }

      let subscribed = false;
      try {
        subscribed = await this.subscribeGrantedOnly(deviceId, base);
      } catch (e) {
        return {
          ok: false,
          permission: Notification.permission,
          message: 'Ошибка подписки: ' + ((e && e.message) || 'неизвестно'),
        };
      }

      if (Notification.permission !== 'granted') {
        return {
          ok: false,
          permission: Notification.permission,
          message: 'Разрешение пропало во время проверки.',
        };
      }
      if (!subscribed) {
        return {
          ok: false,
          permission: Notification.permission,
          message:
            'Разрешение есть в API, но подписку создать не удалось. Проверьте блокировку уведомлений и /push/health.',
        };
      }

      const hasSub = await this.hasBrowserSubscription();
      if (!hasSub) {
        return {
          ok: false,
          permission: Notification.permission,
          message: 'На сервер отправили, но PushSubscription в браузере отсутствует.',
        };
      }

      return {
        ok: true,
        permission: 'granted',
        message:
          'Подписка на сервере OK. Дальше нужно подтвердить, что тестовое уведомление реально видно на экране.',
      };
    },

    /**
     * Local test notification via SW. Site permission may be granted while OS/Chrome
     * notifications are off — only the user can confirm visibility.
     */
    showTestNotification: async function () {
      if (typeof Notification === 'undefined' || Notification.permission !== 'granted') {
        throw new Error('Нет разрешения на уведомления');
      }
      const reg = await getRegistration();
      if (!reg || typeof reg.showNotification !== 'function') {
        throw new Error('Service Worker не умеет showNotification');
      }
      // First test right after subscribe often races SW activation — wait briefly.
      await waitForActive(reg, 15000);
      if (!reg.active) {
        await new Promise(function (r) {
          setTimeout(r, 400);
        });
      }
      const icon = APP_SCOPE + 'icons/Icon-192.png';
      const tag = 'agronizer-verify-' + Date.now();
      // iOS appends "from {PWA name}" — do not put «Микрозелень» in the title.
      var testTitle = isIosDevice() ? 'Проверка' : 'Микрозелень — проверка';
      await reg.showNotification(testTitle, {
        body: 'Если это видно — нажмите «Вижу уведомление» на странице настройки.',
        tag: tag,
        renotify: true,
        requireInteraction: false,
        icon: icon,
        badge: icon,
        data: { url: APP_SCOPE, verify: true },
      });
      return true;
    },

    /**
     * If Notification.permission is granted: ensure PushSubscription + save to server.
     * Safe to call on every app start. Never prompts.
     */
    ensureSubscribedIfNeeded: async function (deviceId, base) {
      if (!deviceId) throw new Error('deviceId required');
      if (typeof Notification === 'undefined' || Notification.permission !== 'granted') {
        return false;
      }
      if (!this.isSupported()) return false;
      return this.subscribeGrantedOnly(deviceId, base);
    },

    unsubscribe: async function (deviceId, base) {
      const root = await apiBase(base);
      try {
        const reg = await getRegistration();
        const sub = await reg.pushManager.getSubscription();
        if (sub) await sub.unsubscribe();
      } catch (_) {}
      if (deviceId) {
        await fetch(root + '/api/subscribe', {
          method: 'DELETE',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ deviceId: deviceId }),
        });
      }
      return true;
    },

    syncSchedule: async function (deviceId, items, base) {
      if (!deviceId) throw new Error('deviceId required');
      const root = await apiBase(base);
      const res = await fetch(root + '/api/schedule', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId: deviceId, items: items || [] }),
      });
      if (res.status === 404) {
        throw new Error('subscribe_required');
      }
      if (!res.ok) throw new Error('Не удалось сохранить расписание');
      return res.json();
    },
  };

  // iOS standalone: overlay on this page. Android: /gate/ in a browser tab.
  window.AgronizerPwa = {
    showSetup: function () {
      window.AgronizerPush.openSetupGate({ notifyOnly: true, resetIcon: false });
    },
    hideSetup: function () {},
    openNotificationSettings: function () {
      window.AgronizerPush.openSetupGate({ notifyOnly: true, resetIcon: false });
    },
    canInstallNatively: function () {
      return false;
    },
    ensurePushSubscription: function () {
      var id = localStorage.getItem('web_push_device_id') || '';
      if (!id) return Promise.resolve(false);
      return window.AgronizerPush.ensureSubscribedIfNeeded(id);
    },
  };
})();