# vpnctl

Маршруты рабочего OpenVPN поверх Outline/Hiddify на конкретной Linux-системе.

`vpnctl` использует конфигурацию `/etc/vpnctl.json`, которая должна быть подготовлена локально. Репозиторий содержит `config.example.json`, а не настоящие UUID, IP или подсети.

Проверка: `../install.sh check vpnctl`. Установка нового экземпляра: `../install.sh install vpnctl`. Замена: `../install.sh install vpnctl --replace` только после проверки различий. `vpnctl.timer` не включается автоматически.

После установки сначала проверить `sudo vpnctl status`, затем `sudo vpnctl apply --dry-run`; только после этого решать, включать ли `vpnctl.timer`. Утилита использует Linux policy routing и может влиять на доступность рабочих сетей.
