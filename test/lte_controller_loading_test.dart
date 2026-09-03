import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_apk/lte/lte_controller.dart';
import 'package:wifi_apk/lte/lte_history_store.dart';
import 'package:wifi_apk/lte/lte_service.dart';
import 'package:wifi_apk/lte/lte_signal.dart';
import 'package:wifi_apk/mikrotik/router_os_transport.dart';

void main() {
  test('waits through zero-filled LTE snapshots until real metrics arrive',
      () async {
    final service = _SequenceLteService([
      _signal({
        'status': 'running',
        'rsrp': '0dBm',
        'rsrq': '0dB',
        'sinr': '0dB',
        'rssi': '0dBm',
      }),
      _signal({
        'status': 'running',
        'current-operator': 'Example Mobile',
        'rsrp': '-101dBm',
        'rsrq': '-11dB',
        'sinr': '8dB',
      }),
    ]);
    final controller = LteController(service: service)
      ..pollInterval = const Duration(seconds: 30);
    addTearDown(() async {
      await controller.disconnect();
      controller.dispose();
    });

    final connected = await controller.connect(const LteConnection(
      host: '192.0.2.1',
      username: 'monitor',
      password: 'secret',
      transport: TransportPreference.ssh,
    ));

    expect(connected, isTrue);
    expect(controller.state, LteMonitorState.connected);
    expect(controller.waitingForFirstSample, isTrue);
    expect(controller.signal, isNull);
    expect(controller.history, isEmpty);
    expect(controller.firstSampleAttempts, 1);

    await controller.refresh();
    expect(controller.waitingForFirstSample, isFalse);
    expect(controller.signal?.rsrp, -101);
    expect(controller.history, hasLength(1));
  });

  test('shows an explicit not-registered state without waiting forever',
      () async {
    final service = _SequenceLteService([
      _signal({'status': 'searching'}),
    ]);
    final controller = LteController(service: service)
      ..pollInterval = const Duration(seconds: 30);
    addTearDown(() async {
      await controller.disconnect();
      controller.dispose();
    });

    expect(
      await controller.connect(const LteConnection(
        host: '192.0.2.1',
        username: 'monitor',
        password: 'secret',
      )),
      isTrue,
    );
    expect(controller.waitingForFirstSample, isFalse);
    expect(controller.signal?.registered, isFalse);
    expect(controller.signal?.status, 'searching');
  });

  test('shutdown closes every LTE resource once even when one close fails',
      () async {
    final service = _CloseTrackingLteService(throwOnClose: true);
    final history = _CloseTrackingLteHistory();
    final controller = LteController(
      service: service,
      historyStore: history,
    );

    final first = controller.shutdown();
    final second = controller.shutdown();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(service.closeCount, 1);
    expect(history.closeCount, 1);
  });

  test('shutdown waits for an in-flight poll before closing history', () async {
    final service = _BlockingRefreshLteService();
    final history = _CloseTrackingLteHistory();
    final controller = LteController(
      service: service,
      historyStore: history,
    )..pollInterval = const Duration(seconds: 30);

    expect(
      await controller.connect(const LteConnection(
        host: '192.0.2.1',
        username: 'monitor',
        password: 'secret',
      )),
      isTrue,
    );
    final refresh = controller.refresh();
    await service.blockingReadStarted.future;

    final shutdown = controller.shutdown();
    await Future<void>.delayed(Duration.zero);
    expect(history.closeCount, 0);

    service.releaseBlockingRead();
    await Future.wait([refresh, shutdown]);
    expect(history.closeCount, 1);
    expect(service.closeCount, 1);
    controller.dispose();
  });
}

LteSignal _signal(Map<String, String> row) =>
    LteSignal.fromMonitor(row, interfaceName: 'lte1');

class _SequenceLteService extends LteService {
  final List<LteSignal> _signals;
  int _index = 0;

  _SequenceLteService(this._signals);

  @override
  String? get transportKind => 'SSH';

  @override
  Future<void> connect(LteConnection connection) async {
    interfaceName = 'lte1';
  }

  @override
  Future<LteSignal> readSignal() async {
    final index = _index < _signals.length ? _index : _signals.length - 1;
    _index++;
    return _signals[index];
  }

  @override
  Future<Map<String, String>?> readResource() async => {
        'board-name': 'SXT LTE',
        'version': '7.21.1',
      };

  @override
  Future<void> close() async {
    interfaceName = null;
  }
}

class _CloseTrackingLteService extends LteService {
  final bool throwOnClose;
  int closeCount = 0;

  _CloseTrackingLteService({this.throwOnClose = false});

  @override
  Future<void> close() async {
    closeCount++;
    if (throwOnClose) throw StateError('simulated transport close failure');
  }
}

class _CloseTrackingLteHistory extends LteHistoryStore {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }
}

class _BlockingRefreshLteService extends LteService {
  final blockingReadStarted = Completer<void>();
  final _release = Completer<void>();
  int _reads = 0;
  int closeCount = 0;

  @override
  Future<void> connect(LteConnection connection) async {
    interfaceName = 'lte1';
  }

  @override
  Future<Map<String, String>?> readResource() async => const {
        'board-name': 'Test LTE',
        'version': '7.20',
      };

  @override
  Future<LteSignal> readSignal() async {
    _reads++;
    if (_reads > 1) {
      if (!blockingReadStarted.isCompleted) blockingReadStarted.complete();
      await _release.future;
    }
    return _signal({
      'status': 'registered',
      'rsrp': '-100dBm',
      'rsrq': '-10dB',
      'sinr': '10dB',
    });
  }

  void releaseBlockingRead() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> close() async {
    closeCount++;
    interfaceName = null;
  }
}
