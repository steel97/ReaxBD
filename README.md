# ReaxDB

[![pub package](https://img.shields.io/pub/v/reaxdb_dart.svg)](https://pub.dev/packages/reaxdb_dart)
[![GitHub stars](https://img.shields.io/github/stars/dvillegastech/ReaxBD.svg)](https://github.com/dvillegastech/ReaxBD/stargazers)
[![GitHub license](https://img.shields.io/github/license/dvillegastech/ReaxBD.svg)](https://github.com/dvillegastech/ReaxBD/blob/main/LICENSE)
[![Dart](https://img.shields.io/badge/Dart-%E2%9D%A4-blue)](https://dart.dev)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-blue)](https://dart.dev)

The fastest NoSQL database for pure Dart. Store millions of records with 21,000+ writes per second, instant reads from cache, and built-in encryption. Perfect for offline-first apps, real-time sync, and large datasets. Works on all platforms with zero native dependencies - now as a pure Dart package!

**Keywords:** Dart database, NoSQL, offline-first, local storage, cache, encryption, ACID transactions, real-time sync, embedded database, key-value store, document database, high performance, zero dependencies, pure Dart, reactive streams, aggregations

## 🆕 What's New in v1.3.0 (August 11, 2025)
- **Pure Dart Package** - Converted from Flutter-specific to pure Dart package (PR #4)
- **Configurable Logging** - Multi-level logging with file/console/memory outputs
- **Reactive Streams** - Advanced stream operators (debounce, throttle, buffer, map)
- **Enhanced Query Builder** - Aggregations, group by, text search, batch updates
- **Advanced Transactions** - Isolation levels, savepoints, nested transactions, retry logic
- **Performance** - Optimized query scanning and caching strategies
- **Special Thanks** - [@TechWithDunamis](https://github.com/TechWithDunamis) for the pure Dart conversion (PR #4)

### Previous v1.2.3 (July 20, 2025)
- **CRITICAL FIX** - Fixed data persistence between application sessions
- **WAL Recovery** - Data now properly restores when reopening database
- **Stability** - Fixed async operations and operation ordering
- **Thanks** - Special thanks to Ray Caruso for reporting the persistence bug

### Previous v1.2.2 (July 15, 2025)
- **Bug Fixes** - Fixed pub.dev issues
- **Documentation** - Added API docs
- **Code Quality** - Better error handling

### Previous v1.2.0 (July 11, 2025)
- **WASM Compatibility** - Full support for Dart's WASM runtime
- **Enhanced Encryption API** - New `EncryptionType` enum for better control
- **AES-256 Performance** - 40% faster AES encryption (138-180ms vs 237ms)
- **WAL Recovery Fix** - Improved Write-Ahead Log reliability
- **Automatic Fallbacks** - Smart encryption fallbacks for WASM environments

### Previous v1.1.1
- **Secondary Indexes** - Query any field with lightning speed
- **Query Builder** - Powerful API for complex queries
- **Range Queries** - Find documents between values
- **Auto Index Updates** - Indexes stay in sync automatically

### Previous v1.0.1
- **4.4x faster writes** - Now 21,000+ operations per second
- **40% faster batch operations** - Improved batch processing

## Features

- **Pure Dart**: Works in any Dart environment - no Flutter dependency required
- **High Performance**: Zero-copy serialization and multi-level caching system
- **Security**: Built-in AES encryption with customizable keys
- **ACID Transactions**: Full transaction support with isolation levels
- **Advanced Transactions**: Savepoints, nested transactions, automatic retry
- **Concurrent Operations**: Connection pooling and batch processing
- **Mobile Optimized**: Hybrid storage engine designed for mobile devices
- **Real-time Streams**: Live data change notifications with pattern matching
- **Reactive Programming**: Stream operators like debounce, throttle, buffer
- **Query Aggregations**: COUNT, SUM, AVG, MIN, MAX, DISTINCT, GROUP BY
- **Text Search**: Full-text search across documents
- **Configurable Logging**: Multi-level logging with various outputs
- **Data Persistence**: Reliable WAL-based persistence across app sessions

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  reaxdb_dart: ^1.3.0
```

Then run:

```bash
flutter pub get
```

or

```bash
dart pub get
```

## Quick Start

### Opening a Database

```dart
import 'package:reaxdb_dart/reaxdb_dart.dart';

// Basic usage
final db = await ReaxDB.open('my_database');

// With custom configuration
final config = DatabaseConfig(
  memtableSizeMB: 16,
  pageSize: 8192,
  l1CacheSize: 2000,
  l2CacheSize: 10000,
  l3CacheSize: 50000,
  compressionEnabled: true,
  syncWrites: false,
  encryptionType: EncryptionType.aes256, // New encryption API
);

final db = await ReaxDB.open(
  'my_database',
  config: config,
  encryptionKey: 'your-encryption-key',
);
```

### Basic Operations

```dart
// Store data
await db.put('user:123', {
  'name': 'John Doe',
  'email': 'john@example.com',
  'age': 30,
});

// Retrieve data
final user = await db.get('user:123');
print(user); // {name: John Doe, email: john@example.com, age: 30}

// Delete data
await db.delete('user:123');

// Close database
await db.close();

// Data persists between sessions (v1.2.3+)
final db2 = await ReaxDB.open('my_database');
final persistedUser = await db2.get('user:123');
// persistedUser is null because it was deleted
```

### Secondary Indexes & Advanced Queries

```dart
// Create indexes for fast queries
await db.createIndex('users', 'email');
await db.createIndex('users', 'age');

// Query by any indexed field
final user = await db.collection('users')
    .whereEquals('email', 'john@example.com')
    .findOne();

// Range queries
final youngUsers = await db.collection('users')
    .whereBetween('age', 18, 30)
    .orderBy('age')
    .find();

// Complex queries
final results = await db.collection('users')
    .whereEquals('city', 'New York')
    .whereGreaterThan('age', 21)
    .limit(10)
    .find();

// Aggregations (NEW!)
final stats = await db.collection('users')
    .aggregate((agg) => agg
        .count()
        .avg('age')
        .min('age')
        .max('age')
        .sum('purchases')
        .distinct('city'))
    .executeAggregation();

print('Total users: ${stats['count'].value}');
print('Average age: ${stats['avg_age'].value}');
print('Unique cities: ${stats['distinct_city'].value}');

// Group By operations (NEW!)
final salesByRegion = await db.collection('sales')
    .aggregate((agg) => agg
        .groupBy('region')
        .sum('amount')
        .count()
        .avg('amount'))
    .executeAggregation();

for (final group in salesByRegion) {
  print('Region: ${group.groupKey}');
  print('Total sales: ${group.aggregations['sum_amount'].value}');
  print('Number of sales: ${group.aggregations['count'].value}');
}

// Text search (NEW!)
final searchResults = await db.collection('articles')
    .search('flutter dart', field: 'content')
    .limit(10)
    .find();

// Batch updates (NEW!)
final updateCount = await db.collection('products')
    .whereEquals('category', 'electronics')
    .update({'onSale': true, 'discount': 0.2});

print('Updated $updateCount products');

// Batch deletes (NEW!)
final deleteCount = await db.collection('logs')
    .whereLessThan('timestamp', DateTime.now().subtract(Duration(days: 30)))
    .delete();

print('Deleted $deleteCount old logs');
```

### Batch Operations

```dart
// Batch write for better performance
await db.putBatch({
  'user:1': {'name': 'Alice', 'age': 25},
  'user:2': {'name': 'Bob', 'age': 30},
  'user:3': {'name': 'Charlie', 'age': 35},
});

// Batch read
final users = await db.getBatch(['user:1', 'user:2', 'user:3']);
```

### Transactions

```dart
// Basic transactions
await db.transaction((txn) async {
  await txn.put('account:1', {'balance': 1000});
  await txn.put('account:2', {'balance': 500});
  
  // Transfer money
  final account1 = await txn.get('account:1');
  final account2 = await txn.get('account:2');
  
  await txn.put('account:1', {'balance': account1['balance'] - 100});
  await txn.put('account:2', {'balance': account2['balance'] + 100});
});

// Advanced transactions with retry logic (NEW!)
await db.withTransaction(
  (txn) async {
    // Your transactional operations
    await txn.put('key', 'value', (k, v) async {});
  },
  maxRetries: 3,
  retryDelay: Duration(milliseconds: 100),
  isolationLevel: IsolationLevel.serializable,
);

// Read-only transactions (NEW!)
final txn = await db.beginReadOnlyTransaction();
final value = await txn.get('key', (k) async => await db.get(k));
await txn.rollback();

// Transactions with savepoints (NEW!)
final txn = await db.beginEnhancedTransaction();
await txn.put('key1', 'value1', (k, v) async {});
await txn.savepoint('sp1');
await txn.put('key2', 'value2', (k, v) async {});
// Rollback to savepoint if needed
await txn.rollbackToSavepoint('sp1');
await txn.commit((changes) async {});
```

### Real-time Data Streams

```dart
// Listen to all changes
final subscription = db.changeStream.listen((event) {
  print('${event.type}: ${event.key} = ${event.value}');
});

// Listen to specific patterns
final userStream = db.stream('user:*').listen((event) {
  print('User updated: ${event.key}');
});

// Reactive streams with operators (NEW!)
db.watch()
  .where((event) => event.key.startsWith('user:'))
  .debounce(Duration(milliseconds: 500))
  .map((event) => event.value)
  .listen((userData) {
    print('User data changed: $userData');
  });

// Throttle high-frequency updates (NEW!)
db.watchKey('counter')
  .throttle(Duration(seconds: 1))
  .listen((event) {
    print('Counter updated (max once per second): ${event.value}');
  });

// Buffer events (NEW!)
db.watchCollection('logs')
  .buffer(10) // Collect 10 events before emitting
  .listen((events) {
    print('Got ${events.length} log entries');
  });

// Don't forget to cancel subscriptions
subscription.cancel();
userStream.cancel();
```

### Configurable Logging (NEW!)

```dart
import 'package:reaxdb_dart/reaxdb_dart.dart';

// Configure logging level
ReaxLogger.instance.configure(
  level: LogLevel.debug,
  outputs: [
    ConsoleLogOutput(),
    FileLogOutput('/path/to/logs/app.log'),
    MemoryLogOutput(maxLines: 1000),
  ],
);

// Use the logger
final logger = ReaxLogger.instance;
logger.info('Database opened successfully');
logger.debug('Query executed', metadata: {'query': 'SELECT * FROM users'});
logger.warning('Cache miss for key: user:123');
logger.error('Transaction failed', error: exception);

// Disable logging for production
ReaxLogger.instance.configure(level: LogLevel.none);

// Get memory logs
final memoryOutput = ReaxLogger.instance.outputs
    .whereType<MemoryLogOutput>()
    .first;
final logs = memoryOutput.getLogs();
```

### Advanced Features

#### Atomic Operations

```dart
// Compare and swap
final success = await db.compareAndSwap('counter', 0, 1);
if (success) {
  print('Counter incremented');
}
```

#### Performance Monitoring

```dart
final stats = db.getPerformanceStats();
print('Cache hit ratio: ${stats['cache']['total_hit_ratio']}');

final dbInfo = await db.getDatabaseInfo();
print('Database name: ${dbInfo.name}');
print('Database size: ${dbInfo.sizeBytes} bytes');
print('Total entries: ${dbInfo.entryCount}');
print('Is encrypted: ${dbInfo.isEncrypted}');
```

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `memtableSizeMB` | 4 | Memory table size in megabytes |
| `pageSize` | 4096 | Storage page size in bytes |
| `l1CacheSize` | 1000 | Level 1 cache maximum entries |
| `l2CacheSize` | 5000 | Level 2 cache maximum entries |
| `l3CacheSize` | 10000 | Level 3 cache maximum entries |
| `compressionEnabled` | true | Enable data compression |
| `syncWrites` | true | Synchronous write operations |
| `maxImmutableMemtables` | 4 | Maximum immutable memtables |

## Performance Characteristics

- **Read Performance**: 333,333 operations/second (~0.003ms latency)
- **Write Performance**: 21,276 operations/second (~0.047ms latency)
- **Batch Operations**: 3,676 operations/second
- **Cache Hits**: 555,555 operations/second (~0.002ms latency)
- **Large Files**: 4.8 GB/s write, 1.9 GB/s read
- **Concurrent Operations**: Up to 10 simultaneous operations
- **Memory Efficiency**: Multi-level caching with automatic promotion
- **Storage Efficiency**: LSM Tree with automatic compaction

## Security

ReaxDB provides built-in encryption support with multiple algorithms:

```dart
// AES-256 encryption (most secure)
final db = await ReaxDB.open(
  'secure_database',
  config: DatabaseConfig.withAes256Encryption(),
  encryptionKey: 'your-256-bit-encryption-key',
);

// XOR encryption (faster, good for performance-critical apps)
final db = await ReaxDB.open(
  'fast_secure_database',
  config: DatabaseConfig.withXorEncryption(),
  encryptionKey: 'your-encryption-key',
);

// Custom encryption configuration
final config = DatabaseConfig(
  memtableSizeMB: 8,
  pageSize: 4096,
  l1CacheSize: 1000,
  l2CacheSize: 5000,
  l3CacheSize: 10000,
  compressionEnabled: true,
  syncWrites: true,
  maxImmutableMemtables: 4,
  cacheSize: 50,
  enableCache: true,
  encryptionType: EncryptionType.aes256, // none, xor, or aes256
);

final db = await ReaxDB.open(
  'custom_secure_database',
  config: config,
  encryptionKey: 'your-encryption-key',
);
```

### Encryption Types

- **`EncryptionType.none`**: No encryption (fastest)
- **`EncryptionType.xor`**: XOR encryption (fast, moderate security)
- **`EncryptionType.aes256`**: AES-256-GCM encryption (secure, slower)

All data is encrypted at rest when an encryption type other than `none` is specified.

### WASM Compatibility

ReaxDB is compatible with Dart's WASM runtime, but with some limitations:

- **Native Performance**: Uses PointyCastle for optimized AES-256 encryption (~138-180ms)
- **WASM Fallback**: Automatically switches to HMAC-based encryption in WASM environments
- **Security Note**: WASM fallback provides authentication but reduced cryptographic strength
- **Recommendation**: Use XOR encryption for WASM deployments requiring high performance

```dart
// For WASM environments, consider using XOR encryption
final db = await ReaxDB.open(
  'wasm_database',
  encryptionType: EncryptionType.xor, // Better WASM performance
  encryptionKey: 'your-encryption-key',
);
```

The library automatically detects WASM runtime and provides appropriate warnings when using AES-256 encryption.

## Architecture

ReaxDB uses a hybrid storage architecture combining:

- **LSM Tree**: Optimized for write-heavy workloads
- **B+ Tree**: Fast range queries and ordered access
- **Multi-level Cache**: L1 (object), L2 (page), L3 (query) caching
- **Write-Ahead Log**: Durability and crash recovery
- **Connection Pooling**: Concurrent operation management

## Error Handling

```dart
try {
  final value = await db.get('nonexistent-key');
} on DatabaseException catch (e) {
  print('Database error: ${e.message}');
} catch (e) {
  print('Unexpected error: $e');
}
```

## Best Practices

1. **Use batch operations** for multiple writes to improve performance
2. **Enable compression** for storage efficiency with large datasets  
3. **Configure cache sizes** based on your application's memory constraints
4. **Use transactions** for operations that must be atomic
5. **Close databases** properly to ensure data persistence
6. **Monitor performance** using built-in statistics methods

## Closing the Database

```dart
await db.close();
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributors

Special thanks to all contributors who have helped make ReaxDB better:

- **[@TechWithDunamis](https://github.com/TechWithDunamis)** - Pure Dart conversion (PR #4) - Converted ReaxDB from Flutter-specific to pure Dart package, enabling use in all Dart environments
- **Ray Caruso** - Bug report for persistence issue (v1.2.3)

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.

## Support the Project

If you find ReaxDB useful, please consider supporting its development:

<a href="https://buymeacoffee.com/dvillegas" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

Your support helps maintain and improve ReaxDB!

## Support

For issues, questions, or contributions, please visit our [GitHub repository](https://github.com/dvillegastech/ReaxBD) or contact our support team.