# Zabbix read-only user / Пользователь Zabbix только для чтения

> Wi-Fi Signal Tester accepts an existing API token. It never creates users,
> tokens, hosts, items or acknowledgements in Zabbix.
>
> Wi-Fi Signal Tester принимает готовый API-токен. Приложение не создаёт в
> Zabbix пользователей, токены, узлы, элементы данных или подтверждения проблем.

## Recommended permissions / Рекомендуемые права

Create a dedicated service user instead of using an Admin or Super admin token.
The exact menu names can differ slightly between supported Zabbix releases.

Создай отдельного сервисного пользователя вместо токена Admin или Super admin.
Названия разделов могут немного отличаться между поддерживаемыми версиями
Zabbix.

1. **Users → User roles**: create a role with user type **User** and enable API
   access. Set the API method rule to **Allow list** with only:

   **Users → User roles**: создай роль типа **User**, включи доступ к API и
   задай для API-методов **Allow list** только из:

   ```text
   host.get
   item.get
   history.get
   trend.get
   ```

   `apiinfo.version` is queried without authentication. The app contains no
   generic JSON-RPC dispatcher and no create/update/delete/acknowledge call.

   `apiinfo.version` запрашивается без авторизации. В приложении нет публичного
   универсального JSON-RPC-метода и нет вызовов create/update/delete/acknowledge.

2. Create a dedicated **user group**. Under Host permissions grant **Read**, not
   Read-write, only to the host groups whose metrics should appear in the app.

   Создай отдельную **группу пользователей**. В Host permissions выдай **Read**,
   а не Read-write, только на нужные приложению группы узлов.

3. Create the service user and assign that role and group. It does not need
   script execution, event acknowledgement, administration or configuration
   export permissions.

   Создай сервисного пользователя и назначь ему эту роль и группу. Ему не нужны
   запуск скриптов, подтверждение событий, администрирование или экспорт
   конфигурации.

4. As an administrator open **Users → API tokens**, create an enabled token
   assigned to this service user, set an expiry date and copy the value at once.
   Zabbix displays the authorization string only once.

   От имени администратора открой **Users → API tokens**, создай включённый
   токен для сервисного пользователя, задай срок действия и сразу скопируй
   значение. Zabbix показывает строку авторизации только один раз.

5. In the app open **⋮ → Zabbix history** or **Settings → Integrations →
   Zabbix**, select HTTPS/HTTP, enter the host/path and optional port, then paste
   the token.

   В приложении открой **⋮ → История из Zabbix** или **Настройки → Интеграции →
   Zabbix**, выбери HTTPS/HTTP, укажи хост/путь и необязательный порт, затем
   вставь токен.

## Security details / Детали безопасности

- The token is stored in platform secure storage and is never written to
  SharedPreferences, measurement databases, application logs or support ZIPs.
- Removing a profile deletes only the app's local token copy. Revoke the token
  separately in Zabbix when it is no longer needed or the device is lost.
- HTTPS is the default and requires a trusted certificate. The app does not
  silently accept an invalid or self-signed Zabbix certificate. Explicit HTTP
  has no encryption and exposes the token/metrics in transit; use it only on a
  trusted LAN or through a VPN.
- Zabbix 5.4/6.0-compatible APIs use the JSON-RPC `auth` property; newer
  supported APIs use the Bearer header. The app detects the API version before
  the first authenticated read.

- Токен хранится в защищённом хранилище платформы и не попадает в
  SharedPreferences, базы замеров, журналы приложения или ZIP в поддержку.
- Удаление профиля стирает только локальную копию. Если токен больше не нужен
  или устройство потеряно, отдельно отзови его в Zabbix.
- HTTPS используется по умолчанию и требует доверенного сертификата. Приложение
  не принимает молча неверный или самоподписанный сертификат Zabbix. Явно
  выбранный HTTP не шифрует токен и метрики; используй его только в доверенной
  LAN или через VPN.
- Для API, совместимых с Zabbix 5.4/6.0, используется JSON-RPC-поле `auth`, для
  новых поддерживаемых API — Bearer-заголовок. Версия определяется до первого
  авторизованного чтения.

Official documentation / Официальная документация:

- [Zabbix API](https://www.zabbix.com/documentation/current/en/manual/api)
- [User roles](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/user_roles)
- [API tokens](https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/api_tokens)
- [`history.get`](https://www.zabbix.com/documentation/current/en/manual/api/reference/history/get)
- [`trend.get`](https://www.zabbix.com/documentation/current/en/manual/api/reference/trend/get)
