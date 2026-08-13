# Agronizer (монорепозиторий приложений)

Платформа [agronizer.ru](https://agronizer.ru): портал и несколько приложений.
Сейчас в реестре одно — **Микрозелень** (`apps/microgreens`).

`docker-compose.yml` **не внутри** этого проекта: он общий на весь серверный стек
(Traefik, Portainer, Agronizer, …) и лежит **рядом** с папкой `agronizer/`.

## Раскладка на сервере

```
/path/to/stack/                 # корень compose (где docker-compose.yml)
  docker-compose.yml            # общий стек, много сервисов
  agronizer/                    # ЭТОТ проект
    apps/
      apps.json
      microgreens/              # Flutter «Микрозелень»
    site/                       # портал + собранные PWA/APK
      index.html
      apps/microgreens/
    platform/
      push/                     # общий бэкенд: статика + Web Push
        data/                   # VAPID, подписки (том Docker)
    scripts/
  portainer/                    # другие сервисы стека…
  uptime-kuma/
  …
```

В compose сервис `agronizer` смотрит сюда:

- `build: ./agronizer/platform/push`
- `./agronizer/site` → `/var/www`
- `./agronizer/platform/push/data` → `/data`

## Структура репозитория (`agronizer/`)

```
apps/
  apps.json                 # реестр приложений
  microgreens/              # Flutter-проект
site/                       # статика для продакшена
platform/
  push/                     # общий Node: сайт + /push/
scripts/
  apps.ps1                  # реестр приложений (подключают другие скрипты)
  build_app.ps1             # сборка одного приложения (APK и/или PWA)
  build_all.ps1             # все приложения из apps.json
  patch_pwa_sw.ps1          # внутренняя: подмена service worker после flutter build web
```

## Общий push-бэкенд

**Один** `platform/push` на все приложения Agronizer:

| Что | Как |
|-----|-----|
| API | `https://agronizer.ru/push/` |
| VAPID | одни ключи в `platform/push/data/vapid.json` |
| Подписки | `subscriptions.json` / `schedules.json` там же |
| Клик по push | `url` из расписания, иначе `DEFAULT_APP_URL` |

Отдельный push-контейнер на приложение не нужен.

| URL | Содержимое |
|-----|------------|
| `/` | портал |
| `/gate/microgreens/` | настройка Push (после иконки; обычная вкладка) |
| `/apps/microgreens/` | PWA |
| `/apps/microgreens/microgreens.apk` | APK |
| `/push/health` | общий push |
| `/app/`, `/green_grow.apk` | редиректы → `/apps/microgreens/…` |

## Сборка на ПК

Flutter на сервер не нужен:

```powershell
cd agronizer   # каталог этого репо

.\scripts\build_all.ps1
.\scripts\build_app.ps1 -AppId microgreens
.\scripts\build_app.ps1 -AppId microgreens -SkipApk   # только PWA
.\scripts\build_app.ps1 -AppId microgreens -SkipWeb   # только APK
```

Артефакты: `agronizer\site\apps\<id>\`.

Docker-образ собирайте в корне стека (`docker compose build agronizer`), не из этого репо. Опция `-Docker` у `build_all.ps1` — только если запускаете скрипт уже из корня стека.

## Локальный запуск в браузере

Портал — это `site/index.html`. Его нельзя открыть как файл: ссылки вида `/apps/microgreens/` работают только с HTTP-сервером. Локально тот же Node, что на проде (`platform/push`).

Нужен Node.js 20+. Сборка Flutter не нужна, если `site/apps/microgreens/` уже есть.

```powershell
cd agronizer\platform\push
npm install
npm start
```

Откройте в Chrome: **http://localhost:3000/**

- http://localhost:3000/ — стартовая страница (`site/index.html`)
- http://localhost:3000/apps/microgreens/ — PWA «Микрозелень»
- http://localhost:3000/apps/microgreens/?setup=1&fresh=1 — установка PWA (как кнопка на портале)
- http://localhost:3000/push/health — push-бэкенд

Если меняли Flutter-приложение, перед `npm start` пересоберите PWA:

```powershell
cd agronizer
.\scripts\build_app.ps1 -AppId microgreens -SkipApk
```

### Только UI Flutter (без портала)

Hot reload, без `site/index.html` и без `/push/`:

```powershell
cd agronizer\apps\microgreens
C:\src\flutter\bin\flutter.bat run -d chrome --web-port 8080 --no-web-resources-cdn
```

Смотрите окно Chrome, которое открыл Flutter. `--no-web-resources-cdn` нужен, иначе страница часто пустая.

## Новое приложение

1. Flutter в `apps/<id>/`
2. Запись в `apps/apps.json`
3. `.\scripts\build_app.ps1 -AppId <id>`
4. Ссылка в `site/index.html`
5. В schedule Web Push — `url: "/apps/<id>/"`

---

## Что копировать на сервер

Корень стека = папка с `docker-compose.yml`. Рядом должна быть папка **`agronizer/`**.

| С ПК (из репо) | На сервер |
|----------------|-----------|
| всё нужное для деплоя | `…/stack/agronizer/` |
| в т.ч. `site/` | `…/stack/agronizer/site/` |
| в т.ч. `platform/push/` | `…/stack/agronizer/platform/push/` |

`docker-compose.yml` уже лежит в `…/stack/` (общий) — его не кладут внутрь `agronizer/`.

**Не копировать:** Flutter SDK, `apps/*/build`, `node_modules` (если нет собранного `site/`).

Пример:

```powershell
# на ПК
cd agronizer
.\scripts\build_all.ps1

# залить проект в папку agronizer рядом с compose
scp -r .\site .\platform .\apps\apps.json user@SERVER:/path/to/stack/agronizer/
# либо целиком репо:
# scp -r . user@SERVER:/path/to/stack/agronizer/
```

На сервере (из **корня стека**, не из `agronizer/`):

```bash
cd /path/to/stack

# миграция со старых путей (если были ./agronizer как статика или agronizer-push)
docker compose rm -sf agronizer agronizer-push 2>/dev/null || true
mkdir -p agronizer/platform/push/data
# сохранить подписки:
# cp -a agronizer-push/data/. agronizer/platform/push/data/

docker compose build agronizer
docker compose up -d agronizer
```

Проверка:

```bash
curl -s https://agronizer.ru/health
curl -s https://agronizer.ru/push/health
```

- https://agronizer.ru/
- https://agronizer.ru/apps/microgreens/
- https://agronizer.ru/push/health

### Обновления

**Только APK/PWA:** залить новый `agronizer/site/` →  
`docker compose restart agronizer`

**Код push-сервера:** залить `agronizer/platform/push/` (кроме `data/`) →  
`docker compose build agronizer && docker compose up -d agronizer`

### Переменные (сервис `agronizer`)

| Переменная | Назначение |
|------------|------------|
| `STATIC_DIR=/var/www` | `agronizer/site` |
| `DATA_DIR=/data` | `agronizer/platform/push/data` |
| `VAPID_SUBJECT` | mailto для VAPID |
| `DEFAULT_APP_URL` | fallback URL в push |
| `PUSH_API_KEY` | опционально для `POST /push/api/send` |

---

## Микрозелень

[`apps/microgreens/README.md`](apps/microgreens/README.md)
