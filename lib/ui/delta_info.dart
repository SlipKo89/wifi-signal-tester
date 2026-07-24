import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../settings/settings_controller.dart';
import 'theme.dart';

/// Opens the explanation + advice sheet for the AP−phone delta.
void showDeltaInfo(
  BuildContext context, {
  required int? phoneRssi,
  required int? apSignal,
  required int? delta,
  String? apName,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DeltaInfoSheet(
      phoneRssi: phoneRssi,
      apSignal: apSignal,
      delta: delta,
      apName: apName,
    ),
  );
}

class _Advice {
  final IconData icon;
  final Color color;
  final String text;
  const _Advice(this.icon, this.color, this.text);
}

class _DeltaInfoSheet extends StatelessWidget {
  final int? phoneRssi;
  final int? apSignal;
  final int? delta;
  final String? apName;

  const _DeltaInfoSheet({
    required this.phoneRssi,
    required this.apSignal,
    required this.delta,
    required this.apName,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsController>().l;
    final advice = _buildAdvice(l);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('Signal asymmetry (Δ AP−phone)', 'Асимметрия (Δ AP−phone)'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              l.t(
                  'The difference between the two directions of the link:\n'
                      'Δ = (how the AP hears the phone) − (how the phone hears '
                      'the AP).',
                  'Разница между двумя направлениями связи:\n'
                      'Δ = (как точка слышит телефон) − (как телефон слышит '
                      'точку).'),
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFFAAB2BD), height: 1.4),
            ),
            const SizedBox(height: 14),
            _formulaRow(),
            const SizedBox(height: 6),
            Text(
              l.t(
                  'Negative → the AP hears you worse than you hear it. Every '
                      '3 dB ≈ 2× power. A balanced link (near 0) is ideal.',
                  'Минус → точка слышит тебя хуже, чем ты её. Каждые 3 dB ≈ '
                      '×2 по мощности. Идеал — баланс около 0.'),
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF7D8590), height: 1.4),
            ),
            const Divider(height: 26, color: Color(0xFF232B36)),
            Text(l.t('WHAT TO DO', 'ЧТО ДЕЛАТЬ'),
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: Color(0xFF7D8590),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...advice.map(_adviceRow),
          ],
        ),
      ),
    );
  }

  Widget _formulaRow() {
    final ap = apSignal?.toString() ?? '—';
    final ph = phoneRssi?.toString() ?? '—';
    final d = delta == null ? '—' : '${delta! > 0 ? '+' : ''}$delta dB';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Δ = $ap − ($ph) = $d',
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      ),
    );
  }

  Widget _adviceRow(_Advice a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(a.icon, size: 17, color: a.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(a.text,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  // Rule-based verdict from the current numbers.
  List<_Advice> _buildAdvice(L10n l) {
    const green = Color(0xFF3FB950);
    const amber = Color(0xFFD29922);
    const red = Color(0xFFF85149);

    if (delta == null || apSignal == null) {
      return [
        _Advice(
            Icons.info_outline,
            const Color(0xFF7D8590),
            l.t(
                'No AP-side data yet — connect to an AP this router manages to '
                    'compare the two directions.',
                'Данных со стороны точки пока нет — подключись к точке, которой '
                    'управляет этот роутер, чтобы сравнить направления.')),
      ];
    }

    final d = delta!;
    final abs = d.abs();
    final out = <_Advice>[];

    if (abs <= 6) {
      out.add(_Advice(
          Icons.check_circle_outline,
          green,
          l.t(
              'Balanced link — both sides hear each other similarly. This is '
                  'what you want.',
              'Связь сбалансирована — обе стороны слышат друг друга похоже. '
                  'Это то, что нужно.')));
    } else if (d < 0) {
      final sev = abs > 15 ? red : amber;
      out.add(_Advice(
          Icons.trending_down,
          sev,
          l.t(
              'The AP hears you $abs dB weaker than you hear it — the uplink '
                  '(phone → AP) is the weak side.',
              'Точка слышит тебя на $abs dB слабее, чем ты её — слабое звено '
                  'это аплинк (телефон → точка).')));
      out.add(_Advice(
          Icons.settings_input_antenna,
          amber,
          l.t(
              'Likely the AP TX power is set higher than your phone can match, '
                  "or you're near the edge of its range.",
              'Скорее всего, мощность точки задрана выше, чем может телефон, '
                  'либо ты на краю её зоны.')));
      out.add(_Advice(
          Icons.tune,
          amber,
          l.t(
              'Try: lower the AP TX power so both sides match, move closer, or '
                  'add an AP for this area.',
              'Попробуй: снизь мощность точки, подойди ближе или добавь AP на '
                  'эту зону.')));
    } else {
      out.add(_Advice(
          Icons.trending_up,
          amber,
          l.t(
              'The AP hears you $abs dB stronger than you hear it — uncommon.',
              'Точка слышит тебя на $abs dB сильнее, чем ты её — необычно.')));
      out.add(_Advice(
          Icons.settings_input_antenna,
          amber,
          l.t(
              'Often a high-gain AP antenna. Usually fine; if the phone drains '
                  'fast, its radio may be working hard to keep up.',
              'Часто это мощная антенна точки. Обычно норм; если телефон быстро '
                  'садится — его радио усиленно тянется за точкой.')));
    }

    if ((phoneRssi ?? 0) < -75 && (apSignal ?? 0) < -75) {
      out.add(_Advice(
          Icons.warning_amber,
          red,
          l.t(
              'Both sides are weak (phone $phoneRssi dBm, AP $apSignal dBm) — '
                  'expect retransmits and low rates. Move closer or add an AP.',
              'Обе стороны слабые (телефон $phoneRssi dBm, точка $apSignal dBm) '
                  '— жди ретрансмиты и низкие скорости. Подойди ближе или добавь '
                  'AP.')));
    } else if ((apSignal ?? 0) < -75) {
      out.add(_Advice(
          Icons.upload,
          red,
          l.t(
              'The AP barely hears you ($apSignal dBm) — uploads and latency '
                  'will suffer even though download looks fine.',
              'Точка еле слышит тебя ($apSignal dBm) — отдача и задержки будут '
                  'страдать, даже если загрузка выглядит нормально.')));
    }

    return out;
  }
}
