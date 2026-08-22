# Микрозелень (`microgreens`)

Flutter-приложение Agronizer для выращивания микрозелени дома.

- **Главная** — обзор лотков и полив
- **База знаний** — виды микрозелени
- **Моя зелень** — посадки и прогресс
- **Напоминания** — локальные Push (Android/iOS) и Web Push (PWA)

Реестр: `apps/apps.json`. Сборка кладёт артефакты в `site/apps/microgreens/`; их отдаёт FastAPI (`platform/push`).

## Разработка

```powershell
cd c:\cursor\green\apps\microgreens
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat run
```

Только UI в Chrome (без портала и `/push/`):

```powershell
C:\src\flutter\bin\flutter.bat run -d chrome --web-port 8080 --no-web-resources-cdn
```

## Сборка в каталог сайта

```powershell
cd c:\cursor\green
.\scripts\build_app.ps1 -AppId microgreens
.\scripts\build_app.ps1 -AppId microgreens -SkipApk   # только PWA
.\scripts\build_app.ps1 -AppId microgreens -SkipWeb   # только APK

# ярлыки:
.\scripts\build_microgreens_web.ps1
.\scripts\build_microgreens_apk.ps1
.\scripts\build_microgreens_aab.ps1   # Google Play (.aab)
```

Локально проверить портал + PWA + push:

```powershell
cd c:\cursor\green
.\scripts\run_local.ps1
```

- PWA: http://localhost:3000/apps/microgreens/
- APK (после сборки): http://localhost:3000/apps/microgreens/microgreens.apk

Прод:

- PWA: `https://agronizer.ru/apps/microgreens/`
- APK: `https://agronizer.ru/apps/microgreens/microgreens.apk`
