import 'dart:convert';

class DiagnosticEvent {
  final DateTime timestamp;
  final String code;
  final String message;
  final Map<String, Object?> details;
  final int occurrences;

  const DiagnosticEvent({
    required this.timestamp,
    required this.code,
    required this.message,
    this.details = const {},
    this.occurrences = 1,
  });

  DiagnosticEvent repeatedAt(DateTime at) => DiagnosticEvent(
        timestamp: at,
        code: code,
        message: message,
        details: details,
        occurrences: occurrences + 1,
      );

  Map<String, Object?> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'code': code,
        'message': message,
        if (details.isNotEmpty) 'details': details,
        if (occurrences > 1) 'occurrences': occurrences,
      };
}

/// In-memory only. Nothing is uploaded and nothing survives an app restart.
/// Consecutive identical events are coalesced to keep a poll failure from
/// flooding the support archive.
class DiagnosticLog {
  final int capacity;
  final List<DiagnosticEvent> _events = [];

  DiagnosticLog({this.capacity = 200});

  List<DiagnosticEvent> get events => List.unmodifiable(_events);

  void record(
    String code,
    String message, {
    Map<String, Object?> details = const {},
  }) {
    final now = DateTime.now();
    if (_events.isNotEmpty) {
      final last = _events.last;
      if (last.code == code &&
          last.message == message &&
          jsonEncode(last.details) == jsonEncode(details)) {
        _events[_events.length - 1] = last.repeatedAt(now);
        return;
      }
    }
    _events.add(DiagnosticEvent(
      timestamp: now,
      code: code,
      message: message,
      details: Map.unmodifiable(details),
    ));
    if (_events.length > capacity) _events.removeAt(0);
  }

  void clear() => _events.clear();
}
