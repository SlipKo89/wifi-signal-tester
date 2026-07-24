/// Lightweight inline localization: `l.t('English', 'Русский')`.
///
/// Deliberately not the full gen-l10n/.arb setup (tracked separately) — this
/// keeps a working EN/RU switch with strings living next to their widgets.
class L10n {
  final bool ru;
  const L10n(this.ru);

  String t(String en, String ruText) => ru ? ruText : en;
}
