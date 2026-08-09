# Микрозелень (Green Grow)

Flutter-приложение для выращивания микрозелени дома.

## Возможности

- **Главная** — обзор лотков и посадки, которым нужен полив
- **Справочник** — виды микрозелени с фильтрами и поиском
- **Моя зелень** — посадки, прогресс роста, отметка полива
- **Контакты** — связь с нами (скоро)
- Данные сада сохраняются локально через `shared_preferences`

## Запуск

Flutter SDK уже можно использовать из `C:\src\flutter` (добавьте `C:\src\flutter\bin` в PATH).

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
cd c:\cursor\green
flutter pub get
flutter run -d windows
# или: flutter run -d chrome
```

## Сборка веб-версии

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
cd c:\cursor\green
flutter build web --release
```

Результат: `build\web\` (откройте через любой статический хостинг или локальный сервер).

Для отладки в браузере без сборки:

```powershell
flutter run -d chrome --web-port 8080
```

## Сборка APK для телефона (ARM64)

Собирайте **раздельные APK по ABI** — для телефона нужен именно `arm64-v8a`.
Флаг `--target-platform android-arm64` без `--split-per-abi` даёт общий `app-release.apk`
(несколько архитектур внутри); на части устройств он может не ставиться.

```powershell
$env:Path = "C:\src\flutter\bin;" + $env:Path
cd c:\cursor\green

# лучше очистить старые артефакты, чтобы не перепутать даты
Remove-Item -Recurse -Force build\app\outputs\flutter-apk -ErrorAction SilentlyContinue

flutter build apk --release --split-per-abi
```

Нужный файл после сборки:

- `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`

Скопируйте в корень как `green_grow.apk`:

```powershell
Copy-Item build\app\outputs\flutter-apk\app-arm64-v8a-release.apk .\green_grow.apk -Force
```

Проверка перед установкой:

```powershell
# подпись должна быть Valid / Verifies
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0\apksigner.bat" verify --verbose .\green_grow.apk
```

Установка на телефон:

1. Удалите старую «Микрозелень», если уже стояла (иначе возможен конфликт подписи).
2. Скопируйте `green_grow.apk` на телефон и откройте его  
   или по USB:

```powershell
adb install -r green_grow.apk
```

Не используйте для телефона файлы `app-armeabi-v7a-release.apk` и `app-x86_64-release.apk`
(это другие архитектуры; x86_64 — для эмулятора).
