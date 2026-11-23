# tunnels

Менеджер именованных SSH-пробросов портов.

Установка: `../install.sh install tunnels` из папки проекта (или `./install.sh` в папке утилиты с флагом `--install`).

Новый пользовательский файл: `~/.local/bin/tunnels`. Настройки и состояние остаются в `~/.config/tunnels` и `~/.local/state/tunnels`.

Убедитесь, что `~/.local/bin` в `PATH`. Требуется установленный OpenSSH-клиент. Не добавляйте пользовательский конфиг и приватные ключи в Git.

Перед заменой существующей версии: `../install.sh check tunnels`, затем `../install.sh install tunnels --replace`.
