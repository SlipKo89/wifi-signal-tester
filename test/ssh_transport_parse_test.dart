import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_signal.dart';
import 'package:wifi_apk/mikrotik/router_os_transport.dart';
import 'package:wifi_apk/mikrotik/ssh_transport.dart';

/// The samples below are verbatim RouterOS 7.22 output captured over SSH from a
/// hAP AC3 running legacy CAPsMAN. The console does not quote values in terse
/// mode, so `interface=hAP AC3 2GHz ssid=SlipKo Wi-Fi 2GHz` is one record with
/// two fields — that is the case worth pinning down.
void main() {
  group('parseRecords', () {
    test('terse: unquoted values with spaces split at the next key', () {
      const out =
          ' 0 comment=-= Kitchen Light Switch =- interface=hAP AC3 2GHz '
          'ssid=SlipKo Wi-Fi 2GHz mac-address=B8:06:0D:71:10:16 eap-identity=';
      final rows = SshTransport.parseRecords(out);

      expect(rows, hasLength(1));
      expect(rows.first['comment'], '-= Kitchen Light Switch =-');
      expect(rows.first['interface'], 'hAP AC3 2GHz');
      expect(rows.first['ssid'], 'SlipKo Wi-Fi 2GHz');
      expect(rows.first['mac-address'], 'B8:06:0D:71:10:16');
      expect(rows.first['eap-identity'], '');
    });

    test('flag letters become the fields REST would return', () {
      const out = ' 0 X name=ftp port=21\n'
          ' 1 D c name=ssh port=22\n'
          ' 2 name=www port=80';
      final rows = SshTransport.parseRecords(out);

      expect(rows, hasLength(3));
      expect(rows[0]['disabled'], 'true');
      expect(rows[0]['name'], 'ftp');
      expect(rows[1]['dynamic'], 'true');
      expect(rows[1].containsKey('disabled'), isFalse);
      expect(rows[2].containsKey('disabled'), isFalse);
      expect(rows[2]['name'], 'www');
    });

    test('stats: `;;;` comment line plus a field line make one record', () {
      const out = ' 0 ;;; -= Kitchen Light Switch =-\n'
          '   interface=hAP AC3 2GHz ssid="SlipKo Wi-Fi 2GHz" '
          'mac-address=B8:06:0D:71:10:16 tx-rate="39Mbps-20MHz/1S" '
          'rx-signal=-75 uptime=1d11h58m12s590ms packets=8760,31839\n'
          '\n'
          ' 1 ;;; -= Kirill Light Switch =-\n'
          '   interface=hAP AC3 2GHz mac-address=4C:A9:19:A5:8C:47 '
          'rx-signal=-56';
      final rows = SshTransport.parseRecords(out);

      expect(rows, hasLength(2));
      expect(rows[0]['comment'], '-= Kitchen Light Switch =-');
      expect(rows[0]['rx-signal'], '-75');
      expect(rows[0]['tx-rate'], '39Mbps-20MHz/1S'); // quotes stripped
      expect(rows[0]['packets'], '8760,31839');
      expect(rows[1]['mac-address'], '4C:A9:19:A5:8C:47');
      expect(rows[1]['rx-signal'], '-56');
    });

    test('an `=` inside a value does not start a new field', () {
      const out = ' 0 B name=Guests-5GHz '
          'current-rate-set=OFDM:6-54 BW:1x-4x HT:0-15 VHTMCS:SS1=0-9,SS2=0-9 '
          'current-state=running-ap current-registered-clients=0';
      final rows = SshTransport.parseRecords(out);

      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Guests-5GHz');
      expect(rows.first['current-rate-set'],
          'OFDM:6-54 BW:1x-4x HT:0-15 VHTMCS:SS1=0-9,SS2=0-9');
      expect(rows.first['current-state'], 'running-ap');
      expect(rows.first['bound'], 'true');
    });

    test('console yes/no becomes REST true/false', () {
      const out = ' 0 HC address=192.168.176.13 published=no '
          'client-to-client-forwarding=yes status=permanent';
      final rows = SshTransport.parseRecords(out);

      // The audit compares against 'true'/'false' — see the REST transport.
      expect(rows.first['published'], 'false');
      expect(rows.first['client-to-client-forwarding'], 'true');
      expect(rows.first['status'], 'permanent');
    });

    test('dotted keys survive (CAPsMAN channel.band)', () {
      const out = '0 name=SlipKo WiFI 5GHz mode=ap security=Pass '
          'channel.band=5ghz-n/ac';
      final rows = SshTransport.parseRecords(out);

      expect(rows.first['channel.band'], '5ghz-n/ac');
      expect(rows.first['name'], 'SlipKo WiFI 5GHz');
    });
  });

  group('parseLabelled', () {
    test('plain print of a single-record menu', () {
      const out = '                   uptime: 1d11h58m17s\n'
          '                  version: 7.22.3 (stable)\n'
          '              free-memory: 128.6MiB\n'
          '             total-memory: 256.0MiB\n'
          '                cpu-count: 4';
      final row = SshTransport.parseLabelled(out);

      expect(row['uptime'], '1d11h58m17s');
      expect(row['version'], '7.22.3 (stable)');
      expect(row['free-memory'], '128.6MiB');
      expect(row['cpu-count'], '4');
    });

    test('monitor once: comments skipped, noise floor kept', () {
      const out = '                 ;;; managed by CAPsMAN\n'
          '                 ;;; channel: 2412/20-Ce/gn(18dBm), SSID: X\n'
          '            channel: 2412/20-Ce/gn(18dBm)\n'
          '        noise-floor: -103dBm\n'
          '     overall-tx-ccq: 65%';
      final row = SshTransport.parseLabelled(out);

      expect(row['noise-floor'], '-103dBm');
      expect(row.containsKey('managed'), isFalse); // `;;;` lines are not fields
      expect(row['channel'], '2412/20-Ce/gn(18dBm)');
      expect(row['overall-tx-ccq'], '65%');
    });

    test('LTE monitor: R11e-LTE labels feed the sanitised model', () {
      const out = '               status: registered\n'
          '         manufacturer: "MikroTik"\n'
          '                model: "R11e-LTE"\n'
          '     current-operator: Example Mobile\n'
          '    access-technology: LTE\n'
          '               earfcn: 2850 (band 7, bandwidth 20Mhz)\n'
          '                  cqi: 12\n'
          '                 rsrp: -102dBm\n'
          '                 rsrq: -8dB\n'
          '                 sinr: 13dB';
      final row = SshTransport.parseLabelled(out);
      final signal = LteSignal.fromMonitor(row, interfaceName: 'lte1');

      expect(signal.modemModel, 'R11e-LTE');
      expect(signal.band, 'B7');
      expect(signal.cqi, 12);
      expect(signal.sinr, 13);
    });

    test('LTE monitor: MBIM primary-band tail remains parseable', () {
      const out = '            status: running\n'
          '             model: FG621-EA\n'
          '  current-operator: Example LTE\n'
          '        data-class: LTE\n'
          '      primary-band: B7@20Mhz earfcn: 3250 phy-cellid: 353\n'
          '              rssi: -80dBm\n'
          '              rsrp: -108dBm\n'
          '              rsrq: -12.5dB\n'
          '              sinr: -1dB';
      final row = SshTransport.parseLabelled(out);
      final signal = LteSignal.fromMonitor(row, interfaceName: 'lte1');

      expect(signal.band, 'B7');
      expect(signal.bandwidthMhz, 20);
      expect(signal.earfcn, 3250);
      expect(signal.rsrq, -12.5);
    });
  });

  group('projected singleton reads', () {
    test('system resource falls back to safe plain print', () async {
      final commands = <String>[];
      final transport = SshTransport.forTesting((command) async {
        commands.add(command);
        if (command == '/system resource print') {
          return '       uptime: 2d3h\n'
              '       version: 7.21.1 (stable)\n'
              '    board-name: SXTR\n'
              '    free-memory: 64MiB';
        }
        return 'expected end of command';
      });

      final rows = await transport.read(
        '/system/resource',
        fields: const ['board-name', 'version', 'uptime'],
      );

      expect(rows.single, {
        'board-name': 'SXTR',
        'version': '7.21.1 (stable)',
        'uptime': '2d3h',
      });
      expect(commands.last, '/system resource print');
      expect(commands.where((command) => command.contains('proplist')),
          hasLength(2));

      await transport.read(
        '/system/resource',
        fields: const ['board-name', 'version', 'uptime'],
      );

      expect(commands.where((command) => command.contains('proplist')),
          hasLength(2));
      expect(commands.where((command) => command == '/system resource print'),
          hasLength(2));
    });

    test('LTE settings falls back to safe plain print', () async {
      final commands = <String>[];
      final transport = SshTransport.forTesting((command) async {
        commands.add(command);
        if (command == '/interface lte settings print') {
          return '       mode: auto\n'
              '   sim-slot: a\n'
              'firmware-path: firmware';
        }
        return 'expected end of command';
      });

      final rows = await transport.read(
        '/interface/lte/settings',
        fields: const ['mode', 'sim-slot'],
      );

      expect(rows.single, {'mode': 'auto', 'sim-slot': 'a'});
      expect(commands.last, '/interface lte settings print');
    });

    test('sensitive LTE interface menu never gets an unprojected fallback',
        () async {
      final commands = <String>[];
      final transport = SshTransport.forTesting((command) async {
        commands.add(command);
        return 'expected end of command';
      });

      await expectLater(
        transport.read('/interface/lte', fields: const ['name', 'running']),
        throwsA(isA<RouterOsException>()),
      );
      expect(commands, isNot(contains('/interface lte print')));
      expect(commands.every((command) => command.contains('proplist')), isTrue);
    });
  });

  group('SSH capability cache', () {
    test('reuses the successful print flavour after one negotiation', () async {
      final commands = <String>[];
      final transport = SshTransport.forTesting((command) async {
        commands.add(command);
        if (command == '/ip arp print') {
          return '0 address=192.168.88.10 '
              'mac-address=AA:BB:CC:DD:EE:FF';
        }
        return 'expected end of command';
      });

      await transport.read('/ip/arp');
      await transport.read('/ip/arp');

      expect(commands.where((c) => c == '/ip arp print terse'), hasLength(1));
      expect(commands.where((c) => c == '/ip arp print'), hasLength(2));
    });

    test('an absent registration menu causes only one router error', () async {
      final commands = <String>[];
      final transport = SshTransport.forTesting((command) async {
        commands.add(command);
        return 'bad command name registration-table (line 1 column 25)';
      });

      await expectLater(
        transport.read('/interface/wifi/capsman/registration-table'),
        throwsA(isA<RouterOsException>()),
      );
      await expectLater(
        transport.read(
          '/interface/wifi/capsman/registration-table',
          fields: const ['mac-address'],
        ),
        throwsA(isA<RouterOsException>()),
      );

      expect(commands, hasLength(1));
      expect(commands.single,
          '/interface wifi capsman registration-table print stats');
    });

    test('a rejected registration terse merge is not retried each poll',
        () async {
      final commands = <String>[];
      final transport = SshTransport.forTesting((command) async {
        commands.add(command);
        if (command == '/caps-man registration-table print stats') {
          return '0 mac-address=AA:BB:CC:DD:EE:FF interface=cap1';
        }
        if (command == '/caps-man registration-table print terse') {
          return 'bad parameter terse (line 1 column 29)';
        }
        return 'expected end of command';
      });

      await transport.read('/caps-man/registration-table');
      await transport.read('/caps-man/registration-table');
      await transport.read('/caps-man/registration-table');

      expect(
        commands.where(
          (c) => c == '/caps-man registration-table print stats',
        ),
        hasLength(3),
      );
      expect(
        commands.where(
          (c) => c == '/caps-man registration-table print terse',
        ),
        hasLength(1),
      );
    });
  });
}
