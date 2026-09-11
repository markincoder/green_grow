/* Cookie notice for agronizer.ru — informational banner (ФЗ-152 / Metrika cookies). */
(function () {
  var KEY = 'agronizer_cookie_notice_v1';
  try {
    if (localStorage.getItem(KEY) === '1') return;
  } catch (_) {}

  function ready(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  ready(function () {
    try {
      if (localStorage.getItem(KEY) === '1') return;
    } catch (_) {}
    if (document.getElementById('agronizer-cookie-notice')) return;

    var style = document.createElement('style');
    style.textContent =
      '#agronizer-cookie-notice{position:fixed;left:0;right:0;bottom:0;z-index:2147483000;' +
      'padding:12px 16px calc(12px + env(safe-area-inset-bottom,0px));' +
      'box-sizing:border-box;font-family:Manrope,system-ui,-apple-system,sans-serif;' +
      'background:rgba(27,67,50,.96);color:#f3faf5;box-shadow:0 -8px 28px rgba(26,46,36,.22)}' +
      '#agronizer-cookie-notice .ag-cookie-inner{max-width:960px;margin:0 auto;display:flex;' +
      'flex-wrap:wrap;align-items:center;gap:12px 16px}' +
      '#agronizer-cookie-notice p{margin:0;flex:1 1 220px;font-size:.9rem;line-height:1.45;' +
      'color:#e8f5ee}' +
      '#agronizer-cookie-notice a{color:#d8f3dc;text-decoration:underline;text-underline-offset:2px}' +
      '#agronizer-cookie-notice a:hover{color:#fff}' +
      '#agronizer-cookie-notice button{flex:0 0 auto;min-height:42px;padding:0 18px;border:0;' +
      'border-radius:12px;background:#52b788;color:#1b4332;font:inherit;font-weight:700;' +
      'font-size:.95rem;cursor:pointer}' +
      '#agronizer-cookie-notice button:hover{background:#74c69d}' +
      '@media (max-width:520px){#agronizer-cookie-notice button{width:100%}}';

    var banner = document.createElement('div');
    banner.id = 'agronizer-cookie-notice';
    banner.setAttribute('role', 'dialog');
    banner.setAttribute('aria-live', 'polite');
    banner.setAttribute('aria-label', 'Уведомление о файлах cookie');
    banner.innerHTML =
      '<div class="ag-cookie-inner">' +
      '<p>Мы используем файлы cookie и Яндекс Метрику для работы сайта и статистики. ' +
      'Продолжая пользоваться сайтом, вы соглашаетесь с этим. ' +
      'Подробнее — в <a href="/legal/privacy.html">политике конфиденциальности</a>.</p>' +
      '<button type="button" data-action="accept">Понятно</button>' +
      '</div>';

    banner.querySelector('[data-action="accept"]').addEventListener('click', function () {
      try {
        localStorage.setItem(KEY, '1');
      } catch (_) {}
      if (banner.parentNode) banner.remove();
      if (style.parentNode) style.remove();
    });

    document.head.appendChild(style);
    document.body.appendChild(banner);
  });
})();
