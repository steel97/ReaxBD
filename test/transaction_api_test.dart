import 'dart:io';
import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';

void main() {
  group('Transaction API Test', () {
    late String testDbPath;

    setUp(() {
      testDbPath = '${Directory.systemTemp.path}/reaxdb_transaction_api_test_${DateTime.now().millisecondsSinceEpoch}';
    });

    tearDown(() async {
      // Clean up test database
      final dir = Directory(testDbPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('Transaction example from email should work correctly', () async {
      final db = await ReaxDB.open(testDbPath);

      // Use transaction() with a callback - commits automatically on success
      await db.transaction((txn) async {
        await txn.put('account:1', {'balance': 1000});
        await txn.put('account:2', {'balance': 500});

        // Transfer money
        final account1 = await txn.get('account:1');
        final account2 = await txn.get('account:2');

        expect(account1, isNotNull);
        expect(account2, isNotNull);
        expect(account1!['balance'], equals(1000));
        expect(account2!['balance'], equals(500));

        await txn.put('account:1', {'balance': account1['balance'] - 100});
        await txn.put('account:2', {'balance': account2['balance'] + 100});
        
        // No need to manually commit - happens automatically
        // If an exception is thrown, automatic rollback occurs
      });

      // Verify the transaction was committed
      final finalAccount1 = await db.get('account:1');
      final finalAccount2 = await db.get('account:2');

      expect(finalAccount1, isNotNull);
      expect(finalAccount2, isNotNull);
      expect(finalAccount1!['balance'], equals(900));
      expect(finalAccount2!['balance'], equals(600));

      await db.close();
    });

    test('Transaction should rollback on error', () async {
      final db = await ReaxDB.open(testDbPath);

      // First, set up initial data
      await db.put('account:1', {'balance': 1000});
      await db.put('account:2', {'balance': 500});

      // Try a transaction that will fail
      try {
        await db.transaction((txn) async {
          await txn.put('account:1', {'balance': 900});
          await txn.put('account:2', {'balance': 600});
          
          // Force an error
          throw Exception('Simulated error');
        });
      } catch (e) {
        // Expected error
      }

      // Verify the transaction was rolled back
      final account1 = await db.get('account:1');
      final account2 = await db.get('account:2');

      expect(account1!['balance'], equals(1000)); // Should be unchanged
      expect(account2!['balance'], equals(500));  // Should be unchanged

      await db.close();
    });
  });
}