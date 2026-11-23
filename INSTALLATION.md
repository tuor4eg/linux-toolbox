# Установка

Общие скрипты ставят утилиты из этого репозитория на Ubuntu. Они не скачивают пакеты, не создают VPN-профили и не включают таймеры, пока это не указано отдельным флагом.

Назначение каждой утилиты и ежедневные команды: [README.md](README.md). Настройка с нуля, проверка и удаление: справочники [bypass](bypass/README.md), [tunnels](tunnels/README.md), [vpnctl](vpnctl/README.md), [work-vpn-audit](work-vpn-audit/README.md). Переустановка системы: [docs/recovery.md](docs/recovery.md).

Примеры ниже запускаются из корня репозитория.

## Что делают скрипты

`install.sh` в корне вызывает `scripts/install-tool.sh`. Такой же вход есть в каталоге каждой утилиты: `bypass/install.sh`, `tunnels/install.sh`, `vpnctl/install.sh`, `work-vpn-audit/install.sh`. Оба входа выполняют одну и ту же программу.

Из корня:

```bash
./install.sh list
./install.sh check all
./install.sh check bypass
./install.sh install tunnels
./install.sh install vpnctl --replace
./install.sh install work-vpn-audit --replace --enable-timer
```

Из каталога утилиты режим по умолчанию — проверка:

```bash
cd bypass
./install.sh
./install.sh --check
./install.sh --install
```

`list` печатает четыре имени: `bypass`, `tunnels`, `vpnctl`, `work-vpn-audit`.

`check` проверяет синтаксис Python через `ast.parse`, печатает путь назначения и не меняет систему. Обязательные команды: `python3`; дополнительно `ip` у `bypass`, `ssh` у `tunnels`, `nmcli`, `ip` и `ping` у `vpnctl`, `nmcli`, `ip` и `curl` у `work-vpn-audit`. Если хотя бы одной нет, `check` печатает `Ошибка: отсутствует обязательная команда` и завершается с кодом 1. Для `vpnctl` и `work-vpn-audit` отсутствие `/etc/vpnctl.json` на этапе `check` только сообщается: файл для проверки репозитория не обязателен.

`install` копирует исполняемый файл. Для `vpnctl` и `work-vpn-audit` также копирует unit-файлы из каталога `systemd/` репозитория и выполняет `systemctl daemon-reload`.

Неизвестный аргумент, неизвестное имя утилиты и `--enable-timer` у `bypass` или `tunnels` завершают скрипт с кодом 2. Сообщение для таймера: `У <утилита> нет таймера`.

## Куда ставятся файлы

| Утилита | Программа | systemd | sudo |
| --- | --- | --- | --- |
| tunnels | `~/.local/bin/tunnels` | нет | не используется |
| bypass | `/usr/local/bin/bypass` | нет | да |
| vpnctl | `/usr/local/bin/vpnctl` | `vpnctl.service`, `vpnctl.timer` в `/etc/systemd/system/` | да |
| work-vpn-audit | `/usr/local/bin/work-vpn-audit` | `work-vpn-audit.service`, `work-vpn-audit.timer` | да |

Права программы: `755`. Права unit-файлов: `644`, владелец `root:root`.

Каталог `~/.local/bin` должен быть в `PATH`, иначе оболочка не найдёт `tunnels`. В стандартном `~/.profile` Ubuntu этот каталог добавляется, если он уже существовал в момент входа. После первой установки откройте новую сессию или добавьте каталог в `PATH` текущей:

```bash
export PATH="$HOME/.local/bin:$PATH"
command -v tunnels
```

## Повторная установка и `--replace`

Если файл назначения уже есть, установка без `--replace` останавливается: `ОТКАЗ: <путь> уже существует`.

`--replace` разрешён для `tunnels`, `vpnctl`, `work-vpn-audit` и для `bypass` v2.

