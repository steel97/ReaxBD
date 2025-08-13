import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:async';

void main() {
  group('Reactive Streams Tests', () {
    late ReaxDB db;
    final testPath = 'test/reactive_streams_test_db';

    setUp(() async {
      // Clean up before test
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      db = await ReaxDB.open(testPath);
    });

    tearDown(() async {
      await db.close();
      // Clean up after test
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    group('Basic Stream Operations', () {
      test('should emit events on put operations', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db.watch().listen(events.add);

        await db.put('key1', 'value1');
        await db.put('key2', 'value2');
        await db.put('key3', 'value3');

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(3));
        expect(events[0].key, equals('key1'));
        expect(events[0].type, equals(ChangeType.put));
        expect(events[1].key, equals('key2'));
        expect(events[2].key, equals('key3'));

        await subscription.cancel();
      });

      test('should emit events on delete operations', () async {
        await db.put('key1', 'value1');

        final events = <DatabaseChangeEvent>[];
        final subscription = db.watch().listen(events.add);

        await db.delete('key1');

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(1));
        expect(events[0].key, equals('key1'));
        expect(events[0].type, equals(ChangeType.delete));

        await subscription.cancel();
      });
    });

    group('Filtering Operations', () {
      test('should filter events with where clause', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db
            .watch()
            .where((event) => event.key.startsWith('user:'))
            .listen(events.add);

        await db.put('user:1', {'name': 'Alice'});
        await db.put('product:1', {'name': 'Widget'});
        await db.put('user:2', {'name': 'Bob'});
        await db.put('order:1', {'total': 100});

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(2));
        expect(events[0].key, equals('user:1'));
        expect(events[1].key, equals('user:2'));

        await subscription.cancel();
      });

      test('should watch specific key', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db.watchKey('specific').listen(events.add);

        await db.put('specific', 'value1');
        await db.put('other', 'value2');
        await db.put('specific', 'value3');

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(2));
        expect(events.every((e) => e.key == 'specific'), isTrue);

        await subscription.cancel();
      });

      test('should watch keys with prefix', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db.watchPrefix('cache:').listen(events.add);

        await db.put('cache:user:1', 'data1');
        await db.put('db:user:1', 'data2');
        await db.put('cache:product:1', 'data3');

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(2));
        expect(events[0].key, equals('cache:user:1'));
        expect(events[1].key, equals('cache:product:1'));

        await subscription.cancel();
      });

      test('should watch collection changes', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db.watchCollection('users').listen(events.add);

        await db.put('users:1', {'name': 'Alice'});
        await db.put('products:1', {'name': 'Widget'});
        await db.put('users:2', {'name': 'Bob'});

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(2));
        expect(events[0].key, equals('users:1'));
        expect(events[1].key, equals('users:2'));

        await subscription.cancel();
      });
    });

    group('Debounce and Throttle', () {
      test('should debounce rapid events', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db
            .watch()
            .debounce(Duration(milliseconds: 200))
            .listen(events.add);

        // Rapid fire events
        for (int i = 0; i < 5; i++) {
          await db.put('key$i', 'value$i');
          await Future.delayed(Duration(milliseconds: 50));
        }

        // Wait for debounce to trigger
        await Future.delayed(Duration(milliseconds: 300));

        // Should only get the last event due to debounce
        expect(events.length, equals(1));
        expect(events[0].key, equals('key4'));

        await subscription.cancel();
      });

      test('should throttle events', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db
            .watch()
            .throttle(Duration(milliseconds: 100))
            .listen(events.add);

        // Send events every 50ms
        for (int i = 0; i < 6; i++) {
          await db.put('key$i', 'value$i');
          await Future.delayed(Duration(milliseconds: 50));
        }

        await Future.delayed(Duration(milliseconds: 100));

        // With 100ms throttle and 50ms intervals, we should get ~3 events
        expect(events.length, greaterThanOrEqualTo(2));
        expect(events.length, lessThanOrEqualTo(4));

        await subscription.cancel();
      });
    });

    group('Buffer Operations', () {
      test('should buffer events by count', () async {
        final batches = <List<DatabaseChangeEvent>>[];
        final subscription = db
            .watch()
            .buffer(3)
            .listen(batches.add);

        for (int i = 0; i < 7; i++) {
          await db.put('key$i', 'value$i');
        }

        await Future.delayed(Duration(milliseconds: 100));

        expect(batches.length, equals(2)); // 7 events / 3 per batch = 2 full batches
        expect(batches[0].length, equals(3));
        expect(batches[1].length, equals(3));

        await subscription.cancel();
      });

      test('should buffer events by time', () async {
        final batches = <List<DatabaseChangeEvent>>[];
        final subscription = db
            .watch()
            .bufferTime(Duration(milliseconds: 200))
            .listen(batches.add);

        // Send events in two time windows
        for (int i = 0; i < 3; i++) {
          await db.put('key$i', 'value$i');
        }

        await Future.delayed(Duration(milliseconds: 250));

        for (int i = 3; i < 5; i++) {
          await db.put('key$i', 'value$i');
        }

        await Future.delayed(Duration(milliseconds: 250));

        expect(batches.length, equals(2));
        expect(batches[0].length, equals(3));
        expect(batches[1].length, equals(2));

        await subscription.cancel();
      });
    });

    group('Take and Skip Operations', () {
      test('should take only first n events', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db
            .watch()
            .take(3)
            .listen(events.add);

        for (int i = 0; i < 10; i++) {
          await db.put('key$i', 'value$i');
        }

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(3));
        expect(events[0].key, equals('key0'));
        expect(events[2].key, equals('key2'));

        await subscription.cancel();
      });

      test('should skip first n events', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db
            .watch()
            .skip(3)
            .listen(events.add);

        for (int i = 0; i < 5; i++) {
          await db.put('key$i', 'value$i');
        }

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(2));
        expect(events[0].key, equals('key3'));
        expect(events[1].key, equals('key4'));

        await subscription.cancel();
      });
    });

    group('Complex Chaining', () {
      test('should chain multiple operations', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db
            .watch()
            .where((event) => event.key.startsWith('user:'))
            .skip(1)
            .take(2)
            .listen(events.add);

        await db.put('user:1', 'Alice');
        await db.put('product:1', 'Widget');
        await db.put('user:2', 'Bob');
        await db.put('user:3', 'Charlie');
        await db.put('user:4', 'David');

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(2));
        expect(events[0].key, equals('user:2'));
        expect(events[1].key, equals('user:3'));

        await subscription.cancel();
      });

      test('should combine filtering with debounce', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db
            .watch()
            .where((event) => event.value is Map)
            .debounce(Duration(milliseconds: 150))
            .listen(events.add);

        // Rapid updates
        await db.put('key1', {'data': 1});
        await Future.delayed(Duration(milliseconds: 50));
        await db.put('key2', 'string');
        await Future.delayed(Duration(milliseconds: 50));
        await db.put('key3', {'data': 3});

        await Future.delayed(Duration(milliseconds: 200));

        expect(events.length, equals(1));
        expect(events[0].key, equals('key3'));
        expect(events[0].value, isA<Map>());

        await subscription.cancel();
      });
    });

    group('Map Transformations', () {
      test('should map events to custom type', () async {
        final mappedValues = <String>[];
        final subscription = db
            .watch()
            .map((event) => '${event.type}:${event.key}')
            .listen(mappedValues.add);

        await db.put('key1', 'value1');
        await db.delete('key1');
        await db.put('key2', 'value2');

        await Future.delayed(Duration(milliseconds: 100));

        expect(mappedValues.length, equals(3));
        expect(mappedValues[0], equals('${ChangeType.put}:key1'));
        expect(mappedValues[1], equals('${ChangeType.delete}:key1'));
        expect(mappedValues[2], equals('${ChangeType.put}:key2'));

        await subscription.cancel();
      });

      test('should extract values from events', () async {
        final values = <dynamic>[];
        final subscription = db
            .watch()
            .where((event) => event.type == ChangeType.put)
            .map((event) => event.value)
            .listen(values.add);

        await db.put('key1', 'value1');
        await db.put('key2', {'data': 123});
        await db.delete('key1');
        await db.put('key3', [1, 2, 3]);

        await Future.delayed(Duration(milliseconds: 100));

        expect(values.length, equals(3));
        expect(values[0], equals('value1'));
        expect(values[1], equals({'data': 123}));
        expect(values[2], equals([1, 2, 3]));

        await subscription.cancel();
      });
    });

    group('Pattern Streams', () {
      test('should handle multiple pattern watchers', () async {
        final userEvents = <DatabaseChangeEvent>[];
        final productEvents = <DatabaseChangeEvent>[];

        final userSub = db.watchPattern('user:*').listen(userEvents.add);
        final productSub = db.watchPattern('product:*').listen(productEvents.add);

        await db.put('user:1', 'Alice');
        await db.put('product:1', 'Widget');
        await db.put('user:2', 'Bob');
        await db.put('other:1', 'Something');
        await db.put('product:2', 'Gadget');

        await Future.delayed(Duration(milliseconds: 100));

        expect(userEvents.length, equals(2));
        expect(productEvents.length, equals(2));

        await userSub.cancel();
        await productSub.cancel();
      });
    });

    group('Error Handling', () {
      test('should handle errors in stream transformations', () async {
        final events = <DatabaseChangeEvent>[];
        final errors = <dynamic>[];

        final subscription = db
            .watch()
            .where((event) {
              if (event.key == 'error') {
                throw Exception('Test error');
              }
              return true;
            })
            .listen(
              events.add,
              onError: errors.add,
            );

        await db.put('key1', 'value1');
        await db.put('error', 'trigger error');
        await db.put('key2', 'value2');

        await Future.delayed(Duration(milliseconds: 100));

        expect(events.length, equals(2));
        expect(errors.length, equals(1));
        expect(errors[0].toString(), contains('Test error'));

        await subscription.cancel();
      });
    });
  });
}