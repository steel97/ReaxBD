# ReaxDB Advanced Documentation

This document contains advanced features and detailed configuration options for ReaxDB.

## Table of Contents
- [Configuration Options](#configuration-options)
- [Secondary Indexes](#secondary-indexes)
- [Transactions](#transactions)
- [Performance Tuning](#performance-tuning)
- [Encryption](#encryption)
- [Streaming and Real-time](#streaming-and-real-time)
- [Aggregations](#aggregations)
- [Architecture](#architecture)

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

## Secondary Indexes

Create indexes for fast queries on any field:

```dart
// Create indexes
await db.createIndex('users', 'email');
await db.createIndex('users', 'age');

// Query by indexed field
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
```

## Transactions

### Basic Transactions

```dart
await db.transaction((txn) async {
  await txn.put('account:1', {'balance': 1000});
  await txn.put('account:2', {'balance': 500});
  
  // Transfer money
  final account1 = await txn.get('account:1');
  final account2 = await txn.get('account:2');
  
  await txn.put('account:1', {'balance': account1['balance'] - 100});
  await txn.put('account:2', {'balance': account2['balance'] + 100});
});
```

### Advanced Transactions

```dart
// With retry logic
await db.withTransaction(
  (txn) async {
    await txn.put('key', 'value', (k, v) async {});
  },
  maxRetries: 3,
  retryDelay: Duration(milliseconds: 100),
  isolationLevel: IsolationLevel.serializable,
);

// Read-only transactions
final txn = await db.beginReadOnlyTransaction();
final value = await txn.get('key', (k) async => await db.get(k));
await txn.rollback();

// Transactions with savepoints
final txn = await db.beginEnhancedTransaction();
await txn.put('key1', 'value1', (k, v) async {});
await txn.savepoint('sp1');
await txn.put('key2', 'value2', (k, v) async {});
await txn.rollbackToSavepoint('sp1');
await txn.commit((changes) async {});
```

## Performance Tuning

### Write Performance Optimization

```dart
// Batch operations for better performance
await db.putBatch({
  'user:1': {'name': 'Alice', 'age': 25},
  'user:2': {'name': 'Bob', 'age': 30},
  'user:3': {'name': 'Charlie', 'age': 35},
});

// Async writes for better throughput
final config = DatabaseConfig(
  syncWrites: false,  // Async writes
  memtableSizeMB: 8,  // Larger memtable
);
```

### Cache Configuration

```dart
final config = DatabaseConfig(
  l1CacheSize: 2000,   // Hot data cache
  l2CacheSize: 10000,  // Warm data cache
  l3CacheSize: 50000,  // Cold data cache
);
```

## Encryption

ReaxDB provides multiple encryption options:

### Encryption Types

- **`EncryptionType.none`**: No encryption (fastest)
- **`EncryptionType.xor`**: XOR encryption (fast, moderate security)
- **`EncryptionType.aes256`**: AES-256-GCM encryption (secure, slower)

### Configuration

```dart
// AES-256 encryption (most secure)
final db = await ReaxDB.open(
  'secure_database',
  config: DatabaseConfig.withAes256Encryption(),
  encryptionKey: 'your-256-bit-encryption-key',
);

// XOR encryption (faster)
final db = await ReaxDB.open(
  'fast_secure_database',
  config: DatabaseConfig.withXorEncryption(),
  encryptionKey: 'your-encryption-key',
);
```

### WASM Compatibility

ReaxDB automatically detects WASM runtime and provides appropriate fallbacks:

```dart
// For WASM environments
final db = await ReaxDB.open(
  'wasm_database',
  encryptionType: EncryptionType.xor,  // Better WASM performance
  encryptionKey: 'your-encryption-key',
);
```

## Streaming and Real-time

### Basic Streams

```dart
// Listen to all changes
final subscription = db.changeStream.listen((event) {
  print('${event.type}: ${event.key} = ${event.value}');
});

// Listen to specific patterns
final userStream = db.stream('user:*').listen((event) {
  print('User updated: ${event.key}');
});
```

### Reactive Streams with Operators

```dart
// Debounce high-frequency updates
db.watch()
  .where((event) => event.key.startsWith('user:'))
  .debounce(Duration(milliseconds: 500))
  .map((event) => event.value)
  .listen((userData) {
    print('User data changed: $userData');
  });

// Throttle updates
db.watchKey('counter')
  .throttle(Duration(seconds: 1))
  .listen((event) {
    print('Counter updated (max once per second): ${event.value}');
  });

// Buffer events
db.watchCollection('logs')
  .buffer(10)  // Collect 10 events before emitting
  .listen((events) {
    print('Got ${events.length} log entries');
  });
```

## Aggregations

### Basic Aggregations

```dart
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
```

### Group By Operations

```dart
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
```

### Text Search

```dart
final searchResults = await db.collection('articles')
    .search('flutter dart', field: 'content')
    .limit(10)
    .find();
```

### Batch Updates and Deletes

```dart
// Batch updates
final updateCount = await db.collection('products')
    .whereEquals('category', 'electronics')
    .update({'onSale': true, 'discount': 0.2});

print('Updated $updateCount products');

// Batch deletes
final deleteCount = await db.collection('logs')
    .whereLessThan('timestamp', DateTime.now().subtract(Duration(days: 30)))
    .delete();

print('Deleted $deleteCount old logs');
```

## Architecture

ReaxDB uses a hybrid storage architecture combining:

- **LSM Tree**: Optimized for write-heavy workloads
- **B+ Tree**: Fast range queries and ordered access
- **Multi-level Cache**: L1 (object), L2 (page), L3 (query) caching
- **Write-Ahead Log**: Durability and crash recovery
- **Connection Pooling**: Concurrent operation management

### Storage Engine

The hybrid storage engine automatically selects the optimal storage strategy based on your workload:

- Small, frequently accessed data → In-memory cache
- Write-heavy operations → LSM Tree
- Range queries → B+ Tree
- Large datasets → Automatic compaction and compression

### Performance Characteristics

- **Read Performance**: 333,333 operations/second (~0.003ms latency)
- **Write Performance**: 21,276 operations/second (~0.047ms latency)
- **Batch Operations**: 3,676 operations/second
- **Cache Hits**: 555,555 operations/second (~0.002ms latency)
- **Large Files**: 4.8 GB/s write, 1.9 GB/s read
- **Concurrent Operations**: Up to 10 simultaneous operations

## Logging

Configure logging for debugging and monitoring:

```dart
import 'package:reaxdb_dart/reaxdb_dart.dart';

// Configure logging
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
```

## Performance Monitoring

```dart
// Get performance statistics
final stats = db.getPerformanceStats();
print('Cache hit ratio: ${stats['cache']['total_hit_ratio']}');

// Get database info
final dbInfo = await db.getDatabaseInfo();
print('Database name: ${dbInfo.name}');
print('Database size: ${dbInfo.sizeBytes} bytes');
print('Total entries: ${dbInfo.entryCount}');
print('Is encrypted: ${dbInfo.isEncrypted}');
```

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
7. **Use the Simple API** for basic operations, advanced API only when needed