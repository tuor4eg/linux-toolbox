# Восстановление компьютера

Пошаговая сборка утилит после полной переустановки Ubuntu. Сами Outline, Hiddify, подключения NetworkManager и ключи OpenVPN этот репозиторий не хранит. Их ставят и восстанавливают отдельно, затем в утилиты попадают уже новые UUID и локальные конфиги.

Общий обзор: [README.md](../README.md). Флаги установщика: [INSTALLATION.md](../INSTALLATION.md). Повседневные команды: [bypass](../bypass/README.md), [tunnels](../tunnels/README.md), [vpnctl](../vpnctl/README.md), [work-vpn-audit](../work-vpn-audit/README.md).

Каталог `~/pets/linux-toolbox` в командах можно заменить на любой другой. Скрипты ориентируются на своё расположение.

Примеры адресов — документационные. В восстановленные файлы попадут ваши настоящие UUID и префиксы из резервной копии, не из примеров репозитория.

## Что сохранить до переустановки

Этих файлов в Git нет намеренно. `git clone` их не вернёт. Скопируйте их на внешний диск или в другое хранилище, пока старая система ещё загружается.

| Файл | Зачем |
| --- | --- |
| `/etc/vpnctl.json` | Профили `vpnctl` и `work-vpn-audit`: имена, UUID, endpoint, сети. |
| `/etc/bypass-routes.json` | Список исключений `bypass`. |
| `/etc/bypass-policy.json` | Таблица, priority и защищённые сети `bypass`, если файл создавался. |
| `/var/lib/work-vpn-audit/history.sqlite3` | Вся история аудита. |
| `~/.config/tunnels/config.json` | Описания SSH-пробросов. |
| `~/.ssh/config` и ключи в `~/.ssh/` | Без них `tunnels start` не подключится. В репозиторий их не кладут. |

Реестр `/var/lib/bypass/managed-routes.json` на новую систему переносить не нужно. После чистой установки маршрутов в ядре ещё нет, и `sudo bypass restore` создаст реестр заново. Имеет смысл оставить копию реестра только как справку, что именно старая система считала своим.

Не стоит копировать как «настройки toolbox»:

- `/run/vpnctl-managed-rules.json` и `/run/lock/bypass.lock` — пропадают при перезагрузке и на новой системе бесполезны.
- Unit-файлы из `/etc/systemd/system/vpnctl.*` и `work-vpn-audit.*`, если вы их не правили. Штатные копии лежат в репозитории и ставятся установщиком. Если правили unit вручную, сохраните эти правки отдельно: `--replace` затрёт их файлами из Git.
- Базы `*.db` рядом с репозиторием, журналы `~/.local/state/tunnels/*.log`, резервные копии `tunnels.bak.*` и каталоги `/var/backups/linux-toolbox-*`. Журналы туннелей истории подключений не содержат. Каталог backup установщика — старые исполняемые файлы, не конфиги.

Подключения NetworkManager лежат вне этого проекта, часто в `/etc/NetworkManager/system-connections/`, и содержат секреты VPN. Решите сами, как вы их резервируете. В каталог `linux-toolbox` и в Git их не копируйте. После восстановления подключений UUID могут стать другими. Тогда их нужно будет заново прочитать через `nmcli` и вписать в восстановленный `/etc/vpnctl.json`.

Историю аудита лучше снимать согласованно. Остановка таймера меняет только расписание, не маршруты:

```bash
sudo systemctl stop work-vpn-audit.timer work-vpn-audit.service
sudo sqlite3 /var/lib/work-vpn-audit/history.sqlite3 \
  ".backup '/home/USER/backups/work-vpn-audit.sqlite3'"
sudo chown "$USER:$USER" /home/USER/backups/work-vpn-audit.sqlite3
sudo systemctl start work-vpn-audit.timer
```

Пакет `sqlite3` — это CLI. Если его нет, остановите таймер теми же двумя командами `systemctl` и скопируйте файл, пока служба не запущена:

```bash
sudo cp -a /var/lib/work-vpn-audit/history.sqlite3 /home/USER/backups/work-vpn-audit.sqlite3
sudo chown "$USER:$USER" /home/USER/backups/work-vpn-audit.sqlite3
```

