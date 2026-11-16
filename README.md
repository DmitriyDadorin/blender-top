# Palmshift — побережье, город и пустыня

Игра с двумя автомобилями и четырьмя картами: пустыня Невады, дневной и ночной Pacific City и летний курорт Palm Bay. В проекте есть заезды на время, гараж, автомобильный свет, городской звук и морское побережье с кораблями.

Название Palmshift объединяет пальмы и переключение передач. При запуске показывается собственная закатная иллюстрация; название отображается в окне, гараже и установщике. Прежнее приложение называлось Drive: после установки Palmshift его можно удалить, рекорды и настройки используют ту же папку профиля.

Для запуска из исходников нужен **Godot 4.7**. Blender нужен для редактирования исходных моделей; готовые GLB уже входят в проект.

## Готовое приложение для Mac

[Скачать Palmshift.dmg для Mac — Apple Silicon](https://github.com/DmitriyDadorin/blender-top/releases/download/v0.1.3-macos-arm64/Palmshift-macOS-arm64-0.1.3.dmg) · [Описание сборки и контрольная сумма](https://github.com/DmitriyDadorin/blender-top/releases/tag/v0.1.3-macos-arm64)

Откройте DMG, перетащите `Palmshift` на папку `Applications` справа, дождитесь копирования и откройте игру из «Программ». После установки образ можно извлечь.

**Первый запуск:** эта сборка не нотарифицирована Apple. Если macOS пишет, что не может проверить Palmshift, закройте предупреждение, откройте «Системные настройки → Конфиденциальность и безопасность» и разрешите Palmshift через «Открыть всё равно». DMG не отменяет эту проверку. [Инструкция Apple](https://support.apple.com/102445). Подробная инструкция также находится внутри образа в `Установка.txt`.

Сборка для Apple Silicon (M1 и новее), **macOS 13+**: `Palmshift.app`, DMG и ZIP создаются в `build/macos-arm64/`. В приложении все четыре карты и обе машины. Для запуска готовой сборки редакторы Godot и Blender не требуются.

Чтобы пересобрать приложение на Mac, установите экспортные шаблоны **Godot 4.7.2** через `Editor → Manage Export Templates` и выполните из корня репозитория:

```sh
python3 -m venv build/macos-tools
build/macos-tools/bin/python -m pip install -r godot-car/tools/requirements-macos.txt
build/macos-tools/bin/python godot-car/tools/build_macos.py --dmg
```

Пресет `macOS Apple Silicon` собирает ARM64 release, исключает инструменты и исходные записи звука. Скрипт добавляет лицензии, подписывает приложение локальной ad-hoc подписью, проверяет архитектуру и запуск всех карт, создаёт ZIP, DMG и SHA-256. Для оформления образа используются `dmgbuild` и Swift из Command Line Tools. Игровой профиль сохраняется по прежнему пути.

Готовый образ можно повторно собрать без экспорта игры: `build/macos-tools/bin/python godot-car/tools/package_macos_dmg.py`. Сборки распространяются через GitHub Releases вне App Store, каталог `build/` исключён из Git. Для запуска без предупреждения об неизвестном разработчике нужны подпись Developer ID и нотарификация Apple.

## Скачать и запустить исходники

Установите Git и [Git LFS](https://git-lfs.com/), затем выполните:

```sh
git lfs install
git clone https://github.com/DmitriyDadorin/blender-top.git
cd blender-top
git lfs pull
```

Откройте `godot-car/project.godot` в Godot и нажмите **F5**. Игра начнётся с выбора машины и карты.

## Файлы проекта

- `godot-car/` — сцены, код, модели, текстуры, звуки и проверки игры.
- `*.blend` в корне — исходники автомобилей, города и пустынных объектов.
- `.gitattributes` — правила Git LFS для моделей `.blend` и `.glb`.

После изменения моделей используйте обычные `git add`, `git commit` и `git push`: Git LFS обрабатывает их автоматически.

Управление, устройство сцен и команды проверок описаны в [документации игры](godot-car/README.md). Авторы и лицензии звуков перечислены в [audio/CREDITS.md](godot-car/audio/CREDITS.md).
