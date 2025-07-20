import 'dart:io';
import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';

void main() {
  group('Persistence Tests', () {
    late String testDbPath;

    setUp(() {
      testDbPath = '${Directory.systemTemp.path}/reaxdb_persistence_test_${DateTime.now().millisecondsSinceEpoch}';
    });

    tearDown(() async {
      // Clean up test database
      final dir = Directory(testDbPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('Data should persist between database sessions', () async {
      // First session: Write data
      var db = await ReaxDB.open(testDbPath);
      
      await db.put('user:123', {
        'name': 'John Doe',
        'email': 'john@example.com',
        'age': 30,
      });

      await db.put('user:456', {
        'name': 'Jane Smith',
        'email': 'jane@example.com',
        'age': 25,
      });

      // Verify data exists in first session
      var user1 = await db.get('user:123');
      expect(user1, isNotNull);
      expect(user1!['name'], equals('John Doe'));

      var user2 = await db.get('user:456');
      expect(user2, isNotNull);
      expect(user2!['name'], equals('Jane Smith'));

      // Close database
      await db.close();

      // Second session: Read data without writing
      db = await ReaxDB.open(testDbPath);

      // Data should still exist
      user1 = await db.get('user:123');
      expect(user1, isNotNull);
      expect(user1!['name'], equals('John Doe'));
      expect(user1!['email'], equals('john@example.com'));
      expect(user1!['age'], equals(30));

      user2 = await db.get('user:456');
      expect(user2, isNotNull);
      expect(user2!['name'], equals('Jane Smith'));
      expect(user2!['email'], equals('jane@example.com'));
      expect(user2!['age'], equals(25));

      await db.close();
    });

    test('Data should persist after multiple write-read cycles', () async {
      var db = await ReaxDB.open(testDbPath);

      // Cycle 1: Write initial data
      await db.put('counter', {'value': 1});
      await db.close();

      // Cycle 2: Read and update
      db = await ReaxDB.open(testDbPath);
      var counter = await db.get('counter');
      expect(counter, isNotNull);
      expect(counter!['value'], equals(1));
      
      await db.put('counter', {'value': 2});
      await db.close();

      // Cycle 3: Verify update persisted
      db = await ReaxDB.open(testDbPath);
      counter = await db.get('counter');
      expect(counter, isNotNull);
      expect(counter!['value'], equals(2));
      await db.close();
    });

    test('Deleted data should not persist', () async {
      var db = await ReaxDB.open(testDbPath);

      // Write data
      await db.put('temp:data', {'value': 'temporary'});
      
      // Verify it exists
      var data = await db.get('temp:data');
      expect(data, isNotNull);

      // Delete it
      await db.delete('temp:data');
      
      // Verify it's gone in same session
      data = await db.get('temp:data');
      expect(data, isNull);

      await db.close();

      // Open new session and verify deletion persisted
      db = await ReaxDB.open(testDbPath);
      data = await db.get('temp:data');
      expect(data, isNull);
      await db.close();
    });
  });
}