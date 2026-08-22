/* Reload the installed PWA when a new service worker takes over.
 * Do not call update() on the first paint — that used to reinstall the SW
 * and leave a blank screen for several seconds.
 */
(function () {
  if (!('serviceWorker' in navigator)) return;

  var reloading = false;
  if (navigator.serviceWorker.controller) {
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      if (reloading) return;
      reloading = true;
      location.reload();
    });
  }

  function ping(reg) {
    try {
      reg.update();
    } catch (_) {}
  }

  navigator.serviceWorker.getRegistration().then(function (reg) {
    if (!reg) return;
    setTimeout(function () {
      ping(reg);
    }, 15000);
    setInterval(function () {
      ping(reg);
    }, 5 * 60 * 1000);
  });
})();
