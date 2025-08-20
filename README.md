# ReaxDB

[![pub package](https://img.shields.io/pub/v/reaxdb_dart.svg)](https://pub.dev/packages/reaxdb_dart)
[![GitHub stars](https://img.shields.io/github/stars/dvillegastech/ReaxBD.svg)](https://github.com/dvillegastech/ReaxBD/stargazers)
[![Dart](https://img.shields.io/badge/Dart-%E2%9D%A4-blue)](https://dart.dev)

**The simplest way to store data in Dart & Flutter.** Start with just 3 lines of code, scale to millions of records.

> 🆕 **Version 1.4.0**: Introducing Simple API - Zero configuration, 3 lines to start! [See changelog](CHANGELOG.md)

```dart
// That's it! You're ready to go
final db = await ReaxDB.simple('myapp');
await db.put('user', {'name': 'John', 'age': 30});
final user = await db.get('user');
```

## Why ReaxDB?

✅ **Dead Simple** - Start with 3 lines, no configuration needed  
✅ **Blazing Fast** - 21,000+ writes/second, instant cache reads  
✅ **Scale When Ready** - From simple key-value to advanced queries  
✅ **Pure Dart** - Works everywhere: iOS, Android, Web, Desktop, Server  
✅ **Production Ready** - ACID transactions, encryption, real-time sync  

## Installation

```yaml
dependencies:
  reaxdb_dart: ^1.4.0
```

## Quick Start

### 1. Basic Usage (90% of use cases)

```dart
import 'package:reaxdb_dart/reaxdb_dart.dart';

// Open database
final db = await ReaxDB.simple('myapp');

// Store any JSON data
await db.put('user:1', {
  'name': 'Alice',
  'email': 'alice@example.com',
  'age': 25
});

// Get data
final user = await db.get('user:1');
print(user['name']); // Alice

// Query with patterns
final users = await db.getAll('user:*');
users.forEach((key, value) {
  print('$key: ${value['name']}');
});

// Delete data
await db.delete('user:1');

// Close when done
await db.close();
```

### 2. Real-time Updates

```dart
// Listen to changes
db.watch('user:*').listen((event) {
  print('User ${event.key} changed');
});

// Make changes - listeners are notified automatically
await db.put('user:2', {'name': 'Bob'});
```

### 3. Batch Operations (faster for multiple items)

```dart
// Store multiple items at once
await db.putAll({
  'user:1': {'name': 'Alice'},
  'user:2': {'name': 'Bob'},
  'user:3': {'name': 'Charlie'},
});

// Delete multiple items
await db.deleteAll(['user:1', 'user:2']);
```

## When to Use ReaxDB

### Perfect for:
- 📱 **Mobile apps** needing offline-first storage
- 🚀 **Startups** wanting to move fast without database complexity
- 📊 **Apps with 100-1M records** that need speed
- 🔄 **Real-time features** like live updates, syncing
- 🛡️ **Secure apps** needing built-in encryption

### ReaxDB vs Others:

| Feature | ReaxDB | Hive | SQLite | Isar |
|---------|--------|------|--------|------|
| Setup complexity | ⭐ Simple | ⭐ Simple | ⭐⭐⭐ Complex | ⭐⭐ Medium |
| Performance | ⚡ 21k/sec | ⚡ Fast | 🐢 Slower | ⚡ Fast |
| Pure Dart | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| Real-time | ✅ Built-in | ❌ No | ❌ No | ✅ Yes |
| Encryption | ✅ Built-in | ✅ Yes | ⚠️ Extension | ✅ Yes |
| Advanced queries | ✅ Yes | ❌ Limited | ✅ SQL | ✅ Yes |
| Active development | ✅ Yes | ⚠️ Deprecated | ✅ Yes | ✅ Yes |

## Need More Power?

ReaxDB grows with your app. When you need advanced features, they're one line away:

```dart
// Need transactions? ✅
await db.advanced.transaction((txn) async {
  // Your atomic operations here
});

// Need indexes for complex queries? ✅
await db.advanced.createIndex('users', 'age');
final youngUsers = await db.advanced.collection('users')
    .whereBetween('age', 18, 25)
    .find();

// Need encryption? ✅
final secureDb = await ReaxDB.simple('myapp', encrypted: true);
```

📚 **[See Advanced Documentation](ADVANCED.md)** for transactions, indexes, aggregations, and more.

## Examples

### Todo App
```dart
// Store todos
await db.put('todo:1', {
  'title': 'Buy milk',
  'done': false,
  'created': DateTime.now().toIso8601String()
});

// Get all todos
final todos = await db.getAll('todo:*');

// Mark as done
final todo = await db.get('todo:1');
todo['done'] = true;
await db.put('todo:1', todo);
```

### User Settings
```dart
// Save settings
await db.put('settings', {
  'theme': 'dark',
  'notifications': true,
  'language': 'en'
});

// Read settings
final settings = await db.get('settings');
final isDark = settings['theme'] == 'dark';
```

### Shopping Cart
```dart
// Add to cart
await db.put('cart:product-123', {
  'name': 'Flutter Book',
  'price': 29.99,
  'quantity': 2
});

// Get cart total
final items = await db.getAll('cart:*');
double total = 0;
items.forEach((_, item) {
  total += item['price'] * item['quantity'];
});
```

## Performance

- **21,000+** writes per second
- **333,000+** reads per second from cache
- **Handles millions** of records efficiently
- **10x faster** than SQLite for key-value operations

## Resources

### Documentation
- 📖 [Advanced Documentation](ADVANCED.md) - Transactions, indexes, performance tuning
- 📊 [Performance Benchmarks](BENCHMARKS.md) - Detailed comparisons with other databases
- 🚀 [Migration Guide](MIGRATION.md) - Moving from Hive/Isar to ReaxDB

### Examples
- 💡 [Simple Example](examples/simple_example.dart) - Quick start guide
- ✅ [Todo App](examples/todo_app.dart) - Full-featured todo application
- 💬 [Chat App](examples/chat_app.dart) - Real-time chat with encryption
- 🎮 [Flutter Demo](example/lib/simple_demo.dart) - Interactive Flutter demo

## Support

- 🐛 [Report Issues](https://github.com/dvillegastech/ReaxBD/issues)
- ⭐ [Star on GitHub](https://github.com/dvillegastech/ReaxBD)
- ☕ [Support Development](https://buymeacoffee.com/dvillegas)

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Ready to build something amazing?** Start with `ReaxDB.simple()` and scale when you need to! 🚀