Последний `systemctl start` нужен, только если таймер до копирования был включён. Проверка без изменения маршрутов: `systemctl is-enabled work-vpn-audit.timer`. Если ответ `disabled`, таймер обратно не запускайте.

Остальные файлы читаются и копируются обычным `sudo cp -a` в ваш каталог резервных копий. Команды `cp` маршруты не меняют.

## 1. Пакеты

На новой Ubuntu. Команда ставит пакеты:

```bash
sudo apt update
sudo apt install git python3 iproute2 openssh-client \
  network-manager network-manager-openvpn openvpn \
  curl iputils-ping sqlite3
```

`sqlite3` нужен для проверки и переноса истории. Сам аудит пишет базу модулем Python и без CLI работает. NetworkManager на настольной Ubuntu обычно уже есть. Другие дистрибутивы этими шагами не покрываются.

Проверка без изменения маршрутов:

```bash
python3 --version
command -v ip nmcli ssh curl ping git
```

Для `vpnctl` нужна версия Python 3.10 или новее.

## 2. Репозиторий

```bash
git clone https://github.com/tuor4eg/linux-toolbox.git ~/pets/linux-toolbox
cd ~/pets/linux-toolbox
./install.sh list
./install.sh check all
```

`check` печатает `Проверка завершена. Система не изменена.` Если нет `python3`, `ip`, `nmcli`, `ssh`, `curl` или `ping` для той утилиты, которой команда нужна, код выхода ненулевой. Вернитесь к установке пакетов. Отсутствие `/etc/vpnctl.json` на этом шаге `check` не валит: файл появится следующим шагом, а `install` для `vpnctl` и `work-vpn-audit` без него остановится и сам файл не создаст.

Адрес выше — HTTPS того репозитория, чей `origin` в рабочей копии указан как `git@github.com:tuor4eg/linux-toolbox.git`. Если ключ GitHub уже есть, можно клонировать по SSH.

## 3. Конфиги, которые должны появиться до таймеров

Таймеры пока не включайте.

`vpnctl` и будущий аудит. Файл из резервной копии, права `600`:

```bash
sudo install -m 600 -o root -g root \
  /путь/к/копии/vpnctl.json /etc/vpnctl.json
```

Если копии не было, начните с примера и заполните его после того, как заново создадите VPN в NetworkManager:

```bash
cd ~/pets/linux-toolbox
sudo install -m 600 -o root -g root \
  vpnctl/config.example.json /etc/vpnctl.json
sudoedit /etc/vpnctl.json
```

UUID после новой установки подключений:

```bash
nmcli -t -f NAME,UUID,TYPE connection show
```

Впишите актуальные UUID. Старые значения из копии годятся только если вы восстановили те же подключения NetworkManager и UUID не изменились.

Политика `bypass`, если она была:

```bash
sudo install -m 600 -o root -g root \
  /путь/к/копии/bypass-policy.json /etc/bypass-policy.json
```

Без копии можно положить пример и отредактировать защищённые сети до первого `bypass add`:

```bash
sudo install -m 600 -o root -g root \
  ~/pets/linux-toolbox/bypass/policy.example.json /etc/bypass-policy.json
sudoedit /etc/bypass-policy.json
```

Исключения `bypass` верните файлом, но реестр и маршруты ещё не создавайте вручную. Это сделает `restore` после установки программы:

```bash
sudo install -m 600 -o root -g root \
  /путь/к/копии/bypass-routes.json /etc/bypass-routes.json
```

Конфиг туннелей можно положить до или после установки программы. Каталоги создайте со своими правами, без `sudo`:

```bash
mkdir -p ~/.config/tunnels
install -m 600 /путь/к/копии/tunnels-config.json ~/.config/tunnels/config.json
```

Ключи SSH верните в `~/.ssh` так, как рекомендует OpenSSH: каталог `700`, закрытый ключ `600`. Проверьте алиасы, на которые ссылается `ssh` в конфиге туннелей:

```bash
ssh -G db-jump | grep -E '^(hostname|user|identityfile) '
```

`ssh -G` печатает разбор конфигурации и не открывает сессию. Имя `db-jump` замените на алиас из своего конфига. Строки `hostname`, `user` и `identityfile` должны указывать на тот сервер и ключ, с которыми туннель будет ходить: `tunnels` передаёт в `ssh` только этот алиас.

