# Linux Toolbox

Личный набор утилит для Ubuntu: исключения из системной VPN-маршрутизации, SSH-пробросы портов, маршруты рабочего OpenVPN поверх Outline/Hiddify и локальный журнал наблюдаемых внешних IP.

Репозиторий рассчитан на одну машину с Ubuntu, systemd и NetworkManager. Это не универсальный пакет «для любого Linux» и не замена самих Outline, Hiddify или OpenVPN. Утилиты подстраивают маршруты и ведут записи вокруг уже установленного прокси и уже созданных подключнений NetworkManager.

Примеры адресов ниже и в остальных документах — документационные диапазоны RFC 5737 (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`) и частная сеть `10.0.0.0/24`. Подставляйте свои значения. Реальные UUID, пароли и локальные конфиги в Git не входят.

## Утилиты

| Утилита | Зачем |
| --- | --- |
| [bypass](bypass/README.md) | Отправляет выбранные домены, IP и подсети мимо системного VPN, через обычный шлюз. |
| [tunnels](tunnels/README.md) | Хранит и запускает именованные локальные SSH-пробросы портов. |
| [vpnctl](vpnctl/README.md) | Удерживает сервер и сети рабочего OpenVPN доступными через Outline/Hiddify. |
| [work-vpn-audit](work-vpn-audit/README.md) | Записывает, был ли рабочий VPN включён и какой внешний IPv4 наблюдался на пути к его серверу. |

Подробная установка общими скриптами: [INSTALLATION.md](INSTALLATION.md). Полная переустановка Ubuntu: [docs/recovery.md](docs/recovery.md).

## Быстрая установка

Проверка только читает исходники и сообщает, есть ли уже файлы на диске. Маршруты, VPN и systemd она не меняет.

```bash
git clone https://github.com/tuor4eg/linux-toolbox.git ~/pets/linux-toolbox
cd ~/pets/linux-toolbox
./install.sh list
./install.sh check all
```

Установка по отдельности. `tunnels` копируется в `~/.local/bin` без `sudo`. Остальные три утилиты ставятся в `/usr/local/bin` и запрашивают `sudo`.

```bash
./install.sh install tunnels
./install.sh install bypass
./install.sh install vpnctl
./install.sh install work-vpn-audit
```

Таймеры `vpnctl` и `work-vpn-audit` после этой команды не включаются. Сначала нужны локальный `/etc/vpnctl.json`, `sudo vpnctl status` и `sudo vpnctl apply --dry-run`. Включение описано в справочниках этих утилит.

Каталог `~/pets/linux-toolbox` в примерах — удобное место, не требование кода. Скрипты берут путь от своего расположения.

## Полезные команды

Диагностика, без смены маршрутов и служб:

```bash
sudo bypass list
tunnels status
sudo vpnctl status
sudo vpnctl apply --dry-run
sudo work-vpn-audit history --changes
systemctl list-timers vpnctl.timer work-vpn-audit.timer
```

Команды, которые меняют маршруты, конфигурацию или службы, собраны в справочнике каждой утилиты. С них не стоит начинать на новой машине.

## Системные требования

Проверялось как набор для Ubuntu с systemd. Нужны:

- Python 3. В тексте `vpnctl` указан Python 3.10 или новее. Модули ставятся из стандартной библиотеки, `pip` не используется.
- `ip` из iproute2 с поддержкой `ip -j` (JSON). Это есть в обычной Ubuntu.
- `sudo` для `bypass`, `vpnctl` и `work-vpn-audit`.
- OpenSSH-клиент (`ssh`) для `tunnels`.
- NetworkManager и `nmcli` для `vpnctl` и `work-vpn-audit`. Рабочий OpenVPN должен быть подключением NetworkManager типа `vpn`. На Ubuntu для этого обычно ставят `network-manager-openvpn` и `openvpn`.
- `curl` для пробы внешнего IP в `work-vpn-audit`.
- `ping` из iputils-ping для `vpnctl check`.
- systemd для таймеров `vpnctl` и `work-vpn-audit`.

Сам установщик пакеты не ставит и в сеть не ходит. `check` завершается с ненулевым кодом, если нет обязательной команды: `python3` для всех утилит, `ip` для `bypass`, `ssh` для `tunnels`, `nmcli`, `ip` и `ping` для `vpnctl`, `nmcli`, `ip` и `curl` для `work-vpn-audit`.

## Маршрутизация

`bypass` и `vpnctl` меняют таблицу маршрутов и правила `ip rule`. Ошибка в исключении или профиле может увести рабочую сеть мимо OpenVPN или, наоборот, оборвать доступ к ней.

Схема, на которую рассчитаны эти две утилиты: обычный default-маршрут остаётся в таблице `main`, а Outline/Hiddify забирает трафик правилами policy routing (утилиты знают таблицы `7113` для Outline и `2022` для Hiddify). Если единственный default в `main` уже смотрит в `tun` или другой туннель, `bypass` отказывается выбирать шлюз.

Правила `bypass` по умолчанию имеют priority `800`, правила сетей `vpnctl` — фиксированный priority `810`. Меньшее число ядро смотрит раньше, поэтому исключение `bypass` перекрывает правило рабочей сети.

Обе утилиты трогают только системную IPv4-маршрутизацию. SOCKS- или HTTP-прокси, включённый внутри браузера или другого приложения, они не переключают.

Перед первым `sudo vpnctl apply` смотрите вывод `sudo vpnctl apply --dry-run`. Перед включением таймера убедитесь, что сухой прогон печатает ожидаемые действия.

## Обновление репозитория

```bash
cd ~/pets/linux-toolbox
git pull
./install.sh check all
```

`git pull` не обновляет уже скопированные в систему программы. Дальше:

- `tunnels`, `vpnctl`, `work-vpn-audit`: `./install.sh install <утилита> --replace`
- `bypass` v2: `./install.sh install bypass --replace`. Флаг не заменяет копию без реестра `managed-routes.json` и не меняет маршруты. Миграция со старой версии описана в [bypass/README.md](bypass/README.md).

Если таймер `vpnctl` уже включён, замена файла сразу меняет то, что таймер будет выполнять. На время обновления его имеет смысл остановить, ещё раз посмотреть `--dry-run` и включить обратно. Команды есть в справочнике `vpnctl`.

Локальные конфиги, реестр маршрутов `bypass`, база аудита и `~/.ssh` при обновлении репозитория не изменяются. Их список для резервной копии: [docs/recovery.md](docs/recovery.md).
