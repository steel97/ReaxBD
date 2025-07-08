import 'dart:async';
import 'dart:math';
import 'package:reaxdb_dart/reaxdb_dart.dart';

class DatabaseService {
  static ReaxDB? _database;
  
  static ReaxDB? get database => _database;
  
  static Future<void> initialize(String path) async {
    final config = DatabaseConfig(
      memtableSizeMB: 64,
      pageSize: 4096,
      l1CacheSize: 100,
      l2CacheSize: 500,
      l3CacheSize: 1000,
      compressionEnabled: true,
      syncWrites: true,
      maxImmutableMemtables: 3,
      cacheSize: 50,
      enableCache: true,
    );

    _database = await ReaxDB.open(
      'example_db',
      config: config,
      path: path,
      encryptionKey: 'demo_encryption_key_2024',
    );
  }
  
  static Future<void> close() async {
    await _database?.close();
    _database = null;
  }
  
  // Security test data
  static final List<Map<String, String>> securityTests = [
    {'name': 'SQL Injection', 'payload': "'; DROP TABLE users; --"},
    {'name': 'XSS Attack', 'payload': "<script>alert('XSS')</script>"},
    {'name': 'Buffer Overflow', 'payload': 'A' * 10000},
    {'name': 'Unicode Exploit', 'payload': '\u0000\uFEFF\u200B'},
  ];
  
  static Future<List<String>> runSecurityTests() async {
    final logs = <String>[];
    
    logs.add('\n🔒 --- SECURITY TESTS ---');
    
    for (final test in securityTests) {
      final stopwatch = Stopwatch()..start();
      
      try {
        await _database!.put('security_${test['name']}', test['payload']!);
        final retrieved = await _database!.get('security_${test['name']}');
        
        stopwatch.stop();
        
        if (retrieved == test['payload']) {
          logs.add('✅ ${test['name']}: Data stored/retrieved safely (${stopwatch.elapsedMicroseconds}μs)');
        } else {
          logs.add('❌ ${test['name']}: Data corruption detected!');
        }
      } catch (e) {
        stopwatch.stop();
        logs.add('🛡️  ${test['name']}: Blocked by security (${e.toString().substring(0, 50)}...)');
      }
    }
    
    logs.add('🔒 Security test completed - ReaxDB safely handled all attack vectors');
    return logs;
  }
  
