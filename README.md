# Agronizer (монорепозиторий приложений)

Платформа [agronizer.ru](https://agronizer.ru): портал и несколько приложений.
Сейчас в реестре одно — **Микрозелень** (`apps/microgreens`).

- [Раскладка на сервере](#раскладка-на-сервере)
- [Структура репозитория](#структура-репозитория)
- [Локальный запуск](#локальный-запуск)
- [Сборка на ПК](#сборка-на-пк)
- [Установка и обновление на сервере](#установка-и-обновление-на-сервере)
- [Переменные окружения](#переменные-окружения)
- [Яндекс ID](#яндекс-id)
- [VK ID](#vk-id)
- [ЮKassa](#юkassa)
- [База SQLite (коды доступа)](#база-sqlite-коды-доступа)
- [Сброс триала в приложении](#сброс-триала-в-приложении)
- [Новое приложение](#новое-приложение)

`docker-compose.yml` **не внутри** каталога проекта на сервере: он общий на весь стек
(Traefik, Portainer, Agronizer, …) и лежит **рядом** с папкой `agronizer/`.
В этом репозитории лежит копия того же файла — образец сервиса `agronizer`.

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
      pay/microgreens/
    platform/
      push/                     # FastAPI: статика + Web Push + OAuth + оплата
        main.py store.py auth.py access.py
        .env                    # секреты, не в git
        # data/ на сервере НЕ используется: SQLite/VAPID в томе agronizer_data
    scripts/
  portainer/
  uptime-kuma/
  …
```

В compose сервис `agronizer` смотрит сюда:

- `build: ./agronizer/platform/push` (Python / FastAPI, порт 3000)
- `./agronizer/site` → `/var/www`
- named volume `agronizer_data` → `/data` (SQLite, VAPID, подписки, пользователи; не в дереве репо)

`environment:` в compose **перекрывает** из `.env` пути и публичные URL
(`DATA_DIR`, `STATIC_DIR`, `PORT`, `SITE_URL`, `YOOKASSA_RETURN_URL`, OAuth redirect URI).
Секреты (`YOOKASSA_SECRET_KEY`, OAuth client secret, `SESSION_SECRET`) берутся из `env_file`.

## Структура репозитория

```
apps/
  apps.json                      # реестр приложений
  microgreens/                   # Flutter-проект
site/                            # статика для продакшена
platform/push/
  main.py                        # FastAPI: портал + PWA/APK + /push/ + оплата
  store.py                       # VAPID, подписки, расписание
  auth.py                        # Яндекс / VK вход
  access.py                      # SQLite кодов доступа
  .env.example                   # шаблон → скопировать в .env
  requirements.txt
  Dockerfile                     # в образ входят только *.py выше + requirements
scripts/
  apps.ps1                       # реестр и пути
  build_app.ps1                  # сборка одного приложения (APK и/или PWA)
  build_all.ps1                  # все приложения из apps.json
  build_microgreens_apk.ps1      # ярлык: только APK микрозелени
  build_microgreens_aab.ps1      # ярлык: App Bundle для Google Play
  build_microgreens_web.ps1      # ярлык: только PWA микрозелени
  create_android_keystore.ps1    # один раз: подпись release APK
  patch_pwa_sw.ps1               # внутренняя: SW после flutter build web
  run_local.ps1                  # локальный FastAPI на :3000
```

## Бэкенд (FastAPI)

Один сервис `platform/push` на все приложения: отдаёт `site/` и API `/push/`.
Flutter и PWA ходят на те же URL (`/push/api/vapid-public-key`, `subscribe`, `schedule`).
Данные живут в томе `agronizer_data` (`DATA_DIR=/data`). Rebuild образа и заливка кода их не затирают.
Локально (`run_local.ps1`) те же файлы в `platform/push/data/`.

| Что | Как |
|-----|-----|
| API | `https://agronizer.ru/push/` |
| VAPID | `/data/vapid.json` |
| Подписки | `/data/subscriptions.json`, `/data/schedules.json` |
| Пользователи | таблица `users` в SQLite/MySQL |
| Коды доступа | `/data/access.sqlite` |
| Клик по push | `url` из расписания, иначе `DEFAULT_APP_URL` |

| URL | Содержимое |
|-----|------------|
| `/` | портал |
| `/gate/microgreens/` | настройка Push (после иконки; обычная вкладка) |
| `/apps/microgreens/` | PWA |
| `/apps/microgreens/microgreens.apk` | APK |
| `/pay/microgreens/` | оплата доступа (нужен вход Яндекс/VK) |
| `/api/config` | публичная конфигурация (OAuth вкл/выкл, redirect URI, суммы) |
| `/health` | FastAPI |
| `/push/health` | Web Push |
| `/app/`, `/green_grow.apk` | редиректы → `/apps/microgreens/…` |

---

## Локальный запуск

Портал — `site/index.html`. Его нельзя открыть как файл: ссылки `/apps/microgreens/` работают только с HTTP-сервером.
Локально тот же FastAPI, что на проде. Нужен **Python 3.12+**. Сборка Flutter не нужна, если `site/apps/microgreens/` уже есть.

```powershell
cd c:\cursor\green
copy platform\push\.env.example platform\push\.env   # один раз, затем заполнить секреты
.\scripts\run_local.ps1
```

Скрипт создаст `platform/push/.venv` при необходимости, поставит зависимости и поднимет uvicorn
на **http://127.0.0.1:3000/**. `DATA_DIR` и `STATIC_DIR` он задаёт сам (локальные пути),
даже если в `.env` прописаны контейнерные `/data` и `/var/www`.

- http://localhost:3000/ — портал
- http://localhost:3000/apps/microgreens/ — PWA «Микрозелень»
- http://localhost:3000/apps/microgreens/?setup=1&fresh=1 — установка PWA
- http://localhost:3000/pay/microgreens/ — оплата
- http://localhost:3000/health — FastAPI
- http://localhost:3000/push/health — push
- http://localhost:3000/api/config — что реально включено (OAuth, redirect URI)

Если меняли Flutter-приложение, перед этим пересоберите PWA:

```powershell
.\scripts\build_app.ps1 -AppId microgreens -SkipApk
```

Вручную (без `run_local.ps1`):

```powershell
cd c:\cursor\green\platform\push
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
$env:STATIC_DIR = (Resolve-Path ..\..\site).Path
$env:DATA_DIR = Join-Path (Get-Location) "data"
.\.venv\Scripts\python -m uvicorn main:app --host 127.0.0.1 --port 3000 --reload --env-file .env
```

OAuth и ЮKassa с `localhost` работают только если в кабинетах прописаны **локальные** Callback/return URL
и те же значения стоят в локальном `.env`. Иначе кнопки входа ведут на прод-callback `agronizer.ru`.
HTTP-уведомления ЮKassa на `localhost` не доходят — после тестовой оплаты код может появиться
через `POST /api/pay/complete` (страница оплаты делает это сама, если вы вошли).

### Только UI Flutter (без портала)

Hot reload, без `site/index.html` и без `/push/`:

```powershell
cd c:\cursor\green\apps\microgreens
C:\src\flutter\bin\flutter.bat run -d chrome --web-port 8080 --no-web-resources-cdn
```

Смотрите окно Chrome, которое открыл Flutter. `--no-web-resources-cdn` нужен, иначе страница часто пустая.

---

## Сборка на ПК

Flutter на сервер не нужен. Скрипты читают `apps/apps.json` и кладут артефакты в `site/apps/<id>/`.

```powershell
cd c:\cursor\green

.\scripts\build_all.ps1
.\scripts\build_app.ps1 -AppId microgreens
.\scripts\build_app.ps1 -AppId microgreens -SkipApk   # только PWA
.\scripts\build_app.ps1 -AppId microgreens -SkipWeb   # только APK

# ярлыки для микрозелени:
.\scripts\build_microgreens_web.ps1
.\scripts\build_microgreens_apk.ps1
.\scripts\build_microgreens_aab.ps1   # App Bundle для Google Play
```

Release APK / AAB нужно подписывать своим keystore, не debug-ключом (иначе Play Protect пишет, что разработчик не подтверждён):

```powershell
.\scripts\create_android_keystore.ps1   # один раз; сохраните android/upload-keystore.jks и android/key.properties
.\scripts\build_microgreens_apk.ps1
.\scripts\build_microgreens_aab.ps1
```

Затем зарегистрируйте пакет `com.agronizer.greengrow` и SHA-256 сертификата в
[Android Developer Console](https://developer.android.com/developer-verification) или Google Play Console.

`build_all.ps1` собирает каждое приложение через `build_app.ps1`.

Docker-образ собирайте в **корне стека** (`docker compose build agronizer`), не из клона репо на ПК.
`-Docker` / `-Up` у `build_all.ps1` сработают, только если рядом найден `docker-compose.yml` стека.

---

## Установка и обновление на сервере

Корень стека = папка с `docker-compose.yml`. Рядом должна быть папка **`agronizer/`**.

### Первый раз

1. На сервере в корне стека уже должен быть сервис `agronizer` (см. `docker-compose.yml` в этом репо).
2. Скопируйте проект в `…/stack/agronizer/` (см. таблицу ниже). Flutter SDK и `apps/*/build` не нужны.
3. Создайте `agronizer/platform/push/.env` из `.env.example`, заполните секреты (OAuth, ЮKassa, `SESSION_SECRET`).
4. Соберите PWA/APK на ПК (`.\scripts\build_all.ps1`) и залейте `site/`.
5. Из **корня стека**: `docker compose build agronizer && docker compose up -d agronizer`.
6. DNS `agronizer.ru` / `www.agronizer.ru` должен смотреть на Traefik (уже в compose).

| С ПК (из репо) | На сервер |
|----------------|-----------|
| `site/` | `…/stack/agronizer/site/` |
| `platform/push/*.py`, `requirements.txt`, `Dockerfile` | `…/stack/agronizer/platform/push/` |
| `apps/apps.json` | `…/stack/agronizer/apps/apps.json` |
| `.env` | только на сервере, из `.env.example` |

`docker-compose.yml` уже лежит в `…/stack/` — его не кладут внутрь `agronizer/`.

**Не копировать:** Flutter SDK, `apps/*/build`, `platform/push/.venv`, `platform/push/__pycache__`, `platform/push/data/`
(на сервере данные в томе `agronizer_data`, не в репо), `platform/push/.env` с ПК (если в нём локальные пути/секреты).

Образ Docker копирует только `main.py`, `store.py`, `auth.py`, `access.py`. Новый `.py` файл без правки `Dockerfile` в контейнер не попадёт.

```powershell
# на ПК
cd c:\cursor\green
.\scripts\build_all.ps1

# статика
scp -r .\site user@SERVER:/path/to/stack/agronizer/

# код FastAPI (все четыре модуля + зависимости + Dockerfile)
scp .\platform\push\main.py `
    .\platform\push\store.py `
    .\platform\push\auth.py `
    .\platform\push\access.py `
    .\platform\push\requirements.txt `
    .\platform\push\Dockerfile `
    user@SERVER:/path/to/stack/agronizer/platform/push/
```

На сервере (из **корня стека**, не из `agronizer/`):

```bash
cd /path/to/stack

docker compose build agronizer
docker compose up -d agronizer
```

SQLite, VAPID, подписки лежат в named volume `agronizer_data` (`/data` в контейнере).
`docker compose build` / `up -d` том не пересоздаёт.

Если раньше данные были в bind `agronizer/platform/push/data`, один раз скопируйте их в том, иначе контейнер стартует с пустой БД:

```bash
docker compose stop agronizer
docker run --rm \
  -v "$PWD/agronizer/platform/push/data:/from:ro" \
  -v agronizer_data:/to \
  alpine cp -a /from/. /to/
docker compose up -d agronizer
```

Проверка:

```bash
curl -s https://agronizer.ru/health
curl -s https://agronizer.ru/push/health
curl -s https://agronizer.ru/api/config
```

- https://agronizer.ru/
- https://agronizer.ru/apps/microgreens/
- https://agronizer.ru/pay/microgreens/

### Обновления

**Только APK/PWA:** залить новый `agronizer/site/` →  
`docker compose restart agronizer`

**Код FastAPI** (`main.py`, `store.py`, `auth.py`, `access.py`, `requirements.txt`, `Dockerfile`): залить эти файлы →  
`docker compose build agronizer && docker compose up -d agronizer`  
Том `agronizer_data` при этом не трогается.

**Секреты / `.env`:** поправить `agronizer/platform/push/.env` на сервере →  
`docker compose up -d agronizer` (пересоздаст контейнер с новым `env_file`).

---

## Переменные окружения

Локально и на сервере значения берутся из `platform/push/.env` (в git не попадает).
В Docker `environment:` перекрывает из `.env` пути и публичные URL — см. таблицу.

| Переменная | Назначение | Compose перекрывает? |
|------------|------------|----------------------|
| `PORT=3000` | порт uvicorn (Traefik смотрит сюда) | да, `3000` |
| `STATIC_DIR` | корень статики | да, `/var/www` |
| `DATA_DIR` | SQLite, VAPID, подписки | да, `/data` |
| `VAPID_SUBJECT` | mailto для VAPID | да |
| `DEFAULT_APP_URL` | fallback URL в push | да, `/apps/microgreens/` |
| `SITE_URL` | публичный URL портала | да, `https://agronizer.ru` |
| `SESSION_SECRET` | подпись cookie сессии | нет |
| `PUSH_API_KEY` | опционально для `POST /push/api/send` | нет |
| `YOOKASSA_SHOP_ID` | shopId ЮKassa | нет |
| `YOOKASSA_SECRET_KEY` | секрет API ЮKassa (только сервер) | нет |
| `YOOKASSA_SUM` | сумма в рублях, по умолчанию `300` | нет |
| `YOOKASSA_RETURN_URL` | куда ЮKassa вернёт после оплаты | да, `https://agronizer.ru/` |
| `TRIAL_PERIOD` | дни демо с первого запуска, по умолчанию `7` | нет |
| `PAID_PERIOD` | месяцы платного доступа после оплаты, по умолчанию `12` | нет |
| `YANDEX_OAUTH_CLIENT_ID` / `YANDEX_OAUTH_CLIENT_SECRET` | вход через Яндекс ID | нет |
| `VK_OAUTH_CLIENT_ID` / `VK_OAUTH_CLIENT_SECRET` | вход через VK ID (`service_token`) | нет |
| `YANDEX_OAUTH_REDIRECT_URI` | Callback Яндекса, строго как в кабинете | да |
| `VK_OAUTH_REDIRECT_URI` | Callback VK, строго как в кабинете | да |

Проверить, что отдаёт сервер: `https://agronizer.ru/api/config`
(поля `oauthYandex` / `oauthVk` / `yandexRedirectUri` / `vkRedirectUri`).

Кнопки «Войти через Яндекс/VK» на портале появляются только если заполнены **оба** поля пары client id + secret.

---

## Яндекс ID

1. Создайте приложение на [oauth.yandex.ru](https://oauth.yandex.ru/).
2. Платформа: **Веб-сервисы**. Callback URL **точно**:

   `https://agronizer.ru/api/auth/oauth/yandex/callback`

   Без хвостового `/`, без `www`, если в compose указан `agronizer.ru`.
3. Доступ к **адресу электронной почты** (оплата и код привязаны к email).
4. В `platform/push/.env` на сервере:

   ```
   YANDEX_OAUTH_CLIENT_ID=…
   YANDEX_OAUTH_CLIENT_SECRET=…
   YANDEX_OAUTH_REDIRECT_URI=https://agronizer.ru/api/auth/oauth/yandex/callback
   ```

   Compose и так выставляет этот redirect URI; в кабинете он должен совпадать символ в символ.
5. `docker compose up -d agronizer`, затем `curl -s https://agronizer.ru/api/config` — `oauthYandex: true`.

Вход: `GET /api/auth/oauth/yandex/start`. Ошибка на портале: `/?oauth_error=yandex_…`.

---

## VK ID

1. Создайте приложение в [VK ID / id.vk.ru](https://id.vk.ru/about/business/go) (не старый vk.com/apps, если кабинет уже VK ID).
2. Доверенный redirect URL **точно**:

   `https://agronizer.ru/api/auth/oauth/vk/callback`
3. Нужен scope **email**. В `.env`:

   ```
   VK_OAUTH_CLIENT_ID=…
   VK_OAUTH_CLIENT_SECRET=…    # защищённый ключ / service_token из кабинета VK ID
   VK_OAUTH_REDIRECT_URI=https://agronizer.ru/api/auth/oauth/vk/callback
   ```

   Допустимо устаревшее имя `VK_OAUTH_SECRET_KEY` вместо `VK_OAUTH_CLIENT_SECRET`.
4. Пересоздайте контейнер и проверьте `oauthVk: true` в `/api/config`.

Вход: `GET /api/auth/oauth/vk/start` (PKCE + `id.vk.ru`). Без email оплата может не выдать код.

---

## ЮKassa

Оплата доступна только **после входа** (Яндекс или VK). Страница: `/pay/microgreens/`.
Приложение открывает ту же страницу по кнопке «купить доступ».

1. В [кабинете ЮKassa](https://yookassa.ru/) возьмите **shopId** и **секретный ключ** API v3
   (`test_…` для тестов, `live_…` для боя).
2. В `.env` на сервере:

   ```
   YOOKASSA_SHOP_ID=…
   YOOKASSA_SECRET_KEY=…
   YOOKASSA_SUM=300
   YOOKASSA_RETURN_URL=https://agronizer.ru/pay/microgreens/
   ```

   В текущем compose `YOOKASSA_RETURN_URL` принудительно `https://agronizer.ru/`
   (портал). Чтобы возвращать на страницу оплаты, поменяйте `environment:` у сервиса `agronizer`
   на `https://agronizer.ru/pay/microgreens/` и пересоздайте контейнер.
3. HTTP-уведомления в кабинете ЮKassa:

   - URL: `https://agronizer.ru/api/pay/notify`
   - события: **`payment.succeeded`** и желательно `payment.canceled`

   Без notify код всё равно может появиться, когда пользователь вернётся на сайт:
   страница дергает `POST /api/pay/complete`. Надёжный путь — webhook.
4. После `payment.succeeded` код пишется в SQLite `/data/access.sqlite` (том `agronizer_data`).
   Срок — `PAID_PERIOD` месяцев от покупки.

Поток: вход → `POST /api/pay/microgreens` → редирект на ЮKassa → notify/complete → код в кабинете и в приложении (активация).

---

## SMTP Яндекса

Сброс пароля (`POST /api/auth/password/forgot`) отправляет временный пароль через SMTP.
На проде сервис `agronizer` читает `platform/push/.env` через `env_file`.

Минимальная конфигурация:

```env
SMTP_HOST=smtp.yandex.ru
SMTP_PORT=587
SMTP_USER=agronizer@yandex.ru
SMTP_PASS=пароль_приложения_яндекса
SMTP_FROM=agronizer@yandex.ru
SMTP_TLS=1
```

Важно:

1. Для `SMTP_PASS` используйте **пароль приложения**, а не обычный пароль от почты.
2. `SMTP_USER` и `SMTP_FROM` лучше держать одинаковыми: адрес того же ящика Яндекса.
3. В настройках ящика Яндекса включите доступ почтовых клиентов:
   `Почта` → `Все настройки` → `Почтовые программы` → включить **IMAP**.
   POP3 не нужен.
4. После правки `.env` пересоздайте контейнер:

   ```bash
   docker compose up -d agronizer
   ```

Диагностика:

- проверить, какие SMTP-переменные реально видит контейнер:

  ```bash
  docker compose exec agronizer sh -lc 'env | grep "^SMTP_"'
  ```

- если в логах видно
  `535 5.7.8 Error: authentication failed: This user does not have access rights to this service`,
  это обычно значит, что для ящика не включён доступ почтовых клиентов/IMAP
  или пароль приложения создан не для того ящика, который указан в `SMTP_USER`.

---

## База SQLite (коды доступа)

Это **не триал**. Триал хранится только на устройстве. В SQLite — коды после оплаты и записи платежей.

| Где | Путь |
|-----|------|
| Локально | `platform/push/data/access.sqlite` |
| Прод, в контейнере | `/data/access.sqlite` |
| Прод, на диске | named volume `agronizer_data` |

Таблицы: `access_codes` (`code`, `purchased_at`, `expires_at`, `activated_at`, `activation_count`, `slug`, `user_id`, `payment_id`)
и `payments`. Даты — ISO UTC, например `2026-08-14T12:00:00+00:00`.

В образе **нет** утилиты `sqlite3`. Смотреть и чистить — через Python в контейнере.
Копировать файлы — через временный контейнер `alpine`. База в режиме WAL: копируйте при **остановленном** `agronizer`, иначе можно снять обрезанный файл.

### Скачать на ПК, поправить, залить обратно

На сервере, из корня стека:

```bash
cd /path/to/stack
docker compose stop agronizer

mkdir -p /tmp/agronizer-db
docker run --rm -v agronizer_data:/data -v /tmp/agronizer-db:/out alpine \
  sh -c 'cp -a /data/access.sqlite /data/access.sqlite-wal /data/access.sqlite-shm /out/ 2>/dev/null; true'

docker compose start agronizer
```

С ПК:

```powershell
scp user@SERVER:/tmp/agronizer-db/access.sqlite* C:\cursor\green\platform\push\data\
```

Откройте файл в [DB Browser for SQLite](https://sqlitebrowser.org/) (или `sqlite3`), сохраните и закройте редактор.

Заливка — снова стоп, **сначала бэкап**, потом замена. Старые `-wal`/`-shm` на томе удалите: иначе они перезапишут ваш файл.

```bash
cd /path/to/stack
docker compose stop agronizer

docker run --rm -v agronizer_data:/data alpine \
  cp -a /data/access.sqlite /data/access.sqlite.bak-$(date +%Y%m%d-%H%M)
```

```powershell
scp C:\cursor\green\platform\push\data\access.sqlite user@SERVER:/tmp/access.sqlite
```

```bash
docker run --rm -v agronizer_data:/data -v /tmp/access.sqlite:/in/access.sqlite:ro alpine \
  sh -c 'cp /in/access.sqlite /data/access.sqlite; rm -f /data/access.sqlite-wal /data/access.sqlite-shm'

docker compose start agronizer
```

Не копируйте обратно весь `/data`: рядом лежат `vapid.json`, `subscriptions.json`, `schedules.json`.

### Почистить базу на сервере

Строки удалить, файл и схему оставить:

```bash
cd /path/to/stack

docker compose exec agronizer python -c "
import sqlite3, time, shutil
from pathlib import Path
p = Path('/data/access.sqlite')
shutil.copy2(p, p.with_name(p.name + '.bak-' + time.strftime('%Y%m%d-%H%M')))
db = sqlite3.connect(p)
db.execute('DELETE FROM access_codes')
db.execute('DELETE FROM payments')
db.commit()
db.execute('VACUUM')
db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
db.close()
print('cleared', p)
"
```

Проверка:

```bash
docker compose exec agronizer python -c "
import sqlite3
db = sqlite3.connect('/data/access.sqlite')
db.row_factory = sqlite3.Row
for row in db.execute('SELECT id, email, code, expires_at FROM access_codes'):
    print(dict(row))
print('rows', db.execute('SELECT count(*) FROM access_codes').fetchone()[0])
"
```

Выданные коды перестанут активироваться. Триал в приложениях **не** сбросится.

Удалить файл целиком (схема создастся при следующем старте):

```bash
docker compose stop agronizer
docker run --rm -v agronizer_data:/data alpine \
  sh -c 'mv /data/access.sqlite /data/access.sqlite.bak; rm -f /data/access.sqlite-wal /data/access.sqlite-shm'
docker compose start agronizer
```

---

## Сброс триала в приложении

Триал считается локально с первого запуска (`TRIAL_PERIOD` дней, по умолчанию 7). На сервер дата не уходит.
Сдвиг часов устройства не продлевает срок (`lastSeen`).

Нужно стереть якоря:

- `access_first_start_at`, `access_first_start_ms`, `access_last_seen_ms`, `access_paid_expires_at`
- в PWA ещё cookie `agronizer_access_start`

**Android:** Настройки → Приложения → Микрозелень → Хранилище → **Очистить данные** (не только кэш).
Удаление APK обычно тоже сбрасывает; если Google Backup вернул настройки — снова очистить данные.

**PWA / браузер:** DevTools → Application → **Clear site data** (localStorage + cookies), либо вручную
cookie и ключи `flutter.access_*`. APK и PWA хранят триал отдельно.

---

## Новое приложение

1. Flutter в `apps/<id>/`
2. Запись в `apps/apps.json` (`flutterRoot`, `sitePath`, `baseHref`, `apkFile`)
3. `.\scripts\build_app.ps1 -AppId <id>`
4. Ссылка в `site/index.html`
5. В schedule Web Push — `url: "/apps/<id>/"`

---

## Микрозелень

[`apps/microgreens/README.md`](apps/microgreens/README.md)
