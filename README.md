# Ubuntu VPS Setup for AmneziaVPN

Скрипт подготовки Ubuntu 24.04 LTS к установке AmneziaVPN.

### Что делает
- Обновляет систему и включает автоматические обновления безопасности.
- Устанавливает Fail2ban для защиты SSH.
- Очищает кеш APT.
- Проверяет RAM, диск и виртуализацию, выводит предупреждения.

**Root:** требует права администратора, но не меняет пароль, пользователей и настройки SSH-доступа.

Не устанавливает AmneziaVPN, Docker и не изменяет firewall.

### Запуск

Скачай [prepare-amnezia-vps.sh](https://github.com/pushkinpushkin/prepare-vps/blob/main/prepare-amnezia-vps.sh) из репозитория или выполни на VPS:

```bash
curl -fsSLo prepare-amnezia-vps.sh https://raw.githubusercontent.com/pushkinpushkin/prepare-vps/main/prepare-amnezia-vps.sh
sudo bash prepare-amnezia-vps.sh
```

Перезагрузка не выполняется автоматически. При необходимости скрипт сообщит об этом.
