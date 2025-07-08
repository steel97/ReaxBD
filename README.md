# ReaxDB

A high-performance NoSQL database for Flutter and Dart applications, combining LSM Tree and B+ Tree architectures with advanced caching, encryption, and ACID transaction support.

## Features

- **High Performance**: Zero-copy serialization and multi-level caching system
- **Security**: Built-in AES encryption with customizable keys
- **ACID Transactions**: Full transaction support with isolation levels
- **Concurrent Operations**: Connection pooling and batch processing
- **Mobile Optimized**: Hybrid storage engine designed for mobile devices
- **Real-time Streams**: Live data change notifications with pattern matching

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  reaxdb_dart: ^1.0.0
```

Then run:

```bash
flutter pub get
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
final txn = await db.beginTransaction();

try {
  await txn.put('account:1', {'balance': 1000});
  await txn.put('account:2', {'balance': 500});
  
  // Transfer money
  final account1 = await txn.get('account:1');
  final account2 = await txn.get('account:2');
  
  await txn.put('account:1', {'balance': account1['balance'] - 100});
  await txn.put('account:2', {'balance': account2['balance'] + 100});
  
  await txn.commit();
} catch (e) {
  await txn.rollback();
  rethrow;
}
```

### Real-time Data Streams

```dart
// Listen to all changes
final subscription = db.watchAll().listen((event) {
  print('${event.type}: ${event.key} = ${event.value}');
});

// Listen to specific patterns
final userStream = db.watchPattern('user:*').listen((event) {
  print('User updated: ${event.key}');
});

// Don't forget to cancel subscriptions
subscription.cancel();
userStream.cancel();
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
print('Database size: ${dbInfo['database']['size']} bytes');
print('Total entries: ${dbInfo['database']['entries']}');
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

- **Read Latency**: ~0.01ms (cache hit), ~0.1ms (disk read)
- **Write Throughput**: >10,000 operations/second
- **Concurrent Operations**: Up to 10 simultaneous operations
- **Memory Efficiency**: Multi-level caching with automatic promotion
- **Storage Efficiency**: LSM Tree with automatic compaction

## Security

ReaxDB provides built-in encryption support:

```dart
// Enable encryption with a custom key
final db = await ReaxDB.open(
  'secure_database',
  encryptionKey: 'your-256-bit-encryption-key',
);
```

All data is encrypted at rest using AES encryption when an encryption key is provided.

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

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.

## Support

For issues, questions, or contributions, please visit our GitHub repository or contact our support team.