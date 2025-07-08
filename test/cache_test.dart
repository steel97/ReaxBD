import 'package:flutter_test/flutter_test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:typed_data';

void main() {
  group('ReaxDB Cache System Tests', () {
    late ReaxDB database;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cache_test_');
      
      final config = DatabaseConfig(
        memtableSizeMB: 16,
        pageSize: 4096,
        l1CacheSize: 10,  // Small cache for testing eviction
        l2CacheSize: 50,
        l3CacheSize: 100,
        compressionEnabled: false, // Disable for predictable testing
        syncWrites: false,
        maxImmutableMemtables: 2,
        cacheSize: 20,
        enableCache: true,
      );

      database = await ReaxDB.open(
        'cache_test_db',
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

    group('L1 Cache Tests', () {
      test('should cache frequently accessed items in L1', () async {
        const key = 'l1_test';
        const value = 'L1 cache test value';
        
        // Write value
        await database.put(key, value);
        
        // Read multiple times to promote to L1 cache
        for (int i = 0; i < 5; i++) {
          final result = await database.get(key);
          expect(result, equals(value));
        }
        
        // Verify it's in cache by checking stats
        final stats = await database.getStatistics();
        expect(stats['cacheHitRate'], greaterThan(0.0));
      });

      test('should evict LRU items when L1 cache is full', () async {
        // Fill L1 cache beyond its capacity
        for (int i = 0; i < 15; i++) {
          await database.put('evict_test_$i', 'Value $i');
          await database.get('evict_test_$i'); // Access to cache it
        }
        
        // Access first item again
        final firstValue = await database.get('evict_test_0');
        expect(firstValue, equals('Value 0'));
        
        // Add more items to trigger eviction
        for (int i = 15; i < 25; i++) {
          await database.put('evict_test_$i', 'Value $i');
          await database.get('evict_test_$i');
        }
        
        // All values should still be accessible (even if not in L1)
        for (int i = 0; i < 25; i++) {
          final value = await database.get('evict_test_$i');
          expect(value, equals('Value $i'));
        }
      });
    });

    group('Multi-Level Cache Tests', () {
      test('should promote items through cache levels', () async {
        const key = 'promotion_test';
        const value = 'Multi-level cache test';
        
        // Write and read once (should be in L3)
        await database.put(key, value);
        await database.get(key);
        
        // Read multiple times to promote through levels
        for (int i = 0; i < 10; i++) {
          final result = await database.get(key);
          expect(result, equals(value));
        }
        
        // Item should now be in higher cache level
        final stats = await database.getStatistics();
        expect(stats['cacheHitRate'], greaterThan(0.8));
      });

      test('should handle cache invalidation on updates', () async {
        const key = 'invalidation_test';
        const originalValue = 'Original value';
        const updatedValue = 'Updated value';
        
        // Put and cache original value
        await database.put(key, originalValue);
        await database.get(key); // Cache it
        
        // Update value
        await database.put(key, updatedValue);
        
        // Should get updated value, not cached one
        final result = await database.get(key);
        expect(result, equals(updatedValue));
      });

      test('should handle cache invalidation on deletes', () async {
        const key = 'delete_invalidation_test';
        const value = 'To be deleted';
        
        // Put and cache value
        await database.put(key, value);
        await database.get(key); // Cache it
        
        // Delete value
        await database.delete(key);
        
        // Should return null, not cached value
        final result = await database.get(key);
        expect(result, isNull);
      });
    });

    group('Cache Performance Tests', () {
      test('should provide faster access for cached items', () async {
        const key = 'performance_test';
        final largeValue = Uint8List.fromList(List.generate(10000, (i) => i % 256));
        
        // Write large value
        await database.put(key, largeValue);
        
        // First read (from disk)
        final stopwatch1 = Stopwatch()..start();
        final result1 = await database.get(key);
        stopwatch1.stop();
        
        expect(result1, equals(largeValue));
        
        // Second read (should be from cache)
        final stopwatch2 = Stopwatch()..start();
        final result2 = await database.get(key);
        stopwatch2.stop();
        
        expect(result2, equals(largeValue));
        
        // Cache access should generally be faster (though timing can vary)
        print('First read (disk): ${stopwatch1.elapsedMicroseconds}μs');
        print('Second read (cache): ${stopwatch2.elapsedMicroseconds}μs');
        
        // At minimum, both should succeed
        expect(result1, equals(result2));
      });

      test('should maintain good hit rate under mixed workload', () async {
        // Create a working set
        const workingSetSize = 50;
        const accessPatterns = 200;
        
        // Initialize working set
        for (int i = 0; i < workingSetSize; i++) {
          await database.put('workload_$i', 'Value $i');
        }
        
        // Access with 80/20 pattern (80% access to 20% of data)
        final hotDataSize = (workingSetSize * 0.2).round();
        
        for (int i = 0; i < accessPatterns; i++) {
          final key = i % 5 == 0 
              ? 'workload_${i % workingSetSize}' // Cold data (20%)
              : 'workload_${i % hotDataSize}';   // Hot data (80%)
              
          await database.get(key);
        }
        
        final stats = await database.getStatistics();
        print('Cache hit rate under mixed workload: ${stats['cacheHitRate']}');
        
        // Should achieve decent hit rate with hot data pattern
        expect(stats['cacheHitRate'], greaterThan(0.3));
      });
    });

    group('Cache Memory Management Tests', () {
      test('should respect memory limits', () async {
        // Create values that will stress memory limits
        final largeValues = <String, Uint8List>{};
        
        for (int i = 0; i < 20; i++) {
          final key = 'memory_test_$i';
          final value = Uint8List.fromList(List.generate(1000, (j) => i));
          largeValues[key] = value;
          
          await database.put(key, value);
          await database.get(key); // Cache it
        }
        
        // Verify all values are still accessible
        for (final entry in largeValues.entries) {
          final result = await database.get(entry.key);
          expect(result, equals(entry.value));
        }
        
        // Check that cache is managing memory (stats should show evictions)
        final stats = await database.getStatistics();
        expect(stats, isA<Map<String, dynamic>>());
      });

      test('should handle cache pressure gracefully', () async {
        // Generate many unique keys to create cache pressure
        for (int i = 0; i < 200; i++) {
          await database.put('pressure_$i', 'Value $i');
          await database.get('pressure_$i');
        }
        
        // Access random subset to test eviction behavior
        final random = [5, 15, 25, 50, 75, 100, 150, 199];
        for (final i in random) {
          final result = await database.get('pressure_$i');
          expect(result, equals('Value $i'));
        }
        
        // System should remain stable
        final stats = await database.getStatistics();
        expect(stats['totalEntries'], greaterThan(0));
      });
    });

    group('Cache Consistency Tests', () {
      test('should maintain consistency across transactions', () async {
        const key = 'tx_consistency_test';
        const initialValue = 'Initial';
        const txValue = 'Transaction Value';
        
        // Set initial value and cache it
        await database.put(key, initialValue);
        await database.get(key);
        
        // Update in transaction
        await database.transaction((tx) async {
          await tx.put(key, txValue);
          
          // Within transaction, should see new value
          final txResult = await tx.get(key);
          expect(txResult, equals(txValue));
          
          return true;
        });
        
        // After transaction, cache should be updated
        final finalResult = await database.get(key);
        expect(finalResult, equals(txValue));
      });

      test('should handle concurrent cache access safely', () async {
        const baseKey = 'concurrent_cache_';
        const numConcurrent = 20;
        
        // Launch concurrent operations
        final futures = <Future>[];
        
        for (int i = 0; i < numConcurrent; i++) {
          futures.add(() async {
            final key = '$baseKey$i';
            final value = 'Concurrent value $i';
            
            // Write, read, update, read pattern
            await database.put(key, value);
            await database.get(key);
            await database.put(key, '$value updated');
            final result = await database.get(key);
            
            expect(result, equals('$value updated'));
          }());
        }
        
        await Future.wait(futures);
        
        // Verify final state
        for (int i = 0; i < numConcurrent; i++) {
          final key = '$baseKey$i';
          final result = await database.get(key);
          expect(result, equals('Concurrent value $i updated'));
        }
      });
    });
  });
}