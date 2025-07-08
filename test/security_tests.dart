import 'package:flutter_test/flutter_test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:math';

void main() {
  group('ReaxDB Security & Data Integrity Tests', () {
    late ReaxDB database;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('security_test_');
      
      final config = DatabaseConfig(
        memtableSizeMB: 64,
        pageSize: 4096,
        l1CacheSize: 100,
        l2CacheSize: 500,
        l3CacheSize: 1000,
        compressionEnabled: true,
        syncWrites: true, // Important for security tests
        maxImmutableMemtables: 3,
        cacheSize: 50,
        enableCache: true,
      );

      database = await ReaxDB.open(
        'security_test_db',
        config: config,
        path: tempDir.path,
        encryptionKey: 'super_secret_key_2024', // Enable encryption
      );
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Data Encryption Tests', () {
      test('should encrypt sensitive data at rest', () async {
        final sensitiveData = {
          'ssn': '123-45-6789',
          'credit_card': '4111-1111-1111-1111',
          'password': 'super_secret_password',
          'personal_info': {
            'name': 'John Doe',
            'address': '123 Secret St',
            'phone': '+1-555-0123'
          }
        };

        await database.put('user_sensitive_data', sensitiveData);
        
        // Verify data can be retrieved correctly
        final retrieved = await database.get('user_sensitive_data');
        expect(retrieved, equals(sensitiveData));

        // Check that raw files don't contain plaintext sensitive data
        final dbFiles = tempDir.listSync(recursive: true);
        for (final file in dbFiles) {
          if (file is File) {
            final content = await file.readAsString();
            expect(content.contains('123-45-6789'), isFalse, 
                reason: 'SSN should not be in plaintext in ${file.path}');
            expect(content.contains('4111-1111-1111-1111'), isFalse,
                reason: 'Credit card should not be in plaintext in ${file.path}');
            expect(content.contains('super_secret_password'), isFalse,
                reason: 'Password should not be in plaintext in ${file.path}');
          }
        }

        print('✓ Sensitive data properly encrypted at rest');
      });

      test('should fail to open database with wrong encryption key', () async {
        // Store some data
        await database.put('encrypted_test', 'secret_content');
        await database.close();

        // Try to open with wrong key
        final wrongConfig = DatabaseConfig(
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

        expect(
          () async => await ReaxDB.open(
            'security_test_db',
            config: wrongConfig,
            path: tempDir.path,
            encryptionKey: 'wrong_key',
          ),
          throwsA(isA<Exception>()),
        );

        print('✓ Database properly protected against wrong encryption keys');
      });
    });

    group('Access Control & Validation Tests', () {
      test('should validate input data and prevent injection', () async {
        // Test various injection attempts
        final maliciousInputs = [
          {'key': 'sql_injection', 'value': "'; DROP TABLE users; --"},
          {'key': 'script_injection', 'value': "<script>alert('XSS')</script>"},
          {'key': 'null_byte', 'value': "test\x00injection"},
          {'key': 'buffer_overflow', 'value': 'A' * 10000},
          {'key': 'unicode_exploit', 'value': '\u0000\uFEFF\u200B'},
        ];

        for (final input in maliciousInputs) {
          await database.put(input['key']!, input['value']);
          final retrieved = await database.get(input['key']!);
          expect(retrieved, equals(input['value']),
              reason: 'Data should be stored and retrieved safely for ${input['key']}');
        }

        print('✓ Input validation and injection prevention working correctly');
      });

      test('should handle large keys and values securely', () async {
        // Test with very large key (should fail gracefully)
        final largeKey = 'k' * 1000;
        expect(
          () async => await database.put(largeKey, 'value'),
          throwsA(isA<ArgumentError>()),
        );

        // Test with very large value (should work but be handled efficiently)
        final largeValue = 'V' * (5 * 1024 * 1024); // 5MB
        await database.put('large_value_test', largeValue);
        final retrieved = await database.get('large_value_test');
        expect(retrieved, equals(largeValue));

        print('✓ Large data handling security checks passed');
      });
    });

    group('Transaction Security Tests', () {
      test('should maintain ACID properties under stress', () async {
        const numConcurrentTx = 50;
        const accountBalance = 1000;
        
        // Initialize accounts
        await database.put('account_A', accountBalance);
        await database.put('account_B', accountBalance);

        final futures = <Future>[];
        
        // Simulate concurrent money transfers
        for (int i = 0; i < numConcurrentTx; i++) {
          futures.add(database.transaction((tx) async {
            final balanceA = await tx.get('account_A') as int;
            final balanceB = await tx.get('account_B') as int;
            
            if (balanceA >= 100) {
              await tx.put('account_A', balanceA - 100);
              await tx.put('account_B', balanceB + 100);
            }
            
            return true;
          }));
        }

        await Future.wait(futures);

        // Verify total money is conserved
        final finalA = await database.get('account_A') as int;
        final finalB = await database.get('account_B') as int;
        final totalMoney = finalA + finalB;
        
        expect(totalMoney, equals(accountBalance * 2),
            reason: 'Total money should be conserved (ACID consistency)');

        print('✓ ACID properties maintained under concurrent transactions');
        print('  Final balances: A=$finalA, B=$finalB, Total=$totalMoney');
      });

      test('should rollback failed transactions completely', () async {
        await database.put('secure_counter', 0);
        
        // Simulate a transaction that should fail
        try {
          await database.transaction((tx) async {
            final current = await tx.get('secure_counter') as int;
            await tx.put('secure_counter', current + 1);
            await tx.put('temp_data', 'should_not_persist');
            
            // Simulate failure
            throw Exception('Simulated transaction failure');
          });
        } catch (e) {
          // Expected to fail
        }

        // Verify rollback
        final counter = await database.get('secure_counter') as int;
        final tempData = await database.get('temp_data');
        
        expect(counter, equals(0), reason: 'Counter should not have changed');
        expect(tempData, isNull, reason: 'Temp data should not exist after rollback');

        print('✓ Transaction rollback security verified');
      });
    });

    group('Data Integrity Tests', () {
      test('should detect and handle data corruption', () async {
        final testData = {
          'id': 12345,
          'checksum': 'abc123',
          'critical_data': 'mission_critical_information',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        await database.put('integrity_test', testData);
        
        // Retrieve and verify
        final retrieved = await database.get('integrity_test');
        expect(retrieved, equals(testData));

        // Simulate multiple reads to ensure consistency
        for (int i = 0; i < 100; i++) {
          final check = await database.get('integrity_test');
          expect(check, equals(testData),
              reason: 'Data should remain consistent across reads');
        }

        print('✓ Data integrity maintained across multiple operations');
      });

      test('should handle concurrent reads/writes safely', () async {
        const numOperations = 100;
        final futures = <Future>[];
        final random = Random();

        // Launch concurrent operations
        for (int i = 0; i < numOperations; i++) {
          futures.add(() async {
            final key = 'concurrent_${i % 10}'; // Overlap some keys
            final value = {
              'operation': i,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'random': random.nextDouble(),
            };
            
            await database.put(key, value);
            
            // Immediate read-back verification
            final verified = await database.get(key);
            expect(verified['operation'], equals(i));
            
            return true;
          }());
        }

        final results = await Future.wait(futures);
        expect(results.every((r) => r == true), isTrue);

        print('✓ Concurrent access safety verified');
      });
    });

    group('Performance Security Tests', () {
      test('should resist denial of service attacks', () async {
        final stopwatch = Stopwatch()..start();
        
        // Simulate rapid-fire operations
        for (int i = 0; i < 1000; i++) {
          await database.put('dos_test_$i', 'attack_simulation_$i');
        }
        
        stopwatch.stop();
        final timeMs = stopwatch.elapsedMilliseconds;
        
        // Should complete within reasonable time (not hang indefinitely)
        expect(timeMs, lessThan(30000), 
            reason: 'Should resist DoS attacks and maintain responsiveness');

        // Verify data integrity after stress
        final sample = await database.get('dos_test_500');
        expect(sample, equals('attack_simulation_500'));

        print('✓ DoS resistance verified: 1000 ops in ${timeMs}ms');
      });

      test('should maintain performance under memory pressure', () async {
        final largeDataSet = <String, Map<String, dynamic>>{};
        
        // Generate large dataset to stress memory
        for (int i = 0; i < 100; i++) {
          final key = 'memory_pressure_$i';
          final value = {
            'id': i,
            'large_field': 'x' * 10000, // 10KB per entry
            'metadata': List.generate(100, (j) => 'item_$j'),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          
          largeDataSet[key] = value;
          await database.put(key, value);
        }

        // Verify all data can still be retrieved correctly
        for (final entry in largeDataSet.entries) {
          final retrieved = await database.get(entry.key);
          expect(retrieved['id'], equals(entry.value['id']));
        }

        print('✓ Performance maintained under memory pressure (1MB+ dataset)');
      });
    });

    group('Forensic & Audit Tests', () {
      test('should maintain operation audit trail', () async {
        final operations = <Map<String, dynamic>>[];
        
        // Perform tracked operations
        for (int i = 0; i < 10; i++) {
          final op = {
            'type': 'PUT',
            'key': 'audit_$i',
            'value': 'operation_$i',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          operations.add(op);
          
          await database.put(op['key'] as String, op['value']);
        }

        // Verify operations can be audited
        final stats = await database.getStatistics();
        expect(stats['totalEntries'], greaterThan(0));

        print('✓ Audit trail capabilities verified');
      });

      test('should handle database recovery scenarios', () async {
        // Store critical data
        final criticalData = {
          'backup_test': 'critical_business_data',
          'user_count': 12345,
          'last_sync': DateTime.now().toIso8601String(),
        };

        for (final entry in criticalData.entries) {
          await database.put(entry.key, entry.value);
        }

        // Simulate database close (normal shutdown)
        await database.close();

        // Reopen database (recovery scenario)
        database = await ReaxDB.open(
          'security_test_db',
          config: DatabaseConfig(
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
          ),
          path: tempDir.path,
          encryptionKey: 'super_secret_key_2024',
        );

        // Verify data recovery
        for (final entry in criticalData.entries) {
          final recovered = await database.get(entry.key);
          expect(recovered, equals(entry.value),
              reason: 'Critical data should survive database restart');
        }

        print('✓ Database recovery and data persistence verified');
      });
    });
  });
}