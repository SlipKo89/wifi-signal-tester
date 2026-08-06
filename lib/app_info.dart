/// App identity shown in the About screen. Keep [kAppVersion] in sync with
/// /VERSION, pubspec.yaml and CHANGELOG.md when releasing.
const String kAppName = 'Wi-Fi Signal Tester';
const String kAppTagline = 'Two-sided MikroTik Wi-Fi signal tester';
const String kAppVersion = '0.2.5';

const String kAuthor = 'SlipKo';
const String kAuthorEmail = 'slipko89@gmail.com';

const String kAuthorTelegram = '@slipko';

/// Project home — source, releases and documentation.
const String kRepoUrl = 'https://github.com/SlipKo89/wifi-signal-tester';
const String kIssuesUrl = '$kRepoUrl/issues';
const String kReleasesUrl = '$kRepoUrl/releases/latest';

/// Usage guide, per UI language.
const String kUsageUrlEn = '$kRepoUrl/blob/main/docs/usage.md';
const String kUsageUrlRu = '$kRepoUrl/blob/main/docs/usage.ru.md';

String usageUrl({required bool ru}) => ru ? kUsageUrlRu : kUsageUrlEn;
