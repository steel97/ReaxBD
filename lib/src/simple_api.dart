import 'dart:async';
import 'reaxdb.dart';
import 'domain/entities/database_entity.dart';
import 'core/encryption/encryption_type.dart';

/// Simple, easy-to-use API for ReaxDB that covers 80% of use cases.
///
/// This is the recommended way to start using ReaxDB. For advanced features
/// like transactions, secondary indexes, or custom configurations, you can
/// access the full API through the [advanced] property.
///
/// Example:
/// ```dart
/// // Quick start - just one line!
/// final db = await ReaxDB.simple('myapp');
///
/// // Store data
/// await db.put('user:1', {'name': 'John', 'age': 30});
///
/// // Retrieve data
/// final user = await db.get('user:1');
///
/// // Query data
/// final users = await db.query('user:*');
///
/// // Delete data
/// await db.delete('user:1');
///
/// // Need advanced features? Access the full API
/// await db.advanced.transaction((txn) async {
///   // Complex transactional operations
/// });
/// ```
class SimpleReaxDB {
  final ReaxDB _db;
  final Set<String> _keys = {};

  SimpleReaxDB._(this._db);

  // Load existing keys from a special metadata entry
  Future<void> _loadExistingKeys() async {
    try {
      final metadata = await _db.get('__reaxdb_simple_keys__');
      if (metadata != null && metadata is List) {
        _keys.addAll(metadata.cast<String>());
      }
    } catch (_) {
      // If there's an error loading keys, start fresh
    }
  }

  // Save current keys to metadata
  Future<void> _saveKeys() async {
    await _db.put('__reaxdb_simple_keys__', _keys.toList());
  }

  /// Creates a simple database instance with optimized defaults.
  ///
  /// This method provides the easiest way to get started with ReaxDB.
  /// It uses sensible defaults that work well for most mobile applications.
  ///
  /// [name] - The name of your database (e.g., 'myapp')
  /// [encrypted] - Enable encryption with automatic key generation (default: false)
  /// [path] - Custom storage path (optional, uses app directory by default)
  static Future<SimpleReaxDB> open(
    String name, {
    bool encrypted = false,
    String? path,
  }) async {
    // Use optimized defaults for mobile apps
    final config = DatabaseConfig(
      memtableSizeMB: 4, // Reduced from 16 for mobile
      pageSize: 4096,
      l1CacheSize: 500, // Reduced cache sizes
      l2CacheSize: 1000,
      l3CacheSize: 2000,
      compressionEnabled: true,
      syncWrites: false, // Async for better performance
      maxImmutableMemtables: 4,
      cacheSize: 50,
      enableCache: true,
      encryptionType: encrypted ? EncryptionType.xor : EncryptionType.none,
    );

    final db = await ReaxDB.open(
      name,
      config: config,
      encryptionKey: encrypted ? _generateSimpleKey(name) : null,
      path: path,
    );

    final instance = SimpleReaxDB._(db);
    // Load existing keys from database
    await instance._loadExistingKeys();
    return instance;
  }

  /// Store a value with a key.
  ///
  /// The value can be any JSON-serializable object (Map, List, String, number, bool).
  ///
  /// Example:
  /// ```dart
  /// await db.put('user:123', {'name': 'Alice', 'age': 25});
  /// await db.put('settings', {'theme': 'dark', 'notifications': true});
  /// await db.put('counter', 42);
  /// ```
  Future<void> put(String key, dynamic value) async {
    await _db.put(key, value);
    _keys.add(key);
    await _saveKeys();
  }

  /// Retrieve a value by key.
  ///
  /// Returns null if the key doesn't exist.
  ///
  /// Example:
  /// ```dart
  /// final user = await db.get('user:123');
  /// if (user != null) {
  ///   print('User name: ${user['name']}');
  /// }
  /// ```
  Future<dynamic> get(String key) async {
    return await _db.get(key);
  }

  /// Delete a value by key.
  ///
  /// Example:
  /// ```dart
  /// await db.delete('user:123');
  /// ```
  Future<void> delete(String key) async {
    await _db.delete(key);
    _keys.remove(key);
    await _saveKeys();
  }

  /// Query keys matching a pattern.
  ///
  /// Supports wildcards:
  /// - `*` matches any sequence of characters
  /// - `?` matches a single character
  ///
  /// Example:
  /// ```dart
  /// // Get all users
  /// final userIds = await db.query('user:*');
  ///
  /// // Get all settings
  /// final settings = await db.query('settings:*');
  /// ```
  Future<List<String>> query(String pattern) async {
    final results = <String>[];
    // Filter keys by pattern
    for (final key in _keys) {
      if (_matchesPattern(key, pattern)) {
        results.add(key);
      }
    }
    return results;
  }

