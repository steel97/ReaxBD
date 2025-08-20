import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  group('SimpleReaxDB API Tests', () {
    late SimpleReaxDB db;
    final testDir = Directory('test_db_simple');
    
    setUp(() async {
      // Clean up any existing test database
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
      
      // Create new test database
      db = await ReaxDB.simple('test_simple', path: testDir.path);
    });
    
    tearDown(() async {
      // Close database
      await db.close();
      
      // Clean up test directory
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    });
    
    group('Basic Operations', () {
      test('should store and retrieve string values', () async {
        await db.put('key1', 'value1');
        final value = await db.get('key1');
        expect(value, equals('value1'));
      });
      
      test('should store and retrieve numeric values', () async {
        await db.put('int_key', 42);
        await db.put('double_key', 3.14);
        
        expect(await db.get('int_key'), equals(42));
        expect(await db.get('double_key'), equals(3.14));
      });
      
      test('should store and retrieve boolean values', () async {
        await db.put('bool_key', true);
        expect(await db.get('bool_key'), equals(true));
      });
      
      test('should store and retrieve Map objects', () async {
        final user = {
          'name': 'Alice',
          'age': 30,
          'email': 'alice@example.com',
          'premium': true,
        };
        
        await db.put('user:1', user);
        final retrieved = await db.get('user:1');
        
        expect(retrieved, equals(user));
        expect(retrieved['name'], equals('Alice'));
        expect(retrieved['age'], equals(30));
      });
      
      test('should store and retrieve List objects', () async {
        final tags = ['flutter', 'dart', 'reaxdb'];
        await db.put('tags', tags);
        
        final retrieved = await db.get('tags');
        expect(retrieved, equals(tags));
        expect(retrieved.length, equals(3));
      });
      
      test('should return null for non-existent keys', () async {
        final value = await db.get('non_existent');
        expect(value, isNull);
      });
      
      test('should delete values', () async {
        await db.put('to_delete', 'value');
        expect(await db.get('to_delete'), equals('value'));
        
        await db.delete('to_delete');
        expect(await db.get('to_delete'), isNull);
      });
      
      test('should check key existence', () async {
        await db.put('exists', 'yes');
        
        expect(await db.exists('exists'), isTrue);
        expect(await db.exists('not_exists'), isFalse);
      });
    });
    
    group('Batch Operations', () {
      test('should perform batch put operations', () async {
        final items = {
          'item:1': {'name': 'Item 1', 'value': 100},
          'item:2': {'name': 'Item 2', 'value': 200},
          'item:3': {'name': 'Item 3', 'value': 300},
        };
        
        await db.putAll(items);
        
        for (final entry in items.entries) {
          final retrieved = await db.get(entry.key);
          expect(retrieved, equals(entry.value));
        }
      });
      
      test('should perform batch delete operations', () async {
        // Setup
        await db.putAll({
          'del:1': 'value1',
          'del:2': 'value2',
          'del:3': 'value3',
          'keep:1': 'keeper',
        });
        
        // Delete batch
        await db.deleteAll(['del:1', 'del:2', 'del:3']);
        
        // Verify
        expect(await db.get('del:1'), isNull);
        expect(await db.get('del:2'), isNull);
        expect(await db.get('del:3'), isNull);
        expect(await db.get('keep:1'), equals('keeper'));
      });
    });
    
    group('Query Operations', () {
      setUp(() async {
        // Add test data
        await db.putAll({
          'user:1': {'name': 'Alice', 'age': 25},
          'user:2': {'name': 'Bob', 'age': 30},
          'user:3': {'name': 'Charlie', 'age': 35},
          'product:1': {'name': 'Laptop', 'price': 999},
          'product:2': {'name': 'Mouse', 'price': 29},
          'setting:theme': 'dark',
          'setting:lang': 'en',
        });
      });
      
      test('should query keys by pattern', () async {
        final userKeys = await db.query('user:*');
        expect(userKeys.length, equals(3));
        expect(userKeys, contains('user:1'));
        expect(userKeys, contains('user:2'));
        expect(userKeys, contains('user:3'));
        
        final productKeys = await db.query('product:*');
        expect(productKeys.length, equals(2));
        
        final settingKeys = await db.query('setting:*');
        expect(settingKeys.length, equals(2));
      });
      
      test('should get all values by pattern', () async {
        final users = await db.getAll('user:*');
        expect(users.length, equals(3));
        expect(users['user:1']['name'], equals('Alice'));
        expect(users['user:2']['name'], equals('Bob'));
        expect(users['user:3']['name'], equals('Charlie'));
      });
      
      test('should count keys by pattern', () async {
        expect(await db.count('user:*'), equals(3));
        expect(await db.count('product:*'), equals(2));
        expect(await db.count('setting:*'), equals(2));
        expect(await db.count('*'), equals(7));
        expect(await db.count('nonexistent:*'), equals(0));
      });
      
      test('should query all keys with wildcard', () async {
        final allKeys = await db.query('*');
        expect(allKeys.length, equals(7));
      });
    });
    
    group('Clear Operation', () {
      test('should clear all data', () async {
        // Add data
        await db.putAll({
          'key1': 'value1',
          'key2': 'value2',
          'key3': 'value3',
        });
        
        expect(await db.count('*'), equals(3));
        
        // Clear
        await db.clear();
        
        // Verify
        expect(await db.count('*'), equals(0));
        expect(await db.get('key1'), isNull);
        expect(await db.get('key2'), isNull);
        expect(await db.get('key3'), isNull);
      });
    });
    
    group('Real-time Watching', () {
      test('should watch all changes', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db.watch().listen(events.add);
        
        // Make changes
        await db.put('watch:1', 'value1');
        await db.put('watch:2', 'value2');
        await db.delete('watch:1');
        
        // Wait for events to propagate
        await Future.delayed(Duration(milliseconds: 100));
        
        // Verify events
        expect(events.length, greaterThanOrEqualTo(3));
        
        subscription.cancel();
      });
      
      test('should watch specific pattern', () async {
        final events = <DatabaseChangeEvent>[];
        final subscription = db.watch('user:*').listen(events.add);
        
        // Make changes
        await db.put('user:new', {'name': 'David'});
        await db.put('product:new', {'name': 'Keyboard'}); // Should not trigger
        
        // Wait for events
        await Future.delayed(Duration(milliseconds: 100));
        
        // Verify only user events are received
        expect(events.length, equals(1));
        expect(events.first.key, equals('user:new'));
        
        subscription.cancel();
      });
    });
    
    group('Database Info', () {
      test('should return database information', () async {
        await db.putAll({
          'test:1': 'value1',
          'test:2': 'value2',
        });
        
        final info = await db.info();
        
        expect(info.name, isNotNull);
        expect(info.entryCount, greaterThanOrEqualTo(2));
        expect(info.sizeBytes, greaterThanOrEqualTo(0)); // Can be 0 if not yet persisted
      });
    });
    
    group('Advanced API Access', () {
      test('should provide access to advanced API', () async {
        // The advanced property should return the full ReaxDB instance
        expect(db.advanced, isA<ReaxDB>());
        
        // Should be able to use advanced features
        await db.advanced.transaction((txn) async {
          await txn.put('txn:1', 'value1');
          await txn.put('txn:2', 'value2');
        });
        
        expect(await db.get('txn:1'), equals('value1'));
        expect(await db.get('txn:2'), equals('value2'));
      });
    });
    
    group('Encryption', () {
      test('should create encrypted database', () async {
        final encryptedDb = await ReaxDB.simple(
          'encrypted_test',
          encrypted: true,
          path: 'test_encrypted',
        );
        
        await encryptedDb.put('secret', 'my secret data');
        expect(await encryptedDb.get('secret'), equals('my secret data'));
        
        await encryptedDb.close();
        
        // Clean up
        Directory('test_encrypted').deleteSync(recursive: true);
      });
    });
    
    group('Edge Cases', () {
      test('should handle empty string keys', () async {
        await db.put('', 'empty key value');
        expect(await db.get(''), equals('empty key value'));
      });
      
      test('should handle special characters in keys', () async {
        final specialKey = 'key:with/special@chars#123';
        await db.put(specialKey, 'special value');
        expect(await db.get(specialKey), equals('special value'));
      });
      
      test('should handle large values', () async {
        final largeList = List.generate(10000, (i) => 'item_$i');
        await db.put('large_list', largeList);
        
        final retrieved = await db.get('large_list');
        expect(retrieved.length, equals(10000));
        expect(retrieved[0], equals('item_0'));
        expect(retrieved[9999], equals('item_9999'));
      });
      
      test('should handle null values in maps', () async {
        final data = {
          'name': 'Test',
          'optional': null,
          'nested': {
            'value': 123,
            'nullField': null,
          }
        };
        
        await db.put('nullable', data);
        final retrieved = await db.get('nullable');
        
        expect(retrieved['name'], equals('Test'));
        expect(retrieved['optional'], isNull);
        expect(retrieved['nested']['value'], equals(123));
        expect(retrieved['nested']['nullField'], isNull);
      });
      
      test('should overwrite existing values', () async {
        await db.put('key', 'original');
        expect(await db.get('key'), equals('original'));
        
        await db.put('key', 'updated');
        expect(await db.get('key'), equals('updated'));
        
        await db.put('key', {'complex': 'object'});
        expect(await db.get('key'), equals({'complex': 'object'}));
      });
    });
    
    group('Performance', () {
      test('should handle rapid sequential operations', () async {
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < 1000; i++) {
          await db.put('perf:$i', {'index': i, 'data': 'test_$i'});
        }
        
        stopwatch.stop();
        print('1000 sequential puts: ${stopwatch.elapsedMilliseconds}ms');
        
        expect(await db.count('perf:*'), equals(1000));
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should be fast
      });
      
      test('should handle batch operations efficiently', () async {
        final items = <String, dynamic>{};
        for (int i = 0; i < 1000; i++) {
          items['batch:$i'] = {'index': i, 'data': 'test_$i'};
        }
        
        final stopwatch = Stopwatch()..start();
        await db.putAll(items);
        stopwatch.stop();
        
        print('Batch put of 1000 items: ${stopwatch.elapsedMilliseconds}ms');
        
        expect(await db.count('batch:*'), equals(1000));
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Batch should be faster
      });
    });
  });
  
  group('SimpleReaxDB Static Methods', () {
    test('should create database with quickStart method', () async {
      final db = await ReaxDB.quickStart('quickstart_test');
      
      await db.put('test', 'value');
      expect(await db.get('test'), equals('value'));
      
      await db.close();
      Directory('quickstart_test').deleteSync(recursive: true);
    });
  });
}