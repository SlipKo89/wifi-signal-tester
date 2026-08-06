import 'package:flutter_test/flutter_test.dart';
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
  });
}
