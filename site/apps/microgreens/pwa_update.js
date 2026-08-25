/* Offer a confirm dialog when a new service worker is waiting.
 * Reload only after the user accepts (SKIP_WAITING → controllerchange),
 * or once after an activation that happened with no open clients.
 */
(function () {
  if (!('serviceWorker' in navigator)) return;

  var FLAG = 'pwa_applying_update';
  var SHOWN = 'pwa_update_prompt_shown';
  var reloading = false;
  var prompted = false;
  var watched = null;

  function scopeUrl() {
    try {
      var base = document.querySelector('base');
      if (base && base.href) return new URL('.', base.href).href;
    } catch (_) {}
    try {
      return new URL('.', location.href).href;
    } catch (_) {
      return location.href;
    }
  }

  function setUpdatingFlag() {
    try {
      sessionStorage.setItem(FLAG, '1');
    } catch (_) {}
  }

  function userAskedUpdate() {
    try {
      return sessionStorage.getItem(FLAG) === '1';
    } catch (_) {
      return false;
    }
  }

  function markPromptShown() {
    try {
      sessionStorage.setItem(SHOWN, '1');
    } catch (_) {}
    try {
      window.__agronizerPwaUpdatePrompted = true;
    } catch (_) {}
  }

  function showInstallingScreen() {
    setUpdatingFlag();
    var existing = document.getElementById('agronizer-installing');
    if (existing) return;

    var overlay = document.createElement('div');
    overlay.id = 'agronizer-installing';
    overlay.setAttribute('role', 'status');
    overlay.setAttribute('aria-live', 'polite');
    overlay.style.cssText =
      'position:fixed;inset:0;z-index:2147483646;display:flex;align-items:center;' +
      'justify-content:center;background:#F3FAF5;font-family:system-ui,-apple-system,sans-serif;' +
      'pointer-events:auto;';

    var inner = document.createElement('div');
    inner.style.cssText =
      'display:flex;flex-direction:column;align-items:center;gap:18px;' +
      'padding:24px;text-align:center;max-width:320px;';

    var img = document.createElement('img');
    img.src = 'icons/Icon-192.png';
    img.alt = '';
    img.width = 96;
    img.height = 96;

    var spin = document.createElement('div');
    spin.style.cssText =
      'width:28px;height:28px;border:3px solid rgba(45,106,79,.2);' +
      'border-top-color:#2D6A4F;border-radius:50%;' +
      'animation:ag-upd-spin .8s linear infinite';

    if (!document.getElementById('ag-upd-spin-style')) {
      var style = document.createElement('style');
      style.id = 'ag-upd-spin-style';
      style.textContent =
        '@keyframes ag-upd-spin{to{transform:rotate(360deg)}}';
      document.head.appendChild(style);
    }

    var text = document.createElement('p');
    text.textContent = 'Идёт установка, пожалуйста, подождите.';
    text.style.cssText =
      'margin:0;color:#1A2E24;font-size:1.05rem;font-weight:600;line-height:1.4';

    inner.appendChild(img);
    inner.appendChild(spin);
    inner.appendChild(text);
    overlay.appendChild(inner);
    document.body.appendChild(overlay);
    document.title = 'Установка…';
  }

  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (reloading) return;
    // Only auto-reload when the user confirmed install. Otherwise a waiting
    // worker that activated after all tabs closed would "silently" refresh.
    if (!userAskedUpdate()) return;
    reloading = true;
    showInstallingScreen();
    location.reload();
  });

  function applyWaiting(reg) {
    var waiting = reg && reg.waiting;
    if (!waiting) return;
    setUpdatingFlag();
    waiting.postMessage('SKIP_WAITING');
  }

  function showPrompt(reg) {
    if (!reg || !reg.waiting) return;
    if (!navigator.serviceWorker.controller) return;
    if (document.getElementById('agronizer-update-prompt')) return;
    if (prompted) return;
    prompted = true;
    markPromptShown();

    var overlay = document.createElement('div');
    overlay.id = 'agronizer-update-prompt';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-labelledby', 'ag-upd-title');
    overlay.style.cssText =
      'position:fixed;inset:0;z-index:2147483645;display:flex;align-items:flex-end;' +
      'justify-content:center;padding:16px;padding-bottom:max(16px,env(safe-area-inset-bottom));' +
      'box-sizing:border-box;background:rgba(26,46,36,.45);font-family:system-ui,-apple-system,sans-serif;' +
      'pointer-events:auto;';

    var card = document.createElement('div');
    card.style.cssText =
      'width:100%;max-width:420px;background:#F3FAF5;color:#1A2E24;border-radius:20px;' +
      'padding:20px 18px 16px;box-shadow:0 12px 40px rgba(26,46,36,.25)';

    var title = document.createElement('h2');
    title.id = 'ag-upd-title';
    title.textContent = 'Обнаружено обновление';
    title.style.cssText =
      'margin:0 0 8px;font-size:1.15rem;font-weight:700;line-height:1.3';

    var text = document.createElement('p');
    text.textContent =
      'Установить новую версию приложения? Страница перезагрузится.';
    text.style.cssText =
      'margin:0 0 16px;font-size:.95rem;line-height:1.45;color:#5C7268';

    var actions = document.createElement('div');
    actions.style.cssText = 'display:flex;gap:10px;justify-content:flex-end';

    var later = document.createElement('button');
    later.type = 'button';
    later.textContent = 'Позже';
    later.style.cssText =
      'flex:1;min-height:44px;border:none;border-radius:14px;background:transparent;' +
      'color:#5C7268;font-size:1rem;font-weight:600;cursor:pointer';

    var install = document.createElement('button');
    install.type = 'button';
    install.textContent = 'Установить';
    install.style.cssText =
      'flex:1.2;min-height:44px;border:none;border-radius:14px;background:#2D6A4F;' +
      'color:#fff;font-size:1rem;font-weight:700;cursor:pointer';

    later.addEventListener('click', function () {
      overlay.remove();
      prompted = false;
    });
    install.addEventListener('click', function () {
      install.disabled = true;
      later.disabled = true;
      overlay.remove();
      showInstallingScreen();
      applyWaiting(reg);
      // Fallback reload if controllerchange does not fire promptly.
      setTimeout(function () {
        if (!reloading) {
          reloading = true;
          location.reload();
        }
      }, 2500);
    });

    actions.appendChild(later);
    actions.appendChild(install);
    card.appendChild(title);
    card.appendChild(text);
    card.appendChild(actions);
    overlay.appendChild(card);
    document.body.appendChild(overlay);

    try {
      window.dispatchEvent(new CustomEvent('agronizer-pwa-update'));
    } catch (_) {}
  }

  function trackInstalling(sw, reg) {
    if (!sw) return;
    var onState = function () {
      if (sw.state === 'installed') showPrompt(reg);
    };
    sw.addEventListener('statechange', onState);
    onState();
  }

  function watch(reg) {
    if (!reg) return;
    if (watched !== reg) {
      watched = reg;
      reg.addEventListener('updatefound', function () {
        trackInstalling(reg.installing, reg);
      });
    }
    if (reg.waiting) showPrompt(reg);
    if (reg.installing) trackInstalling(reg.installing, reg);
  }

  function ping(reg) {
    if (!reg) return;
    try {
      var p = reg.update();
      if (p && typeof p.then === 'function') {
        p.then(function () {
          watch(reg);
        }).catch(function () {});
      } else {
        watch(reg);
      }
    } catch (_) {}
  }

  function attach(reg) {
    if (!reg) return;
    watch(reg);
    ping(reg);
  }

  function start() {
    var scope = scopeUrl();
    navigator.serviceWorker.getRegistration(scope).then(function (reg) {
      if (reg) {
        attach(reg);
        return;
      }
      navigator.serviceWorker.ready.then(attach).catch(function () {});
      setTimeout(function () {
        navigator.serviceWorker.getRegistration(scope).then(attach);
      }, 1500);
    });

    setInterval(function () {
      navigator.serviceWorker.getRegistration(scope).then(function (reg) {
        if (!reg) return;
        watch(reg);
        ping(reg);
      });
    }, 30 * 1000);
  }

  navigator.serviceWorker.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || data.type !== 'AGRONIZER_UPDATE_READY') return;
    navigator.serviceWorker.getRegistration(scopeUrl()).then(function (reg) {
      if (reg) showPrompt(reg);
    });
  });

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState !== 'visible') return;
    navigator.serviceWorker.getRegistration(scopeUrl()).then(function (reg) {
      if (!reg) return;
      watch(reg);
      ping(reg);
    });
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }

  window.agronizerBeginPwaInstall = showInstallingScreen;
  window.agronizerHasWaitingUpdate = function () {
    return navigator.serviceWorker
      .getRegistration(scopeUrl())
      .then(function (reg) {
        return !!(reg && reg.waiting && navigator.serviceWorker.controller);
      });
  };
})();
