import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';
import 'dart:async';

void main() {
  group('Enhanced Transaction Tests', () {
    late ReaxDB db;
    final testPath = 'test/enhanced_transaction_test_db';

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

    group('Transaction Types', () {
      test('should create read-write transaction', () async {
        final txn = await db.beginEnhancedTransaction(
          type: TransactionType.readWrite,
        );

        expect(txn.type, equals(TransactionType.readWrite));
        expect(txn.isReadOnly, isFalse);
        expect(txn.isActive, isTrue);

        await txn.rollback();
      });

      test('should create read-only transaction', () async {
        final txn = await db.beginReadOnlyTransaction();

        expect(txn.type, equals(TransactionType.readOnly));
        expect(txn.isReadOnly, isTrue);
        expect(txn.isActive, isTrue);

        await txn.rollback();
      });

      test('should prevent writes in read-only transaction', () async {
        final txn = await db.beginReadOnlyTransaction();

        expect(
          () async => await txn.put('key', 'value', (k, v) async {}),
          throwsStateError,
        );

        expect(
          () async => await txn.delete('key', (k) async {}),
          throwsStateError,
        );

        await txn.rollback();
      });
    });

    group('Isolation Levels', () {
      test('should support different isolation levels', () async {
        final txn1 = await db.beginEnhancedTransaction(
          isolationLevel: IsolationLevel.readUncommitted,
        );
        expect(txn1.isolationLevel, equals(IsolationLevel.readUncommitted));
        await txn1.rollback();

        final txn2 = await db.beginEnhancedTransaction(
          isolationLevel: IsolationLevel.serializable,
        );
        expect(txn2.isolationLevel, equals(IsolationLevel.serializable));
        await txn2.rollback();
      });
    });

    group('Savepoints', () {
      test('should create and rollback to savepoint', () async {
        final txn = await db.beginEnhancedTransaction();

        // Make initial changes
        await txn.put('key1', 'value1', (k, v) async {});
        await txn.put('key2', 'value2', (k, v) async {});

        // Create savepoint
        final sp1 = await txn.savepoint('sp1');
        expect(sp1, equals('sp1'));

        // Make more changes
        await txn.put('key3', 'value3', (k, v) async {});
        await txn.put('key4', 'value4', (k, v) async {});

        // Rollback to savepoint
        await txn.rollbackToSavepoint('sp1');

        // key3 and key4 changes should be rolled back
        final stats = txn.getStats();
        expect(stats['changes'], equals(2)); // Only key1 and key2

        await txn.rollback();
      });

      test('should release savepoint', () async {
        final txn = await db.beginEnhancedTransaction();

        await txn.savepoint('sp1');
        await txn.savepoint('sp2');

        await txn.releaseSavepoint('sp1');

        // Should throw when trying to rollback to released savepoint
        expect(
          () async => await txn.rollbackToSavepoint('sp1'),
          throwsStateError,
        );

        await txn.rollback();
      });

      test('should handle multiple savepoints', () async {
        final txn = await db.beginEnhancedTransaction();

        await txn.put('key1', 'value1', (k, v) async {});
        await txn.savepoint('sp1');

        await txn.put('key2', 'value2', (k, v) async {});
        await txn.savepoint('sp2');

        await txn.put('key3', 'value3', (k, v) async {});
        await txn.savepoint('sp3');

        // Rollback to sp2
        await txn.rollbackToSavepoint('sp2');

        final stats = txn.getStats();
        expect(stats['changes'], equals(2)); // key1 and key2
        expect(stats['savepoints'], equals(2)); // sp1 and sp2

        await txn.rollback();
      });
    });

    group('Nested Transactions', () {
      test('should create nested transaction', () async {
        final parent = await db.beginEnhancedTransaction();
        final nested = await parent.beginNested();

        expect(nested.id, contains('nested'));
        expect(nested.isActive, isTrue);

        await nested.rollback();
        await parent.rollback();
      });

      test('should inherit parent transaction properties', () async {
        final parent = await db.beginEnhancedTransaction(
          isolationLevel: IsolationLevel.serializable,
          timeout: Duration(seconds: 30),
        );

        final nested = await parent.beginNested();

        expect(nested.isolationLevel, equals(IsolationLevel.serializable));
        expect(nested.timeout, equals(Duration(seconds: 30)));

        await nested.rollback();
        await parent.rollback();
      });

      test('should handle nested transaction commit', () async {
        final parent = await db.beginEnhancedTransaction();

        await parent.put('parent_key', 'parent_value', (k, v) async {});

        final nested = await parent.beginNested();
        await nested.put('nested_key', 'nested_value', (k, v) async {});

        // Commit nested transaction
        await nested.commit((changes) async {
          // In real implementation, changes would be applied
        });

        expect(nested.isActive, isFalse);

        await parent.rollback();
      });
    });

    group('Transaction Timeout', () {
      test('should timeout after specified duration', () async {
        final txn = await db.beginEnhancedTransaction(
          timeout: Duration(milliseconds: 100),
        );

        // Wait for timeout
        await Future.delayed(Duration(milliseconds: 150));

        expect(txn.hasTimedOut, isTrue);

        // Operations should throw timeout exception
        expect(
          () async => await txn.put('key', 'value', (k, v) async {}),
          throwsA(isA<TimeoutException>()),
        );

        await txn.rollback();
      });

      test('should not timeout if duration not exceeded', () async {
        final txn = await db.beginEnhancedTransaction(
          timeout: Duration(seconds: 10),
        );

        expect(txn.hasTimedOut, isFalse);

        await txn.put('key', 'value', (k, v) async {});

        await txn.rollback();
      });
    });

    group('Retry Logic', () {
      test('should retry on failure', () async {
        int attempts = 0;
        final result = await db.withTransaction<String>(
          (txn) async {
            attempts++;
            if (attempts < 3) {
              throw Exception('Simulated failure');
            }
            return 'success';
          },
          maxRetries: 3,
          retryDelay: Duration(milliseconds: 10),
        );

        expect(result, equals('success'));
        expect(attempts, equals(3));
      });

      test('should fail after max retries', () async {
        int attempts = 0;

        try {
          await db.withTransaction<String>(
            (txn) async {
              attempts++;
              throw Exception('Always fails');
            },
            maxRetries: 2,
            retryDelay: Duration(milliseconds: 10),
          );
        } catch (e) {
          // Expected to fail
        }

        expect(attempts, equals(2));
      });

      test('should use exponential backoff', () async {
        final startTime = DateTime.now();
        int attempts = 0;

        try {
          await db.withTransaction<String>(
            (txn) async {
              attempts++;
              throw Exception('Force retry');
            },
            maxRetries: 3,
            retryDelay: Duration(milliseconds: 100),
          );
        } catch (e) {
          // Expected
        }

        final duration = DateTime.now().difference(startTime);
        // Should take at least 100 + 200 = 300ms (with jitter could be ~400ms)
        expect(duration.inMilliseconds, greaterThan(300));
      });
    });

    group('Transaction Statistics', () {
      test('should track transaction statistics', () async {
        final txn = await db.beginEnhancedTransaction();

        await txn.put('key1', 'value1', (k, v) async {});
        await txn.put('key2', 'value2', (k, v) async {});
        await txn.savepoint('sp1');

        final nested = await txn.beginNested();
        await nested.rollback();

        // Add a small delay to ensure duration > 0
        await Future.delayed(Duration(milliseconds: 1));

        final stats = txn.getStats();

        expect(stats['id'], contains('txn-'));
        expect(stats['type'], contains('readWrite'));
        expect(stats['changes'], equals(2));
        expect(stats['savepoints'], equals(1));
        expect(stats['nestedTransactions'], equals(1));
        expect(stats['isActive'], isTrue);
        expect(stats['duration'], greaterThanOrEqualTo(0));

        await txn.rollback();
      });
    });

    group('Transaction Manager', () {
      test('should track active transactions', () async {
        final manager = EnhancedTransactionManager();

        final txn1 = await manager.begin();
        final txn2 = await manager.begin();

        expect(manager.activeTransactionCount, equals(2));
        expect(manager.activeTransactions.length, equals(2));

        await txn1.rollback();
        await txn2.rollback();
      });

      test('should close all active transactions', () async {
        final manager = EnhancedTransactionManager();

        final txn1 = await manager.begin();
        final txn2 = await manager.begin();
        final txn3 = await manager.begin();

        await manager.closeAll();

        expect(txn1.isActive, isFalse);
        expect(txn2.isActive, isFalse);
        expect(txn3.isActive, isFalse);
        expect(manager.activeTransactionCount, equals(0));
      });
    });

    group('Integration Tests', () {
      test('should integrate with ReaxDB operations', () async {
        // Setup initial data
        await db.put('account:1', {'balance': 1000});
        await db.put('account:2', {'balance': 500});

        // Perform transaction with retry
        await db.withTransaction((txn) async {
          // In a real implementation, these would use the transaction
          final account1 = await db.get('account:1');
          final account2 = await db.get('account:2');

          expect(account1!['balance'], equals(1000));
          expect(account2!['balance'], equals(500));

          // Transfer money
          await db.put('account:1', {'balance': 900});
          await db.put('account:2', {'balance': 600});
        });

        // Verify the changes
        final finalAccount1 = await db.get('account:1');
        final finalAccount2 = await db.get('account:2');

        expect(finalAccount1!['balance'], equals(900));
        expect(finalAccount2!['balance'], equals(600));
      });

      test('should handle concurrent transactions', () async {
        // Start multiple transactions
        final futures = List.generate(5, (i) async {
          return db.withTransaction((txn) async {
            await db.put('concurrent:$i', {'value': i});
            return i;
          });
        });

        final results = await Future.wait(futures);

        expect(results, equals([0, 1, 2, 3, 4]));

        // Verify all values were written
        for (int i = 0; i < 5; i++) {
          final value = await db.get('concurrent:$i');
          expect(value!['value'], equals(i));
        }
      });
    });
  });
}