- `tunnels`: предыдущий файл копируется рядом как `~/.local/bin/tunnels.bak.ГГГГММДДЧЧММСС`. Конфиг и состояние не трогаются.
- `vpnctl`, `work-vpn-audit` и `bypass`: каталог резервной копии создаётся командой `mktemp -d` в `/var/backups/linux-toolbox-XXXXXXXX` только если уже есть программа или unit-файл, который предстоит заменить. Пустой каталог не создаётся. Туда копируются прежние файлы. Это копия перед заменой, не автоматический откат. Вернуть старые файлы можно только вручную из этого каталога.

`bypass --replace` срабатывает, только если в уже установленном файле есть строка `managed-routes.json`. Тогда заменяется программа, а маршруты, `/etc/bypass-routes.json`, политика и реестр не читаются и не меняются. Если этой строки нет, установка останавливается: `ОТКАЗ: установлен старый bypass. Требуется отдельная миграция маршрутов/правил.` Автоматической миграции v1 → v2 нет. Подробности в [bypass/README.md](bypass/README.md).

Замена `vpnctl` или `work-vpn-audit` при уже включённом таймере сразу подхватывается после `daemon-reload`. Следующий запуск таймера выполнит уже новую программу. Перед `--replace` у `vpnctl` остановите таймер, если не хотите автоматического `apply` в середине проверки. Команды остановки приведены в [vpnctl/README.md](vpnctl/README.md).

## Таймеры

Без `--enable-timer` установщик только копирует unit-файлы и перечитывает конфигурацию systemd. В конце он печатает команду включения.

Включать таймер имеет смысл после ручной проверки:

```bash
sudo vpnctl status
sudo vpnctl apply --dry-run
sudo systemctl enable --now vpnctl.timer
```

```bash
sudo work-vpn-audit audit
sudo work-vpn-audit history
sudo systemctl enable --now work-vpn-audit.timer
```

`--enable-timer` выполняет `systemctl enable --now` сразу, без проверки содержимого `/etc/vpnctl.json`. Для `vpnctl` это запускает периодический `vpnctl apply`, который уже может менять маршруты.

`vpnctl install-timer` — другая команда, уже у установленной утилиты. Она записывает unit-файлы текстом из самой программы и тоже сразу включает таймер. Сейчас этот текст совпадает с `vpnctl/systemd/`. Подробности и отличие от установщика репозитория: [vpnctl/README.md](vpnctl/README.md).

## Что установщик не создаёт

Эти файлы остаются локальными и в Git не коммитятся:

- `/etc/bypass-routes.json`, `/etc/bypass-policy.json`, `/var/lib/bypass/managed-routes.json`
- `/etc/vpnctl.json`
- `~/.config/tunnels/config.json` и `~/.local/state/tunnels/`
- `/var/lib/work-vpn-audit/history.sqlite3`
- ключи и `~/.ssh/config`
- подключения NetworkManager и файлы OpenVPN

Примеры без реальных адресов: [bypass/policy.example.json](bypass/policy.example.json) и [vpnctl/config.example.json](vpnctl/config.example.json).

`work-vpn-audit` читает тот же `/etc/vpnctl.json`, что и `vpnctl`. Установка любой из этих двух утилит останавливается, если файла нет, и не создаёт его, не меняет и не перезаписывает. Содержимое при этом не проверяется: перед таймером его по-прежнему нужно просмотреть вручную. Пока файла нет, ручной `audit` и таймер завершаются ошибкой, базу при этом не портят.

Установщик не удаляет утилиты. Порядок отключения описан в справочнике каждой утилиты.

## Зависимости пакетов

На Ubuntu набор команд, которыми утилиты пользуются:

```bash
sudo apt update
sudo apt install python3 iproute2 openssh-client network-manager network-manager-openvpn openvpn curl iputils-ping
```

Пакет `sqlite3` нужен только если хотите смотреть базу аудита или делать согласованную резервную копию командой `.backup`. Сама утилита пишет базу модулем Python и без CLI работает.

Эта команда `apt` ставит пакеты в систему. Установщик репозитория её не выполняет.
