import 'package:flutter/foundation.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';

/// Example demonstrating secondary indexes in ReaxDB
void main() async {
  // Open database
  final db = await ReaxDB.open('my_app_db');

  debugPrint('=== ReaxDB Secondary Index Example ===\n');
  
  // Create indexes on user collection
  debugPrint('Creating indexes...');
  await db.createIndex('users', 'email');
  await db.createIndex('users', 'age');
  await db.createIndex('users', 'city');
  debugPrint('Indexes created: ${db.listIndexes()}\n');
  
  // Insert some users
  debugPrint('Inserting users...');
  final users = [
    {'id': '1', 'name': 'John Doe', 'email': 'john@example.com', 'age': 25, 'city': 'New York'},
    {'id': '2', 'name': 'Jane Smith', 'email': 'jane@example.com', 'age': 30, 'city': 'Los Angeles'},
    {'id': '3', 'name': 'Bob Johnson', 'email': 'bob@example.com', 'age': 35, 'city': 'New York'},
    {'id': '4', 'name': 'Alice Brown', 'email': 'alice@example.com', 'age': 28, 'city': 'Chicago'},
    {'id': '5', 'name': 'Charlie Wilson', 'email': 'charlie@example.com', 'age': 22, 'city': 'New York'},
  ];
  
  for (final user in users) {
    await db.put('users:${user['id']}', user);
  }
  debugPrint('${users.length} users inserted\n');
  
  // Query examples
  debugPrint('=== Query Examples ===\n');
  
  // 1. Find by email (exact match)
  debugPrint('1. Find user by email:');
  final userByEmail = await db.collection('users')
      .whereEquals('email', 'jane@example.com')
      .findOne();
  debugPrint('   Result: ${userByEmail?['name']} (${userByEmail?['email']})\n');
  
  // 2. Find users in New York
  debugPrint('2. Find all users in New York:');
  final nyUsers = await db.where('users', 'city', 'New York');
  for (final user in nyUsers) {
    debugPrint('   - ${user['name']} (age: ${user['age']})');
  }
  debugPrint('');
  
  // 3. Find users by age range
  debugPrint('3. Find users between 25-30 years old:');
  final youngUsers = await db.collection('users')
      .whereBetween('age', 25, 30)
      .orderBy('age')
      .find();
  for (final user in youngUsers) {
    debugPrint('   - ${user['name']} (age: ${user['age']})');
  }
  debugPrint('');
  
  // 4. Complex query with multiple conditions
  debugPrint('4. Find young users in New York:');
  final youngNyUsers = await db.collection('users')
      .whereEquals('city', 'New York')
      .whereLessThan('age', 30)
      .find();
  for (final user in youngNyUsers) {
    debugPrint('   - ${user['name']} (age: ${user['age']}, city: ${user['city']})');
  }
  debugPrint('');
  
  // 5. Query with limit and offset
  debugPrint('5. Paginated query (limit 2, offset 1):');
  final page = await db.collection('users')
      .orderBy('name')
      .limit(2)
      .offset(1)
      .find();
  for (final user in page) {
    debugPrint('   - ${user['name']}');
  }
  debugPrint('');
  
  // Performance comparison
  debugPrint('=== Performance Comparison ===\n');
  
  // Without index (scan all documents)
  debugPrint('Dropping email index for comparison...');
  await db.dropIndex('users', 'email');
  
  final stopwatch1 = Stopwatch()..start();
  await db.collection('users')
      .whereEquals('email', 'bob@example.com')
      .findOne();
  stopwatch1.stop();
  debugPrint('Query without index: ${stopwatch1.elapsedMicroseconds}μs');
  
  // With index
  debugPrint('Recreating email index...');
  await db.createIndex('users', 'email');
  
  final stopwatch2 = Stopwatch()..start();
  await db.collection('users')
      .whereEquals('email', 'bob@example.com')
      .findOne();
  stopwatch2.stop();
  debugPrint('Query with index: ${stopwatch2.elapsedMicroseconds}μs');
  debugPrint('Speedup: ${(stopwatch1.elapsedMicroseconds / stopwatch2.elapsedMicroseconds).toStringAsFixed(1)}x faster\n');
  
  // Update a document (indexes are automatically updated)
  debugPrint('Updating user email...');
  final bobUser = await db.get<Map<String, dynamic>>('users:3');
  if (bobUser != null) {
    bobUser['email'] = 'robert@example.com';
    await db.put('users:3', bobUser);
    
    // Query with new email
    final updatedUser = await db.collection('users')
        .whereEquals('email', 'robert@example.com')
        .findOne();
    debugPrint('Updated user found: ${updatedUser?['name']} with new email: ${updatedUser?['email']}\n');
  }
  
  // Clean up
  await db.close();
  debugPrint('Database closed.');
}