## 4. Установка выбранных утилит

Ставьте только то, чем пользуетесь. Каждая команда `install` уже меняет систему: копирует программу и для двух утилит ещё unit-файлы. Таймеры из-за этих четырёх команд не включаются.

```bash
cd ~/pets/linux-toolbox
./install.sh install tunnels
./install.sh install bypass
./install.sh install vpnctl
./install.sh install work-vpn-audit
```

`tunnels` окажется в `~/.local/bin`. Если оболочка его не видит:

```bash
export PATH="$HOME/.local/bin:$PATH"
command -v tunnels
```

На чистой системе `/usr/local/bin/bypass` ещё нет, поэтому отказ про старый bypass не ожидается. Если он появился, в файле нет `managed-routes.json`: `--replace` такой файл не заменит и маршруты не тронет. Не затирайте его копированием, пока не снимете старые маршруты. Порядок описан в [bypass/README.md](../bypass/README.md). Уже установленная v2 обновляется командой `./install.sh install bypass --replace`.

## 5. Маршруты bypass

К этому моменту обычная сеть уже должна иметь один IPv4 default в таблице `main` через Wi-Fi или Ethernet, а не через `tun`. Проверка без изменений:

```bash
ip -j -4 route show table main default
```

Применение исключений меняет маршруты и создаёт реестр:

```bash
sudo bypass restore
sudo bypass list
```

Дальше диагностика:

```bash
ip -4 rule show
ip -4 route show table main
ip -4 route show table 7113
```

Если в политике другой `outline_table`, подставьте его вместо `7113`. У своих адресов должны появиться правило priority из политики (по умолчанию `800`) и маршрут через шлюз из default. Ошибки `чужой/унаследованный маршрут` на чистой системе быть не должно: ядро ещё не содержит старых исключений. Если она появилась, в таблице уже есть маршрут, который `bypass` не создавал. Его нельзя захватывать автоматически. Разбор: [bypass/README.md](../bypass/README.md).

Старый реестр на этот шаг не подкладывайте.

## 6. vpnctl и таймер

Пока Outline или Hiddify и рабочий OpenVPN не запущены, `status` покажет прокси «не обнаружен» и профили отключёнными. Это ещё не проверка маршрутов. Включите прокси и рабочий VPN так, как делали раньше, затем:

```bash
sudo vpnctl status
sudo vpnctl apply --dry-run
```

Обе команды маршруты не меняют. В `--dry-run` не должно быть неожиданного `ip route del`. Когда план совпадает с тем, что нужно, один боевой проход и только потом таймер:

```bash
sudo vpnctl apply
sudo systemctl enable --now vpnctl.timer
systemctl list-timers vpnctl.timer
```

`enable` включает периодический `vpnctl apply` примерно каждые 15 секунд. Пока сухой прогон не посмотрели, таймер не включайте и не передавайте установщику `--enable-timer`.

Если endpoint в `status` пустой или команда просит задать IPv4, запишите адрес. Это меняет только JSON:

```bash
sudo vpnctl endpoint work 198.51.100.20
```

Имя профиля и адрес возьмите из своего конфига. `auto` вернёт определение из процесса: `sudo vpnctl endpoint work auto`.

## 7. SSH-пробросы

Программа и `~/.config/tunnels/config.json` уже на месте, ключи тоже. Запуск создаёт процессы `ssh`:

```bash
tunnels status
tunnels start all
tunnels status
```

Если конфига не было, создайте туннели заново по [tunnels/README.md](../tunnels/README.md). Systemd-юнита нет: после следующей загрузки снова нужен `tunnels start all`, либо ваш собственный автозапуск, которого в репозитории нет.

PID и журналы в `~/.local/state/tunnels/` со старой машины не восстанавливайте. Это состояние процессов, которых на новой системе нет.

Проверка одного туннеля без второй копии процесса — статус и локальный порт:

```bash
tunnels status
ss -ltn 'sport = :5432'
```

Порт замените на `local_port` из конфига.

## 8. История аудита

Каталог и файл должны принадлежать root ещё до первого запуска таймера. Иначе таймер успеет создать пустую базу, и копия ляжет рядом с ней, а не вместо неё.

Если таймер вы ещё не включали:

