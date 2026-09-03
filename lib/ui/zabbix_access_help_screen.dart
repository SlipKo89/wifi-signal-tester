import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/link_service.dart';
import '../settings/settings_controller.dart';
import 'widgets/app_safe_area.dart';

const _allowedMethods = 'host.get\nitem.get\nhistory.get\ntrend.get';

class ZabbixAccessHelpScreen extends StatelessWidget {
  const ZabbixAccessHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t(
          'Zabbix read-only access',
          'Доступ Zabbix только для чтения',
        )),
      ),
      body: AppSafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoCard(
              icon: Icons.security_outlined,
              title: l.t('Recommended layout', 'Рекомендуемая схема'),
              body: l.t(
                'Create a separate service user. Give it Read access only to the host groups needed by the app, then let an administrator create an expiring API token for that user. Do not use a Super admin token.',
                'Создай отдельного сервисного пользователя. Дай ему только Read-доступ к нужным приложению группам узлов, затем администратор создаёт для него API-токен со сроком действия. Не используй токен Super admin.',
              ),
            ),
            const SizedBox(height: 12),
            _StepCard(
              number: 1,
              title: l.t('Create a user role', 'Создай роль пользователя'),
              body: l.t(
                'Users → User roles. User type: User. Enable API access. Choose an API method Allow list and add only the methods shown below. apiinfo.version is queried without authentication.',
                'Users → User roles. Тип пользователя: User. Включи доступ к API. Выбери Allow list для API-методов и добавь только методы ниже. apiinfo.version приложение запрашивает без авторизации.',
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: SelectableText(
                        _allowedMethods,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          height: 1.55,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l.t('Copy methods', 'Скопировать методы'),
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(text: _allowedMethods),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(l.t(
                            'API method list copied.',
                            'Список API-методов скопирован.',
                          )),
                        ));
                      },
                      icon: const Icon(Icons.copy_all_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _StepCard(
              number: 2,
              title: l.t('Grant host permissions', 'Выдай права на узлы'),
              body: l.t(
                'Add the user to a dedicated user group. In Host permissions, grant Read (not Read-write) only to the host groups whose metrics should be visible in the app.',
                'Добавь пользователя в отдельную группу. В Host permissions выдай Read, а не Read-write, только на те группы узлов, чьи метрики должны быть видны в приложении.',
              ),
            ),
            const SizedBox(height: 8),
            _StepCard(
              number: 3,
              title: l.t(
                  'Create the service user', 'Создай сервисного пользователя'),
              body: l.t(
                'Assign the role and user group created above. The app does not need administration, script execution, acknowledgement, configuration export or any write permission.',
                'Назначь созданные выше роль и группу. Приложению не нужны администрирование, запуск скриптов, подтверждение проблем, экспорт конфигурации и любые права записи.',
              ),
            ),
            const SizedBox(height: 8),
            _StepCard(
              number: 4,
              title: l.t('Create an API token', 'Создай API-токен'),
              body: l.t(
                'Users → API tokens. As an administrator, create an enabled token assigned to the service user, set an expiry date and copy its value immediately. The value is shown only once.',
                'Users → API tokens. От имени администратора создай включённый токен для сервисного пользователя, задай срок действия и сразу скопируй значение. Оно показывается только один раз.',
              ),
            ),
            const SizedBox(height: 8),
            _StepCard(
              number: 5,
              title: l.t('Paste it into the app', 'Вставь токен в приложение'),
              body: l.t(
                'Select HTTPS or HTTP, enter the frontend host/path and optional port. HTTPS is recommended. HTTP exposes the token in transit and is only suitable for a trusted LAN/VPN. The app stores the token in platform secure storage and never includes it in logs or support reports. Removing a profile deletes only the local copy; revoke the token in Zabbix separately.',
                'Выбери HTTPS или HTTP, укажи хост/путь веб-интерфейса и необязательный порт. Рекомендуется HTTPS. HTTP раскрывает токен по пути и подходит только для доверенной LAN/VPN. Приложение хранит токен в защищённом хранилище платформы и не добавляет его в логи или отчёты. Удаление профиля стирает только локальную копию — сам токен отзывается отдельно в Zabbix.',
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l.t(
                'Menu names differ slightly between Zabbix versions.',
                'Названия разделов могут немного отличаться между версиями Zabbix.',
              ),
              style: const TextStyle(fontSize: 11, color: Color(0xFF7D8590)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => openExternalLink(
                    context,
                    'https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/user_roles',
                  ),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: Text(l.t('User roles', 'Роли пользователей')),
                ),
                OutlinedButton.icon(
                  onPressed: () => openExternalLink(
                    context,
                    'https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/users/api_tokens',
                  ),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('API tokens'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF58A6FF)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(body,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFC9D1D9))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _StepCard extends StatelessWidget {
  final int number;
  final String title;
  final String body;

  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor:
                    const Color(0xFF58A6FF).withValues(alpha: 0.16),
                child: Text('$number',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF58A6FF))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(body,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFC9D1D9))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
