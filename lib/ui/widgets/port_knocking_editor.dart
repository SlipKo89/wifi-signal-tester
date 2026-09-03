import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../mikrotik/port_knocking.dart';
import '../theme.dart';

/// Advanced, opt-in editor for a router's TCP/UDP port-knocking sequence.
/// Ports are concealed by default and the parent stores the resulting value
/// only as part of its secure router profile.
class PortKnockingEditor extends StatefulWidget {
  final PortKnockConfig value;
  final L10n l;
  final bool enabled;
  final bool requiresExplicitTransport;
  final ValueChanged<PortKnockConfig> onChanged;

  const PortKnockingEditor({
    super.key,
    required this.value,
    required this.l,
    required this.onChanged,
    this.enabled = true,
    this.requiresExplicitTransport = false,
  });

  @override
  State<PortKnockingEditor> createState() => _PortKnockingEditorState();
}

class _PortKnockingEditorState extends State<PortKnockingEditor> {
  bool _showPorts = false;

  @override
  Widget build(BuildContext context) {
    final config = widget.value;
    final l = widget.l;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: config.enabled,
              onChanged: widget.enabled
                  ? (value) => widget.onChanged(config.copyWith(enabled: value))
                  : null,
              secondary: const Icon(Icons.vpn_key_outlined),
              title: Text(l.t('Port knocking (advanced)',
                  'Port knocking (расширенная настройка)')),
              subtitle: Text(l.t(
                'Open the selected management service with a fixed TCP/UDP sequence.',
                'Открыть выбранный сервис управления фиксированной TCP/UDP-последовательностью.',
              )),
            ),
          ),
          if (config.enabled) ...[
            Text(
              l.t(
                'The app sends only the packets listed here, before connecting and once after a network disconnect. It does not configure RouterOS. Firewall rules may temporarily add this device to a dynamic address list.',
                'Приложение отправляет только указанные здесь пакеты — перед подключением и один раз после сетевого обрыва. Оно не настраивает RouterOS. Правила firewall могут временно добавить это устройство в динамический address list.',
              ),
              style: const TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Color(0xFF9DA7B3),
              ),
            ),
            if (widget.requiresExplicitTransport) ...[
              const SizedBox(height: 10),
              _Notice(
                text: l.t(
                  'Choose REST, binary API or SSH explicitly. Auto is disabled for knocking so the app never probes extra management ports.',
                  'Выбери REST, бинарный API или SSH явно. Автовыбор с knocking запрещён, чтобы приложение не пробовало лишние порты управления.',
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.t('Sequence (1–${PortKnockConfig.maxSteps})',
                        'Последовательность (1–${PortKnockConfig.maxSteps})'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _showPorts
                      ? l.t('Hide ports', 'Скрыть порты')
                      : l.t('Show ports', 'Показать порты'),
                  onPressed: () => setState(() => _showPorts = !_showPorts),
                  icon: Icon(
                    _showPorts ? Icons.visibility : Icons.visibility_off,
                    size: 19,
                  ),
                ),
              ],
            ),
            if (config.steps.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.t('Add at least one knock step.',
                      'Добавь хотя бы один шаг knocking.'),
                  style: const TextStyle(
                    color: Color(0xFFD29922),
                    fontSize: 12,
                  ),
                ),
              ),
            for (var index = 0; index < config.steps.length; index++)
              _stepTile(index, config.steps[index]),
            OutlinedButton.icon(
              onPressed: !widget.enabled ||
                      config.steps.length >= PortKnockConfig.maxSteps
                  ? null
                  : () => _editStep(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l.t('Add knock step', 'Добавить шаг knocking')),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _delayField(
                    label: l.t('Between steps', 'Между шагами'),
                    value: config.intervalMs,
                    values: const [0, 100, 200, 300, 500, 1000, 2000, 5000],
                    onChanged: (value) => widget.onChanged(
                      config.copyWith(intervalMs: value),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _delayField(
                    label: l.t('Before connect', 'Перед входом'),
                    value: config.settleMs,
                    values: const [0, 200, 300, 500, 1000, 2000, 5000, 10000],
                    onChanged: (value) => widget.onChanged(
                      config.copyWith(settleMs: value),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.t(
                'The sequence is kept in secure profile storage and excluded from diagnostic reports.',
                'Последовательность хранится в защищённом профиле и не попадает в диагностические отчёты.',
              ),
              style: const TextStyle(fontSize: 10, color: Color(0xFF7D8590)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepTile(int index, PortKnockStep step) {
    final config = widget.value;
    final protocol = step.protocol.name.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: const Color(0xFF171C22),
        borderRadius: BorderRadius.circular(9),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 10, right: 2),
          leading: CircleAvatar(
            radius: 13,
            backgroundColor: AppTheme.apAccent.withValues(alpha: 0.18),
            child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
          ),
          title: Text('$protocol · ${_showPorts ? step.port : '••••'}'),
          trailing: Wrap(
            spacing: 0,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: widget.l.t('Edit', 'Изменить'),
                onPressed: widget.enabled
                    ? () => _editStep(index: index, initial: step)
                    : null,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: widget.l.t('Remove', 'Удалить'),
                onPressed: widget.enabled
                    ? () {
                        final steps = [...config.steps]..removeAt(index);
                        widget.onChanged(config.copyWith(steps: steps));
                      }
                    : null,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _delayField({
    required String label,
    required int value,
    required List<int> values,
    required ValueChanged<int> onChanged,
  }) {
    final options = {...values, value}.toList()..sort();
    return DropdownButtonFormField<int>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options
          .map((delay) => DropdownMenuItem(
                value: delay,
                child: Text('$delay ms'),
              ))
          .toList(growable: false),
      onChanged: widget.enabled
          ? (next) {
              if (next != null) onChanged(next);
            }
          : null,
    );
  }

  Future<void> _editStep({int? index, PortKnockStep? initial}) async {
    var protocol = initial?.protocol ?? PortKnockProtocol.tcp;
    final port = TextEditingController(text: initial?.port.toString() ?? '');
    String? error;
    final result = await showDialog<PortKnockStep>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(widget.l.t(
            initial == null ? 'Add knock step' : 'Edit knock step',
            initial == null ? 'Добавить шаг knocking' : 'Изменить шаг knocking',
          )),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PortKnockProtocol>(
                initialValue: protocol,
                decoration: InputDecoration(
                  labelText: widget.l.t('Protocol', 'Протокол'),
                ),
                items: PortKnockProtocol.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name.toUpperCase()),
                        ))
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setDialogState(() => protocol = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: port,
                autofocus: true,
                obscureText: !_showPorts,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.l.t('Port', 'Порт'),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(widget.l.t('Cancel', 'Отмена')),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(port.text.trim());
                if (parsed == null || parsed < 1 || parsed > 65535) {
                  setDialogState(() => error = widget.l.t(
                        'Enter a port from 1 to 65535.',
                        'Укажи порт от 1 до 65535.',
                      ));
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  PortKnockStep(protocol: protocol, port: parsed),
                );
              },
              child: Text(widget.l.t('Save', 'Сохранить')),
            ),
          ],
        ),
      ),
    );
    port.dispose();
    if (result == null || !mounted) return;
    final steps = [...widget.value.steps];
    if (index == null) {
      steps.add(result);
    } else {
      steps[index] = result;
    }
    widget.onChanged(widget.value.copyWith(steps: steps));
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFD29922).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: const Color(0xFFD29922).withValues(alpha: 0.40),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFE3B341),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      );
}
