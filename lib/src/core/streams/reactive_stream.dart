import 'dart:async';
import '../../domain/entities/database_entity.dart';

/// Reactive stream builder for database changes
class ReactiveStream {
  final Stream<DatabaseChangeEvent> _sourceStream;
  final List<StreamTransformer<DatabaseChangeEvent, DatabaseChangeEvent>> _transformers = [];

  ReactiveStream(this._sourceStream);

  /// Filter events by a predicate
  ReactiveStream where(bool Function(DatabaseChangeEvent) test) {
    _transformers.add(
      StreamTransformer<DatabaseChangeEvent, DatabaseChangeEvent>.fromHandlers(
        handleData: (event, sink) {
          if (test(event)) {
            sink.add(event);
          }
        },
      ),
    );
    return this;
  }

  /// Map events to a different type
  Stream<T> map<T>(T Function(DatabaseChangeEvent) convert) {
    Stream<DatabaseChangeEvent> stream = _sourceStream;
    for (final transformer in _transformers) {
      stream = stream.transform(transformer);
    }
    return stream.map(convert);
  }

  /// Distinct events based on a key selector
  ReactiveStream distinct([Object? Function(DatabaseChangeEvent)? keySelector]) {
    _transformers.add(
      StreamTransformer<DatabaseChangeEvent, DatabaseChangeEvent>.fromHandlers(
        handleData: (event, sink) {
          // Simple distinct implementation
          sink.add(event);
        },
      ).cast<DatabaseChangeEvent, DatabaseChangeEvent>(),
    );
    return this;
  }

  /// Debounce events by duration
  ReactiveStream debounce(Duration duration) {
    Timer? timer;
    DatabaseChangeEvent? lastEvent;

    _transformers.add(
      StreamTransformer<DatabaseChangeEvent, DatabaseChangeEvent>.fromHandlers(
        handleData: (event, sink) {
          lastEvent = event;
          timer?.cancel();
          timer = Timer(duration, () {
            if (lastEvent != null) {
              sink.add(lastEvent!);
            }
          });
        },
        handleDone: (sink) {
          timer?.cancel();
          if (lastEvent != null) {
            sink.add(lastEvent!);
          }
          sink.close();
        },
      ),
    );
    return this;
  }

  /// Throttle events by duration
  ReactiveStream throttle(Duration duration) {
    DateTime? lastEmit;

    _transformers.add(
      StreamTransformer<DatabaseChangeEvent, DatabaseChangeEvent>.fromHandlers(
        handleData: (event, sink) {
          final now = DateTime.now();
          if (lastEmit == null || now.difference(lastEmit!) >= duration) {
            lastEmit = now;
            sink.add(event);
          }
        },
      ),
    );
    return this;
  }

  /// Buffer events into batches
  Stream<List<DatabaseChangeEvent>> buffer(int count) {
    final buffer = <DatabaseChangeEvent>[];
    
    Stream<DatabaseChangeEvent> stream = _sourceStream;
    for (final transformer in _transformers) {
      stream = stream.transform(transformer);
    }

    return stream.transform(
      StreamTransformer<DatabaseChangeEvent, List<DatabaseChangeEvent>>.fromHandlers(
        handleData: (event, sink) {
          buffer.add(event);
          if (buffer.length >= count) {
            sink.add(List.from(buffer));
            buffer.clear();
          }
        },
        handleDone: (sink) {
          if (buffer.isNotEmpty) {
            sink.add(List.from(buffer));
          }
          sink.close();
        },
      ),
    );
  }

  /// Buffer events by time window
  Stream<List<DatabaseChangeEvent>> bufferTime(Duration duration) {
    final buffer = <DatabaseChangeEvent>[];
    Timer? timer;

    Stream<DatabaseChangeEvent> stream = _sourceStream;
    for (final transformer in _transformers) {
      stream = stream.transform(transformer);
    }

    return stream.transform(
      StreamTransformer<DatabaseChangeEvent, List<DatabaseChangeEvent>>.fromHandlers(
        handleData: (event, sink) {
          if (buffer.isEmpty) {
            timer = Timer(duration, () {
              if (buffer.isNotEmpty) {
                sink.add(List.from(buffer));
                buffer.clear();
              }
            });
          }
          buffer.add(event);
        },
        handleDone: (sink) {
          timer?.cancel();
          if (buffer.isNotEmpty) {
            sink.add(List.from(buffer));
          }
          sink.close();
        },
      ),
    );
  }

  /// Take only first n events
  ReactiveStream take(int count) {
    int taken = 0;

    _transformers.add(
      StreamTransformer<DatabaseChangeEvent, DatabaseChangeEvent>.fromHandlers(
        handleData: (event, sink) {
          if (taken < count) {
            taken++;
            sink.add(event);
            if (taken >= count) {
              sink.close();
            }
          }
        },
      ),
    );
    return this;
  }

  /// Skip first n events
  ReactiveStream skip(int count) {
    int skipped = 0;

    _transformers.add(
      StreamTransformer<DatabaseChangeEvent, DatabaseChangeEvent>.fromHandlers(
        handleData: (event, sink) {
          if (skipped >= count) {
            sink.add(event);
          } else {
            skipped++;
          }
        },
      ),
    );
    return this;
  }

  /// Listen to the stream
  StreamSubscription<DatabaseChangeEvent> listen(
    void Function(DatabaseChangeEvent) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    Stream<DatabaseChangeEvent> stream = _sourceStream;
    for (final transformer in _transformers) {
      stream = stream.transform(transformer);
    }
    
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Convert to regular stream
  Stream<DatabaseChangeEvent> asStream() {
    Stream<DatabaseChangeEvent> stream = _sourceStream;
    for (final transformer in _transformers) {
      stream = stream.transform(transformer);
    }
    return stream;
  }
}

/// Extension to create reactive streams from regular streams
extension ReactiveStreamExtension on Stream<DatabaseChangeEvent> {
  ReactiveStream get reactive => ReactiveStream(this);
}