```bash
sudo install -d -m 700 -o root -g root /var/lib/work-vpn-audit
sudo install -m 600 -o root -g root \
  /путь/к/копии/work-vpn-audit.sqlite3 \
  /var/lib/work-vpn-audit/history.sqlite3
```

Проверка чтения:

```bash
sudo work-vpn-audit history --days 3650 --limit 5
sudo sqlite3 /var/lib/work-vpn-audit/history.sqlite3 \
  'SELECT COUNT(*) FROM observations;'
```

Один новый замер дописывает строки, старые не стирает:

```bash
sudo work-vpn-audit audit
sudo work-vpn-audit history --days 1 --limit 20
```

Затем таймер:

```bash
sudo systemctl enable --now work-vpn-audit.timer
systemctl list-timers work-vpn-audit.timer
```

Если пустая база уже успела создаться, остановите таймер, замените файл теми же командами `install` и включите таймер снова:

```bash
sudo systemctl disable --now work-vpn-audit.timer
sudo install -m 600 -o root -g root \
  /путь/к/копии/work-vpn-audit.sqlite3 \
  /var/lib/work-vpn-audit/history.sqlite3
sudo systemctl enable --now work-vpn-audit.timer
```

Без резервной копии история начинается с нуля первым `sudo work-vpn-audit audit`. Восстановить её из Git нельзя.

## 9. Проверка маршрутизации

Набор ниже только читает состояние. Адреса замените на endpoint и исключение со своей машины.

```bash
ip -j -4 route show table main default
ip -4 rule show
ip -4 route show table 2022
ip -4 route show table 7113
sudo bypass list
sudo vpnctl status
sudo vpnctl apply --dry-run
ip -4 route get 198.51.100.20
ip -4 route get 203.0.113.10
```

Что считать собранной схемой:

- В `main` один понятный default через обычный интерфейс.
- `vpnctl status` видит `hiddify` или `outline`.
- Маршрут до сервера OpenVPN идёт через интерфейс этого прокси.
- Для сетей из `expected_networks` маршрут идёт через `tunN`, а в правилах есть priority `810`, если боевой `apply` уже выполнялся.
- Исключение `bypass` в `ip route get` идёт через обычный шлюз, а в правилах есть его priority (`800`, если политику не меняли).
- `--dry-run` печатает `без изменений` или только те правила, которые вы готовы отдать таймеру.

`sudo vpnctl check 203.0.113.10` дополнительно шлёт ping и маршруты не переписывает.

## Контрольный список

Отмечайте по факту, не включая лишние таймеры заранее.

- Пакеты стоят: `python3`, `ip`, `nmcli`, `ssh`, `curl`, `ping`.
- Репозиторий склонирован, `./install.sh check all` завершился без синтаксической ошибки.
- `/etc/vpnctl.json` на месте, режим `600`, UUID совпадают с `nmcli`.
- Рабочий VPN — подключение NetworkManager типа `vpn`, Outline или Hiddify включены в системном режиме.
- `sudo vpnctl status` показывает нужный прокси и endpoint.
- `sudo vpnctl apply --dry-run` не содержит лишнего удаления маршрута.
- Боевой `sudo vpnctl apply` выполнен осознанно.
- `vpnctl.timer` включён только после этого: `systemctl list-timers vpnctl.timer`.
- Политика `bypass` содержит рабочие сети и адрес сервера OpenVPN, если их нельзя пускать мимо VPN.
- `/etc/bypass-routes.json` восстановлен, `sudo bypass restore` напечатал `OK: restore`.
- `ip rule` и `ip route get` по одному исключению показывают обычный шлюз.
- `~/.ssh` и `~/.config/tunnels/config.json` на месте, `tunnels start all` поднимает нужные имена, `ss` видит локальные порты.
- `tunnels` не запускался через `sudo`.
- База аудита либо восстановлена командой `install` в `/var/lib/work-vpn-audit/history.sqlite3` до включения таймера, либо вы согласны начать историю заново.
- `sudo work-vpn-audit audit` дописывает строку, `history` её показывает.
- `work-vpn-audit.timer` включён, если нужен минутный опрос.
- Свежая резервная копия снова включает `/etc/vpnctl.json`, исключения и политику `bypass`, конфиг туннелей, `~/.ssh` и базу аудита. Реестр `bypass` на чистой системе создаётся заново и в обязательный набор не входит.
