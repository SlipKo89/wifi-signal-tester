import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wifi_apk/history/history_store.dart';
import 'package:wifi_apk/services/beeper.dart';
import 'package:wifi_apk/state/monitor_controller.dart';

void main() {
  group('HistoryStore lifecycle', () {
    test('shares one database open between concurrent callers', () async {
      final gate = Completer<Database>();
      var openCount = 0;
      final database = _FakeDatabase();
      final store = HistoryStore(databaseOpener: () {
        openCount++;
        return gate.future;
      });

      final first = store.sessions();
      final second = store.sessions();
      await Future<void>.delayed(Duration.zero);
      expect(openCount, 1);

      gate.complete(database);
      await Future.wait([first, second]);
      expect(database.rawQueryCount, 2);
      await store.close();
    });

    test('failed open can be retried and a closed store can reopen', () async {
      var openCount = 0;
      final firstDatabase = _FakeDatabase();
      final secondDatabase = _FakeDatabase();
      final store = HistoryStore(databaseOpener: () async {
        openCount++;
        if (openCount == 1) throw StateError('temporary open failure');
        return openCount == 2 ? firstDatabase : secondDatabase;
      });

      await expectLater(store.sessions(), throwsStateError);
      await store.sessions();
      await store.close();
      expect(firstDatabase.closed, isTrue);

      await store.sessions();
      expect(openCount, 3);
      await store.close();
      expect(secondDatabase.closed, isTrue);
    });

    test('session deletion and clear-all are atomic transactions', () async {
      final database = _FakeDatabase();
      final store = HistoryStore(databaseOpener: () async => database);

      await store.deleteSession(7);
      expect(database.transactionCount, 1);
      expect(database.transactionDeletes, [
        'samples:session_id = ?:7',
        'sessions:id = ?:7',
      ]);

      database.transactionDeletes.clear();
      await store.clearAll();
      expect(database.transactionCount, 2);
      expect(database.transactionDeletes, ['samples::', 'sessions::']);
      await store.close();
    });

    testWidgets('MonitorController shutdown is awaitable and idempotent',
        (tester) async {
      final store = _TrackingHistoryStore();
      final beeper = _TrackingBeeper();
      final controller = MonitorController(
        historyStore: store,
        beeper: beeper,
      );

      final first = controller.shutdown();
      final second = controller.shutdown();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);

      controller.dispose();
      await tester.pump();

      expect(store.closeCount, 1);
      expect(beeper.disposeCount, 1);
    });
  });
}

class _FakeDatabase implements Database {
  final transactionDeletes = <String>[];
  int rawQueryCount = 0;
  int transactionCount = 0;
  bool closed = false;

  @override
  String get path => 'memory:test';

  @override
  bool get isOpen => !closed;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    rawQueryCount++;
    return const [];
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    transactionCount++;
    return action(_FakeTransaction(transactionDeletes));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransaction implements Transaction {
  final List<String> deletes;

  _FakeTransaction(this.deletes);

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    deletes.add('$table:${where ?? ''}:${whereArgs?.join(',') ?? ''}');
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackingHistoryStore extends HistoryStore {
  final closed = Completer<void>();
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
    if (!closed.isCompleted) closed.complete();
  }
}

class _TrackingBeeper extends Beeper {
  int disposeCount = 0;

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}
