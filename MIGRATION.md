# Migration Guide

## Migrating from Hive to ReaxDB

ReaxDB makes it easy to migrate from Hive. The APIs are similar, but ReaxDB offers more features when you need them.

### Quick Comparison

| Hive | ReaxDB Simple API |
|------|-------------------|
| `Hive.initFlutter()` | `ReaxDB.simple('myapp')` |
| `Hive.openBox('box')` | Already included in `simple()` |
| `box.put('key', value)` | `db.put('key', value)` |
| `box.get('key')` | `db.get('key')` |
| `box.delete('key')` | `db.delete('key')` |
| `box.clear()` | `db.clear()` |
| `box.values` | `db.getAll('*')` |
| `box.keys` | `db.query('*')` |
| `box.watch()` | `db.watch()` |

### Step-by-Step Migration

#### 1. Replace Hive Initialization

**Before (Hive):**
```dart
await Hive.initFlutter();
final box = await Hive.openBox('myBox');
```

**After (ReaxDB):**
```dart
final db = await ReaxDB.simple('myapp');
```

#### 2. Update CRUD Operations

**Before (Hive):**
```dart
// Create/Update
await box.put('user:1', {'name': 'Alice'});

// Read
final user = box.get('user:1');

// Delete
await box.delete('user:1');

// Check existence
final exists = box.containsKey('user:1');
```

**After (ReaxDB):**
```dart
// Create/Update
await db.put('user:1', {'name': 'Alice'});

// Read
final user = await db.get('user:1');

// Delete
await db.delete('user:1');

// Check existence
final exists = await db.exists('user:1');
```

#### 3. Batch Operations

**Before (Hive):**
```dart
await box.putAll({'key1': 'value1', 'key2': 'value2'});
await box.deleteAll(['key1', 'key2']);
```

**After (ReaxDB):**
```dart
await db.putAll({'key1': 'value1', 'key2': 'value2'});
await db.deleteAll(['key1', 'key2']);
```

#### 4. Watching Changes

**Before (Hive):**
```dart
box.watch(key: 'user:1').listen((event) {
  print('Value changed: ${event.value}');
});
```

**After (ReaxDB):**
```dart
db.watch('user:1').listen((event) {
  print('Value changed: ${event.value}');
});
```

#### 5. Getting All Values

**Before (Hive):**
```dart
final allValues = box.values.toList();
final allKeys = box.keys.toList();
```

**After (ReaxDB):**
```dart
final allItems = await db.getAll('*');
final allKeys = await db.query('*');
```

### Migration Script

Here's a simple script to migrate your Hive data to ReaxDB:

```dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';

Future<void> migrateFromHive() async {
  // Open Hive box
  await Hive.initFlutter();
  final hiveBox = await Hive.openBox('myBox');
  
  // Open ReaxDB
  final reaxDb = await ReaxDB.simple('myapp');
  
  // Migrate all data
  final entries = <String, dynamic>{};
  for (final key in hiveBox.keys) {
    entries[key.toString()] = hiveBox.get(key);
  }
  
  // Batch insert into ReaxDB
  await reaxDb.putAll(entries);
  
  print('Migrated ${entries.length} items from Hive to ReaxDB');
  
  // Close connections
  await hiveBox.close();
  await reaxDb.close();
}
```

## Migrating from Isar to ReaxDB

### Key Differences

| Isar | ReaxDB |
|------|--------|
| Schema required | No schema needed |
| Code generation | No code generation |
| `@collection` classes | Plain Dart Maps/Objects |
| Query builder | Simple patterns or advanced queries |
| Native library | Pure Dart |

### Migration Steps

#### 1. Remove Schema Classes

**Before (Isar):**
```dart
@collection
class User {
  Id id = Isar.autoIncrement;
  String? name;
  int? age;
}
```

**After (ReaxDB):**
```dart
// No schema needed! Just use plain objects
await db.put('user:1', {
  'id': 1,
  'name': 'Alice',
  'age': 25,
});
```

#### 2. Replace Queries

**Before (Isar):**
```dart
final users = await isar.users
    .where()
    .ageGreaterThan(18)
    .findAll();
```

**After (ReaxDB - Simple):**
```dart
// For simple cases, filter in memory
final allUsers = await db.getAll('user:*');
final adults = allUsers.values
    .where((user) => user['age'] > 18)
    .toList();
```

**After (ReaxDB - Advanced):**
```dart
// For complex queries with indexes
await db.advanced.createIndex('users', 'age');
final adults = await db.advanced.collection('users')
    .whereGreaterThan('age', 18)
    .find();
```

#### 3. Replace Watchers

**Before (Isar):**
```dart
Stream<List<User>> watchUsers() {
  return isar.users.watchLazy();
}
```

**After (ReaxDB):**
```dart
Stream<DatabaseChangeEvent> watchUsers() {
  return db.watch('user:*');
}
```

### Migration Script for Isar

```dart
import 'package:isar/isar.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';

Future<void> migrateFromIsar(Isar isar) async {
  // Open ReaxDB
  final reaxDb = await ReaxDB.simple('myapp');
  
  // Example: Migrate users collection
  final users = await isar.users.findAll();
  
  final entries = <String, dynamic>{};
  for (final user in users) {
    entries['user:${user.id}'] = {
      'id': user.id,
      'name': user.name,
      'age': user.age,
      // ... other fields
    };
  }
  
  // Batch insert
  await reaxDb.putAll(entries);
  
  print('Migrated ${users.length} users from Isar to ReaxDB');
  
  await reaxDb.close();
}
```

## Migrating from SQLite/sqflite to ReaxDB

### Key Differences

| SQLite | ReaxDB |
|--------|--------|
| SQL queries | Key-value with patterns |
| Tables & schemas | Collections (by key prefix) |
| JOIN operations | Denormalized data |
| Transactions | Built-in transactions |

### Migration Example

**Before (SQLite):**
```dart
// Create table
await db.execute('''
  CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    age INTEGER
  )
''');

// Insert
await db.insert('users', {'name': 'Alice', 'age': 25});

// Query
final users = await db.query('users', where: 'age > ?', whereArgs: [18]);
```

**After (ReaxDB):**
```dart
// No table creation needed!

// Insert
await db.put('user:1', {'name': 'Alice', 'age': 25});

// Query (simple approach)
final allUsers = await db.getAll('user:*');
final adults = allUsers.values.where((u) => u['age'] > 18).toList();
```

## Why Migrate to ReaxDB?

### Benefits over Hive
- ✅ **Active development** (Hive is deprecated)
- ✅ **Better performance** (21k writes/sec vs 16k)
- ✅ **Built-in real-time** features
- ✅ **Advanced queries** when you need them
- ✅ **Same simple API** for basic usage

### Benefits over Isar
- ✅ **No code generation** required
- ✅ **Pure Dart** (no native dependencies)
- ✅ **Simpler setup** (no schema definitions)
- ✅ **More flexible** data structures

### Benefits over SQLite
- ✅ **10x faster** for key-value operations
- ✅ **No SQL knowledge** required
- ✅ **Built-in caching** and optimization
- ✅ **Real-time updates** out of the box

## Need Help?

- Check our [examples](examples/) for real-world usage
- Read the [documentation](README.md) for API details
- Open an [issue](https://github.com/dvillegastech/ReaxBD/issues) for migration problems

Remember: You don't need to migrate everything at once. ReaxDB can run alongside your existing database during the transition!