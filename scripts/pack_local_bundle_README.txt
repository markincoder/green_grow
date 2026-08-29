Agronizer - локальный запуск (без Flutter)
==========================================

Требования
----------
- Windows
- Python 3.12 или новее (python.org -> "Add python.exe to PATH")
- PowerShell

Запуск
------
1. Распакуйте этот архив в любую папку, например C:\agronizer
2. Откройте PowerShell в корне распакованной папки
   (там, где лежат папки site, platform, scripts)
3. Запустите (файл platform\push\.env уже внутри архива):

   .\scripts\run_local.ps1

4. Откройте в браузере:
   http://127.0.0.1:3000/                    - портал
   http://127.0.0.1:3000/apps/microgreens/   - приложение "Микрозелень"
   http://127.0.0.1:3000/health              - проверка API

Скрипт сам создаст platform\push\.venv и поставит зависимости.
Данные (SQLite, VAPID) появятся в platform\push\data\.

Остановка: Ctrl+C в окне PowerShell.

Замечания
---------
- В архиве лежит настоящий platform\push\.env с секретами.
  Не выкладывайте zip в открытый доступ и не оставляйте на чужом ПК.
- Вход Яндекс/VK и ЮKassa на localhost работают только если в .env
  и в кабинетах прописаны локальные callback URL. Для просмотра UI
  и PWA это не обязательно.
- Пересборка Flutter на этом ПК не нужна: PWA уже в site\apps\microgreens\.

Собрано: {{STAMP}}
