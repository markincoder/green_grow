# Микрозелень (`microgreens`)

Flutter-приложение Agronizer для выращивания микрозелени дома.

- **Главная** — обзор лотков и полив
- **База знаний** — виды микрозелени
- **Моя зелень** — посадки и прогресс
- **Напоминания** — локальные Push (Android/iOS) и Web Push (PWA)

## Разработка

```powershell
cd c:\cursor\green\apps\microgreens
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat run
```

Сборка в каталог сайта:

```powershell
cd c:\cursor\green
.\scripts\build_app.ps1 -AppId microgreens
```

PWA: `https://agronizer.ru/apps/microgreens/`  
APK: `https://agronizer.ru/apps/microgreens/microgreens.apk`
