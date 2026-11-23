# work-vpn-audit

Локальный журнал наблюдаемых внешних IP при активных рабочих VPN. Читает `/etc/vpnctl.json`; хранит SQLite в `/var/lib/work-vpn-audit/history.sqlite3`.

Проверка: `../install.sh check work-vpn-audit`. Установка: `../install.sh install work-vpn-audit`. Замена: `../install.sh install work-vpn-audit --replace` после проверки различий.

Таймер не включается автоматически. Проверка вручную: `sudo work-vpn-audit audit` и `sudo work-vpn-audit history --changes`. Только после неё: `sudo systemctl enable --now work-vpn-audit.timer`.

Записываемый IP подтверждён локальным проверочным запросом через выбранный интерфейс, но не серверными логами OpenVPN. Локальная SQLite-база и реальные настройки не должны попадать в Git.