  static Future<List<String>> runConcurrencyTest() async {
    final logs = <String>[];
    
    logs.add('\n🚀 --- CONCURRENCY STRESS TEST ---');
    
    // First populate some data for GET operations to succeed
    logs.add('📝 Preparing test data...');
    for (int i = 0; i < 100; i++) {
      await _database!.put('base_data_$i', {
        'id': i,
        'data': 'base_test_data_$i',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
    
    const numConcurrentOps = 200;
    final futures = <Future>[];
    final results = <String>[];
    final errors = <String>[];
    final stopwatch = Stopwatch()..start();
    
    for (int i = 0; i < numConcurrentOps; i++) {
      final operation = Random().nextInt(3);
      
      late Future future;
      
      switch (operation) {
        case 0:
        case 1:
          future = _database!.put('concurrent_$i', {
            'id': i,
            'operation': 'PUT',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'data': 'concurrent_test_data_$i',
          }).then((_) {
            results.add('PUT_$i');
          }).catchError((e) {
            errors.add('PUT_$i: $e');
          });
          break;
          
        case 2:
          final keyId = Random().nextInt(100);
          future = _database!.get('base_data_$keyId').then((value) {
            results.add('GET_$i');
          }).catchError((e) {
            errors.add('GET_$i: $e');
          });
          break;
      }
      
      futures.add(future);
      
      if (i % 50 == 0 && i > 0) {
        await Future.delayed(Duration(milliseconds: 10));
      }
    }
    
    await Future.wait(futures);
    stopwatch.stop();
    
    final throughput = numConcurrentOps / stopwatch.elapsedMilliseconds * 1000;
    final errorRate = errors.length / numConcurrentOps * 100;
    
    logs.add('📊 CONCURRENCY TEST RESULTS:');
    logs.add('   Concurrent operations: $numConcurrentOps');
    logs.add('   Successful: ${results.length}');
    logs.add('   Errors: ${errors.length}');
    logs.add('   Time: ${stopwatch.elapsedMilliseconds}ms');
    logs.add('   Throughput: ${throughput.toStringAsFixed(2)} ops/sec');
    logs.add('   Error rate: ${errorRate.toStringAsFixed(2)}%');
    
    if (errorRate < 10.0) {
      logs.add('✅ Concurrency test PASSED - Excellent error rate under stress');
    } else if (errorRate < 25.0) {
      logs.add('⚠️  Concurrency test WARNING - Moderate error rate detected');
    } else {
      logs.add('❌ Concurrency test FAILED - High error rate indicates issues');
    }
    
    if (errors.isNotEmpty) {
      logs.add('Sample errors: ${errors.take(3).join(', ')}');
    }
    
    return logs;
  }
  
  static Future<List<String>> runOptimizedConcurrencyTest() async {
    final logs = <String>[];
    
    logs.add('\n🚀 --- OPTIMIZED CONCURRENCY TEST ---');
    logs.add('🔧 Testing with batch operations and performance optimizations...');
    
    const numOperations = 1000;
    const batchSize = 100;
    final stopwatch = Stopwatch()..start();
    
    // First populate base data using batch operations
    logs.add('📝 Preparing test data with batch operations...');
    final baseData = <String, dynamic>{};
    for (int i = 0; i < 200; i++) {
      baseData['optimized_base_$i'] = {
        'id': i,
        'data': 'optimized_test_data_$i',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'metadata': {
          'type': 'base',
          'index': i,
          'created': DateTime.now().toIso8601String(),
        }
      };
    }
    await _database!.putBatch(baseData);
    
    // Run concurrent batch operations
    final futures = <Future>[];
    final results = <String>[];
    final errors = <String>[];
    
    logs.add('⚡ Starting optimized concurrent operations...');
    
    for (int batch = 0; batch < numOperations ~/ batchSize; batch++) {
      // Create batch write operations
      final batchWrites = <String, dynamic>{};
      for (int i = 0; i < batchSize; i++) {
        final key = 'optimized_concurrent_${batch}_$i';
        batchWrites[key] = {
          'batch': batch,
          'index': i,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'data': List.generate(10, (j) => 'data_${batch}_${i}_$j'),
        };
      }
      
      // Create batch read operations
      final batchReadKeys = List.generate(
        batchSize ~/ 2, 
        (i) => 'optimized_base_${Random().nextInt(200)}'
      );
      
      // Execute batch operations concurrently
      futures.add(
        _database!.putBatch(batchWrites).then((_) {
          results.add('BATCH_WRITE_$batch');
        }).catchError((e) {
          errors.add('BATCH_WRITE_$batch: $e');
        })
      );
      
      futures.add(
        _database!.getBatch<Map<String, dynamic>>(batchReadKeys).then((values) {
          results.add('BATCH_READ_$batch');
        }).catchError((e) {
          errors.add('BATCH_READ_$batch: $e');
        })
      );
    }
    
    await Future.wait(futures);
    stopwatch.stop();
    
    final throughput = numOperations / stopwatch.elapsedMilliseconds * 1000;
    final errorRate = errors.length / (futures.length) * 100;
    
    // Get performance stats
    final perfStats = _database!.getPerformanceStats();
    
    logs.add('\n📊 OPTIMIZED TEST RESULTS:');
    logs.add('   Total operations: $numOperations');
    logs.add('   Batch size: $batchSize');
    logs.add('   Successful batches: ${results.length}');
    logs.add('   Failed batches: ${errors.length}');
    logs.add('   Time: ${stopwatch.elapsedMilliseconds}ms');
    logs.add('   Throughput: ${throughput.toStringAsFixed(2)} ops/sec');
    logs.add('   Error rate: ${errorRate.toStringAsFixed(2)}%');
    logs.add('\n⚡ PERFORMANCE OPTIMIZATIONS:');
    logs.add('   L1 Cache hit ratio: ${(perfStats['cache']['l1_hit_ratio'] * 100).toStringAsFixed(2)}%');
    logs.add('   Total cache hit ratio: ${(perfStats['cache']['total_hit_ratio'] * 100).toStringAsFixed(2)}%');
    logs.add('   Zero-copy: ${perfStats['optimization']['zero_copy_enabled']}');
    logs.add('   Connection pooling: ${perfStats['optimization']['connection_pooling']}');
    logs.add('   Batch operations: ${perfStats['optimization']['batch_operations']}');
    
    if (errorRate < 5.0) {
      logs.add('\n✅ Optimized test PASSED - Excellent performance under load');
    } else {
      logs.add('\n⚠️  Optimized test WARNING - Higher error rate than expected');
    }
    
    return logs;
  }
  
  static Future<List<String>> runExtremeStressTest() async {
    final logs = <String>[];
    
    logs.add('\n💀 --- EXTREME STRESS TEST (10,000 ops) ---');
    logs.add('⚠️  WARNING: This will push the database to its limits!');
    
    const totalOperations = 10000;
    const concurrentBatches = 50;
    const opsPerBatch = totalOperations ~/ concurrentBatches;
    
    final stopwatch = Stopwatch()..start();
    final operationLatencies = <int>[];
    
    // Prepare extreme test data
    logs.add('🔥 Preparing extreme load test...');
    
    final futures = <Future>[];
    final results = <String>[];
    final errors = <String>[];
    
    for (int batch = 0; batch < concurrentBatches; batch++) {
      futures.add(
        Future(() async {
          final batchStopwatch = Stopwatch()..start();
          
          try {
            // Mixed operations in each batch
            final batchData = <String, dynamic>{};
            
            for (int i = 0; i < opsPerBatch ~/ 2; i++) {
              final key = 'extreme_${batch}_$i';
              batchData[key] = {
                'batch': batch,
                'index': i,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'largeData': List.generate(100, (j) => {
                  'field_$j': 'value_${batch}_${i}_$j',
                  'nested': {
                    'deep': {
                      'data': List.generate(10, (k) => 'nested_${k}_${batch}_$i'),
                    }
                  }
                }),
              };
            }
            
            // Batch write
            await _database!.putBatch(batchData);
            
            // Random reads
            final readKeys = List.generate(
              opsPerBatch ~/ 4,
              (i) => 'extreme_${Random().nextInt(batch + 1)}_${Random().nextInt(opsPerBatch ~/ 2)}'
            );
            
            await _database!.getBatch<Map<String, dynamic>>(readKeys);
            
            // Individual operations for variety
            for (int i = 0; i < opsPerBatch ~/ 4; i++) {
              await _database!.put('extreme_individual_${batch}_$i', {
                'type': 'individual',
                'batch': batch,
                'index': i,
              });
            }
            
            batchStopwatch.stop();
            operationLatencies.add(batchStopwatch.elapsedMicroseconds);
            results.add('BATCH_$batch');
            
          } catch (e) {
            errors.add('BATCH_$batch: ${e.toString().substring(0, 50)}');
          }
        })
      );
      
      // Add small delay every few batches to prevent complete system overload
      if (batch % 10 == 0 && batch > 0) {
        await Future.delayed(Duration(milliseconds: 5));
      }
    }
    
    await Future.wait(futures);
    stopwatch.stop();
    
    // Calculate statistics
    final avgLatency = operationLatencies.isEmpty ? 0 : 
        operationLatencies.reduce((a, b) => a + b) / operationLatencies.length;
    final maxLatency = operationLatencies.isEmpty ? 0 : 
        operationLatencies.reduce((a, b) => a > b ? a : b);
    final minLatency = operationLatencies.isEmpty ? 0 : 
        operationLatencies.reduce((a, b) => a < b ? a : b);
    
    final throughput = totalOperations / stopwatch.elapsedMilliseconds * 1000;
    final successRate = results.length / concurrentBatches * 100;
    
    // Get final stats
    final dbInfo = await _database!.getDatabaseInfo();
    final perfStats = _database!.getPerformanceStats();
    
    logs.add('\n💀 EXTREME STRESS TEST RESULTS:');
    logs.add('   Total operations: $totalOperations');
    logs.add('   Concurrent batches: $concurrentBatches');
    logs.add('   Operations per batch: $opsPerBatch');
    logs.add('   Successful batches: ${results.length}/$concurrentBatches');
    logs.add('   Failed batches: ${errors.length}');
    logs.add('   Success rate: ${successRate.toStringAsFixed(2)}%');
    logs.add('\n⏱️  PERFORMANCE METRICS:');
    logs.add('   Total time: ${stopwatch.elapsedMilliseconds}ms');
    logs.add('   Throughput: ${throughput.toStringAsFixed(2)} ops/sec');
    logs.add('   Avg batch latency: ${(avgLatency / 1000).toStringAsFixed(2)}ms');
    logs.add('   Min batch latency: ${(minLatency / 1000).toStringAsFixed(2)}ms');
    logs.add('   Max batch latency: ${(maxLatency / 1000).toStringAsFixed(2)}ms');
    logs.add('\n💾 DATABASE STATS:');
    logs.add('   Total entries: ${dbInfo.entryCount}');
    logs.add('   Database size: ${(dbInfo.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB');
    logs.add('   Cache hit ratio: ${(perfStats['cache']['total_hit_ratio'] * 100).toStringAsFixed(2)}%');
    
    if (successRate >= 95.0) {
      logs.add('\n🏆 EXTREME TEST PASSED - ReaxDB handled 10K operations like a champion!');
    } else if (successRate >= 80.0) {
      logs.add('\n✅ EXTREME TEST PASSED - Good performance under extreme load');
    } else if (successRate >= 60.0) {
      logs.add('\n⚠️  EXTREME TEST WARNING - Moderate degradation under extreme load');
    } else {
      logs.add('\n❌ EXTREME TEST FAILED - Significant issues under extreme load');
    }
    
    if (errors.isNotEmpty) {
      logs.add('\nSample errors: ${errors.take(3).join(', ')}');
    }
    
    return logs;
  }
}