  // Helper method to match patterns
  bool _matchesPattern(String key, String pattern) {
    if (pattern == '*') return true;

    // Convert pattern to regex
    final regexPattern = pattern.replaceAll('*', '.*').replaceAll('?', '.');

    final regex = RegExp('^$regexPattern\$');
    return regex.hasMatch(key);
  }

  /// Get all values matching a key pattern.
  ///
  /// Returns a Map of key-value pairs.
  ///
  /// Example:
  /// ```dart
  /// // Get all user objects
  /// final users = await db.getAll('user:*');
  /// users.forEach((key, value) {
  ///   print('$key: ${value['name']}');
  /// });
  /// ```
  Future<Map<String, dynamic>> getAll(String pattern) async {
    final results = <String, dynamic>{};
    final keys = await query(pattern);
    for (final key in keys) {
      final value = await get(key);
      if (value != null) {
        results[key] = value;
      }
    }
    return results;
  }

  /// Store multiple values at once (batch operation).
  ///
  /// More efficient than multiple individual puts.
  ///
  /// Example:
  /// ```dart
  /// await db.putAll({
  ///   'user:1': {'name': 'Alice'},
  ///   'user:2': {'name': 'Bob'},
  ///   'user:3': {'name': 'Charlie'},
  /// });
  /// ```
  Future<void> putAll(Map<String, dynamic> entries) async {
    await _db.putBatch(entries);
    _keys.addAll(entries.keys);
    await _saveKeys();
  }

  /// Delete multiple keys at once.
  ///
  /// Example:
  /// ```dart
  /// await db.deleteAll(['user:1', 'user:2', 'user:3']);
  /// ```
  Future<void> deleteAll(List<String> keys) async {
    // Delete each key individually since deleteBatch doesn't exist
    for (final key in keys) {
      await _db.delete(key);
      _keys.remove(key);
    }
    await _saveKeys();
  }

  /// Clear all data in the database.
  ///
  /// ⚠️ This will delete ALL data. Use with caution!
  ///
  /// Example:
  /// ```dart
  /// await db.clear();
  /// ```
  Future<void> clear() async {
    // Clear all data by deleting all keys
    for (final key in _keys.toList()) {
      await _db.delete(key);
    }
    _keys.clear();
    await _saveKeys();
  }

  /// Listen to real-time changes in the database.
  ///
  /// Returns a stream that emits events whenever data changes.
  ///
  /// Example:
  /// ```dart
  /// db.watch('user:*').listen((event) {
  ///   print('User changed: ${event.key}');
  /// });
  /// ```
  Stream<DatabaseChangeEvent> watch([String? pattern]) {
    if (pattern != null) {
      return _db.stream(pattern);
    }
    return _db.changeStream;
  }

  /// Check if a key exists.
  ///
  /// Example:
  /// ```dart
  /// if (await db.exists('user:123')) {
  ///   print('User exists');
  /// }
  /// ```
  Future<bool> exists(String key) async {
    final value = await get(key);
    return value != null;
  }

  /// Count keys matching a pattern.
  ///
  /// Example:
  /// ```dart
  /// final userCount = await db.count('user:*');
  /// print('Total users: $userCount');
  /// ```
  Future<int> count([String pattern = '*']) async {
    final keys = await query(pattern);
    return keys.length;
  }

  /// Get database statistics.
  ///
  /// Returns basic information about the database.
  ///
  /// Example:
  /// ```dart
  /// final info = await db.info();
  /// print('Database size: ${info.sizeBytes} bytes');
  /// print('Total entries: ${info.entryCount}');
  /// ```
  Future<DatabaseInfo> info() async {
    return await _db.getDatabaseInfo();
  }

  /// Access the advanced API for complex operations.
  ///
  /// Use this when you need features like:
  /// - Transactions
  /// - Secondary indexes
  /// - Custom configurations
  /// - Performance tuning
  ///
  /// Example:
  /// ```dart
  /// // Use transactions
  /// await db.advanced.transaction((txn) async {
  ///   await txn.put('account:1', {'balance': 100});
  ///   await txn.put('account:2', {'balance': 200});
  /// });
  ///
  /// // Create indexes
  /// await db.advanced.createIndex('users', 'age');
  ///
  /// // Query with indexes
  /// final youngUsers = await db.advanced.collection('users')
  ///     .whereBetween('age', 18, 25)
  ///     .find();
  /// ```
  ReaxDB get advanced => _db;

  /// Close the database.
  ///
  /// Always close the database when you're done to ensure data is saved.
  ///
  /// Example:
  /// ```dart
  /// await db.close();
  /// ```
  Future<void> close() async {
    await _db.close();
  }

  // Helper method to generate a simple encryption key
  static String _generateSimpleKey(String name) {
    // Simple key generation based on database name
    // In production, you should use a secure key management solution
    final base = 'reaxdb_$name';
    final key = base.padRight(32, '0');
    return key.substring(0, 32);
  }
}
