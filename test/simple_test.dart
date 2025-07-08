import 'package:flutter_test/flutter_test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';

void main() {
  group('ReaxDB Simple Tests', () {
    late ReaxDB database;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('simple_test_');
      
      final config = DatabaseConfig(
        memtableSizeMB: 16,
        pageSize: 4096,
        l1CacheSize: 10,
        l2CacheSize: 50,
        l3CacheSize: 100,
        compressionEnabled: false,
        syncWrites: false,
        maxImmutableMemtables: 2,
        cacheSize: 20,
        enableCache: true,
      );

      database = await ReaxDB.open(
        'simple_test_db',
        config: config,
        path: tempDir.path,
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should put and get a simple value', () async {
      const key = 'simple_key';
      const value = 'simple_value';
      
      await database.put(key, value);
      final result = await database.get<String>(key);
      
      expect(result, equals(value));
    });

    test('should handle null values', () async {
      const key = 'null_key';
      
      await database.put(key, null);
      final result = await database.get(key);
      
      expect(result, isNull);
    });

    test('should delete values', () async {
      const key = 'delete_key';
      const value = 'to_be_deleted';
      
      await database.put(key, value);
      expect(await database.get(key), equals(value));
      
      await database.delete(key);
      expect(await database.get(key), isNull);
    });

    test('should handle non-existent keys', () async {
      final result = await database.get('non_existent');
      expect(result, isNull);
    });

    test('should provide database info', () async {
      final info = await database.getDatabaseInfo();
      
      expect(info, isA<DatabaseInfo>());
      expect(info.name, equals('simple_test_db'));
      expect(info.path, isNotEmpty);
    });

    test('should provide database statistics', () async {
      // Add some data first
      await database.put('stats_test', 'test_value');
      
      final stats = await database.getStatistics();
      
      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('totalEntries'), isTrue);
    });
  });
}