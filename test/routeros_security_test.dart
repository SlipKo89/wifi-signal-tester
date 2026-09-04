import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/routeros_updates/routeros_security.dart';

void main() {
  group('RouterOS version intelligence', () {
    final service = RouterOsSecurityService();
    final catalog = RouterOsSecurityCatalog.bundled;

    test('compares stable versions within their official release branch', () {
      expect(
        service
            .evaluate(
              host: 'router',
              installedVersion: '7.23.3 (stable)',
              catalog: catalog,
            )
            ?.fixedVersion,
        '7.23.4',
      );
      expect(
        service
            .evaluate(
              host: 'router',
              installedVersion: '7.24.1',
              catalog: catalog,
            )
            ?.fixedVersion,
        '7.24.2',
      );
      expect(
        service.evaluate(
          host: 'router',
          installedVersion: '7.24.2',
          catalog: catalog,
        ),
        isNull,
      );
    });

    test('handles RouterOS 6 and development suffixes', () {
      expect(
        service
            .evaluate(
              host: 'router',
              installedVersion: '6.49.20 (long-term)',
              catalog: catalog,
            )
            ?.fixedVersion,
        '6.49.21',
      );
      expect(
        service
            .evaluate(
              host: 'router',
              installedVersion: '7.25beta2',
              catalog: catalog,
            )
            ?.fixedVersion,
        '7.25beta3',
      );
      expect(
        service.evaluate(
          host: 'router',
          installedVersion: '7.25beta3',
          catalog: catalog,
        ),
        isNull,
      );
    });

    test('does not guess about an unlisted newer branch', () {
      expect(
        service.evaluate(
          host: 'router',
          installedVersion: '7.26beta1',
          catalog: catalog,
        ),
        isNull,
      );
    });

    test('parses fixed releases from the official announcement shape', () {
      final catalog = RouterOsSecurityService.parseOfficialSecurityPage(
        '''
        <h3>Security Announcements</h3>
        <h4>September 2026 vulnerability Sep 3, 2026</h4>
        <p>This is an important security update.</p>
        <p>Fix is included in:</p>
        <ul><li>7.25 beta 3</li><li>7.24.2</li><li>7.23.4</li>
        <li>6.49.21</li></ul>
        <h2>Steps after upgrade</h2>
        ''',
        checkedAt: DateTime.utc(2026, 9, 5),
      );

      expect(catalog, isNotNull);
      expect(catalog!.fixedVersions,
          containsAll(['7.25beta3', '7.24.2', '7.23.4', '6.49.21']));
      expect(catalog.publishedAt, DateTime.utc(2026, 9, 3));
      expect(catalog.fromLiveSource, isTrue);
    });

    test('rejects an ordinary changelog without explicit security wording', () {
      expect(
        RouterOsSecurityService.parseOfficialSecurityPage(
          '<h3>Security Announcements</h3><p>Fix is included in: 7.24.2</p>',
          checkedAt: DateTime.utc(2026, 9, 5),
        ),
        isNull,
      );
    });
  });
}
