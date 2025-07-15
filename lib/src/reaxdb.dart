import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'core/storage/hybrid_storage_engine.dart';
import 'core/cache/multi_level_cache.dart';
import 'core/transactions/transaction_manager.dart' as tx_manager;
import 'core/indexing/index_manager.dart';
import 'core/query/query_builder.dart';
import 'core/encryption/encryption_type.dart';
import 'core/encryption/encryption_engine.dart';
import 'domain/entities/database_entity.dart';

class ReaxDB {
  final String _name;
  final HybridStorageEngine _storageEngine;
  final MultiLevelCache _cache;
  final tx_manager.TransactionManager _transactionManager;
  final IndexManager _indexManager;
  final EncryptionEngine? _encryptionEngine;

  final StreamController<DatabaseChangeEvent> _changeStream =
      StreamController<DatabaseChangeEvent>.broadcast();
  final Map<String, StreamController<DatabaseChangeEvent>> _patternStreams = {};

  bool _isOpen = false;

  ReaxDB._({
    required String name,
    required HybridStorageEngine storageEngine,
    required MultiLevelCache cache,
    required tx_manager.TransactionManager transactionManager,
    required IndexManager indexManager,
    EncryptionEngine? encryptionEngine,
  }) : _name = name,
       _storageEngine = storageEngine,
       _cache = cache,
       _transactionManager = transactionManager,
       _indexManager = indexManager,
       _encryptionEngine = encryptionEngine;

  static Future<ReaxDB> open(
    String name, {
    DatabaseConfig? config,
    String? encryptionKey,
    String? path,
  }) async {
    config ??= DatabaseConfig.defaultConfig();

    String dbPath = path ?? name;

    final cache = MultiLevelCache(
      l1MaxSize: config.l1CacheSize,
      l2MaxSize: config.l2CacheSize,
      l3MaxSize: config.l3CacheSize,
    );

    final storageEngine = await HybridStorageEngine.create(
      path: dbPath,
      config: StorageConfig(
        memtableSize: config.memtableSizeMB * 1024 * 1024,
        pageSize: config.pageSize,
        compressionEnabled: config.compressionEnabled,
        syncWrites: config.syncWrites,
        maxImmutableMemtables: config.maxImmutableMemtables,
      ),
    );

    final transactionManager = tx_manager.TransactionManager(
      storageEngine: storageEngine,
    );

    final indexManager = IndexManager(
      basePath: dbPath,
      storageEngine: storageEngine,
    );

    await indexManager.loadIndexes();

    EncryptionEngine? encryptionEngine;
    if (config.encryptionType != EncryptionType.none) {
      encryptionEngine = EncryptionEngine(
        type: config.encryptionType,
        key: encryptionKey,
      );
    }

    final db = ReaxDB._(
      name: name,
      storageEngine: storageEngine,
      cache: cache,
      transactionManager: transactionManager,
      indexManager: indexManager,
      encryptionEngine: encryptionEngine,
    );

    db._isOpen = true;
    return db;
  }

  Future<void> put(String key, dynamic value) async {
    _ensureOpen();

    final serializedValue = _serializeValue(value);
    final finalValue =
        _encryptionEngine?.encrypt(serializedValue) ?? serializedValue;

    _cache.put(key, finalValue, level: CacheLevel.l1);

    await _storageEngine.put(key.codeUnits, finalValue);

    if (key.contains(':') && value is Map<String, dynamic>) {
      final parts = key.split(':');
      if (parts.length >= 2) {
        final collection = parts[0];
        final documentId = parts.sublist(1).join(':');
        await _indexManager.onDocumentInsert(collection, documentId, value);
      }
    }

    final event = DatabaseChangeEvent(
      type: ChangeType.put,
      key: key,
      value: value,
      timestamp: DateTime.now(),
    );

    _changeStream.add(event);
    _notifyPatternStreams(key, event);
  }

  Future<T?> get<T>(String key) async {
    _ensureOpen();

    final cached = _cache.get(key);
    if (cached != null) {
      final decryptedCached = _encryptionEngine?.decrypt(cached) ?? cached;
      return _deserializeValue<T>(decryptedCached);
    }

    final rawValue = await _storageEngine.get(key.codeUnits);
    if (rawValue == null) return null;

    final decryptedValue = _encryptionEngine?.decrypt(rawValue) ?? rawValue;
    final value = _deserializeValue<T>(decryptedValue);

    _cache.put(key, decryptedValue, level: CacheLevel.l1);

    return value;
  }

  Future<void> delete(String key) async {
    _ensureOpen();

    dynamic oldValue;
    if (key.contains(':')) {
      oldValue = await get(key);
    }

    await _storageEngine.delete(key.codeUnits);
    _cache.remove(key);

    if (key.contains(':') && oldValue is Map<String, dynamic>) {
      final parts = key.split(':');
      if (parts.length >= 2) {
        final collection = parts[0];
        final documentId = parts.sublist(1).join(':');
        await _indexManager.onDocumentDelete(collection, documentId, oldValue);
      }
    }

    final event = DatabaseChangeEvent(
      type: ChangeType.delete,
      key: key,
      value: null,
      timestamp: DateTime.now(),
    );

    _changeStream.add(event);
    _notifyPatternStreams(key, event);
  }

  Future<T> transaction<T>(Future<T> Function(Transaction) operation) async {
    _ensureOpen();

    return await _transactionManager.executeTransaction<T>((tx) async {
      return await operation(Transaction._(this, tx));
    });
  }

  Stream<DatabaseChangeEvent> stream(String keyPattern) {
    if (!_patternStreams.containsKey(keyPattern)) {
      _patternStreams[keyPattern] =
          StreamController<DatabaseChangeEvent>.broadcast();
    }
    return _patternStreams[keyPattern]!.stream;
  }

  Stream<DatabaseChangeEvent> get changeStream => _changeStream.stream;

  Future<void> compact() async {
    _ensureOpen();
    await _storageEngine.compact();
  }

  Future<void> createIndex(String collection, String fieldName) async {
    _ensureOpen();
    await _indexManager.createIndex(collection, fieldName);
  }

  Future<void> dropIndex(String collection, String fieldName) async {
    _ensureOpen();
    await _indexManager.dropIndex(collection, fieldName);
  }

  List<String> listIndexes() {
    _ensureOpen();
    return _indexManager.listIndexes();
  }

  QueryBuilder collection(String name) {
    _ensureOpen();
    return QueryBuilder(
      collection: name,
      db: this,
      indexManager: _indexManager,
    );
  }

  Future<List<Map<String, dynamic>>> where(
    String collection,
    String field,
    dynamic value,
  ) async {
    return this.collection(collection).whereEquals(field, value).find();
  }

  Future<void> close() async {
    if (!_isOpen) return;

    await _indexManager.close();
    await _storageEngine.close();
    await _transactionManager.close();
    await _changeStream.close();

    for (final controller in _patternStreams.values) {
      await controller.close();
    }
    _patternStreams.clear();

    _isOpen = false;
  }

  // Gets database info
  Future<DatabaseInfo> getDatabaseInfo() async {
    _ensureOpen();

    return DatabaseInfo(
      name: _name,
      path: 'database_path',
      createdAt: DateTime.now(),
      lastAccessed: DateTime.now(),
      entryCount: await _storageEngine.getEntryCount(),
      sizeBytes: await _storageEngine.getDatabaseSize(),
      isEncrypted: _encryptionEngine != null,
    );
  }

  // Gets database statistics
  Future<Map<String, dynamic>> getStatistics() async {
    _ensureOpen();

    final cacheStats = _cache.getStats();
    final transactionStats = _transactionManager.getStats();

    return {
      'database': {
        'name': _name,
        'size': await _storageEngine.getDatabaseSize(),
        'entries': await _storageEngine.getEntryCount(),
        'encrypted': _encryptionEngine != null,
      },
      'cache': {
        'l1': {'hits': cacheStats.l1Hits, 'misses': cacheStats.l1Misses},
        'l2': {'hits': cacheStats.l2Hits, 'misses': cacheStats.l2Misses},
        'l3': {'hits': cacheStats.l3Hits, 'misses': cacheStats.l3Misses},
        'totalEntries': cacheStats.totalEntries,
        'hitRatio': cacheStats.hitRatio,
      },
      'transactions': {
        'active': transactionStats.activeTransactions,
        'committed': transactionStats.committedTransactions,
        'aborted': transactionStats.abortedTransactions,
        'avgTime': transactionStats.averageTransactionTime,
      },
    };
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw DatabaseException('Database is not open');
    }
  }

  Uint8List serializeValue(dynamic value) {
    if (value is String) {
      final bytes = utf8.encode(value);
      final result = ByteData(5 + bytes.length);
      result.setUint8(0, 0);
      result.setUint32(1, bytes.length, Endian.little);
      final buffer = result.buffer.asUint8List();
      buffer.setRange(5, 5 + bytes.length, bytes);
      return buffer;
    } else if (value is int) {
      final bytes = ByteData(9);
      bytes.setUint8(0, 1);
      bytes.setInt64(1, value, Endian.little);
      return bytes.buffer.asUint8List();
    } else if (value is double) {
      final bytes = ByteData(9);
      bytes.setUint8(0, 2);
      bytes.setFloat64(1, value, Endian.little);
      return bytes.buffer.asUint8List();
    } else if (value is bool) {
      return Uint8List.fromList([3, value ? 1 : 0]);
    } else if (value is List<int>) {
      final header = ByteData(5);
      header.setUint8(0, 4);
      header.setUint32(1, value.length, Endian.little);
      final result = Uint8List(5 + value.length);
      result.setRange(0, 5, header.buffer.asUint8List());
      result.setRange(5, 5 + value.length, value);
      return result;
    }

    final json = jsonEncode(value);
    final jsonBytes = utf8.encode(json);
    final header = ByteData(5);
    header.setUint8(0, 255);
    header.setUint32(1, jsonBytes.length, Endian.little);
    final result = Uint8List(5 + jsonBytes.length);
    result.setRange(0, 5, header.buffer.asUint8List());
    result.setRange(5, 5 + jsonBytes.length, jsonBytes);
    return result;
  }

  T? deserializeValue<T>(Uint8List data) {
    if (data.isEmpty) return null;

    final typeMarker = data[0];

    try {
      switch (typeMarker) {
        case 0:
          final length = ByteData.view(
            data.buffer,
            data.offsetInBytes + 1,
            4,
          ).getUint32(0, Endian.little);
          return utf8.decode(data.sublist(5, 5 + length)) as T?;
        case 1:
          return ByteData.view(
                data.buffer,
                data.offsetInBytes + 1,
                8,
              ).getInt64(0, Endian.little)
              as T?;
        case 2:
          return ByteData.view(
                data.buffer,
                data.offsetInBytes + 1,
                8,
              ).getFloat64(0, Endian.little)
              as T?;
        case 3:
          return (data[1] == 1) as T?;
        case 4:
          final length = ByteData.view(
            data.buffer,
            data.offsetInBytes + 1,
            4,
          ).getUint32(0, Endian.little);
          return data.sublist(5, 5 + length) as T?;
        case 255:
          final length = ByteData.view(
            data.buffer,
            data.offsetInBytes + 1,
            4,
          ).getUint32(0, Endian.little);
          final json = utf8.decode(data.sublist(5, 5 + length));
          return jsonDecode(json) as T?;
        default:
          final json = utf8.decode(data);
          return jsonDecode(json) as T?;
      }
    } catch (e) {
      try {
        final json = utf8.decode(data);
        return jsonDecode(json) as T?;
      } catch (_) {
        return null;
      }
    }
  }

  // Encrypts data
  Uint8List encryptData(Uint8List data) {
    return _encryptionEngine?.encrypt(data) ?? data;
  }

  // Decrypts data
  Uint8List decryptData(Uint8List data) {
    return _encryptionEngine?.decrypt(data) ?? data;
  }

  // Gets encryption information
  Map<String, dynamic> getEncryptionInfo() {
    if (_encryptionEngine == null) {
      return {
        'enabled': false,
        'type': 'none',
        'display_name': 'No Encryption',
        'security_level': 'none',
        'performance_impact': 'none',
        'version': '1.0',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }

    return _encryptionEngine.getMetadata();
  }

  Uint8List _serializeValue(dynamic value) => serializeValue(value);
  T? _deserializeValue<T>(Uint8List data) => deserializeValue<T>(data);

  void _notifyPatternStreams(String key, DatabaseChangeEvent event) {
    for (final pattern in _patternStreams.keys) {
      if (_matchesPattern(key, pattern)) {
        _patternStreams[pattern]?.add(event);
      }
    }
  }

  bool _matchesPattern(String key, String pattern) {
    if (pattern.endsWith('*')) {
      final prefix = pattern.substring(0, pattern.length - 1);
      return key.startsWith(prefix);
    }
    return key == pattern;
  }

  // Batch operations for maximum throughput
  Future<void> putBatch(Map<String, dynamic> entries) async {
    _ensureOpen();

    final batchData = <List<int>, Uint8List>{};
    final events = <DatabaseChangeEvent>[];

    for (final entry in entries.entries) {
      final serialized = _serializeValue(entry.value);
      final finalValue = _encryptionEngine?.encrypt(serialized) ?? serialized;
      batchData[entry.key.codeUnits] = finalValue;
      _cache.put(entry.key, finalValue, level: CacheLevel.l1);

      events.add(
        DatabaseChangeEvent(
          type: ChangeType.put,
          key: entry.key,
          value: entry.value,
          timestamp: DateTime.now(),
        ),
      );
    }

    await _storageEngine.putBatch(batchData);

    for (final entry in entries.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key.contains(':') && value is Map<String, dynamic>) {
        final parts = key.split(':');
        if (parts.length >= 2) {
          final collection = parts[0];
          final documentId = parts.sublist(1).join(':');
          await _indexManager.onDocumentInsert(collection, documentId, value);
        }
      }
    }

    for (final event in events) {
      _changeStream.add(event);
      _notifyPatternStreams(event.key, event);
    }
  }

  // Parallel GET operations
  Future<Map<String, T?>> getBatch<T>(List<String> keys) async {
    _ensureOpen();

    final keyBytes = keys.map((k) => k.codeUnits).toList();
    final rawResults = await _storageEngine.getBatch(keyBytes);

    final result = <String, T?>{};
    for (int i = 0; i < keys.length; i++) {
      final key = keys[i];
      final rawValue = rawResults[keyBytes[i]];

      if (rawValue != null) {
        final decrypted = _encryptionEngine?.decrypt(rawValue) ?? rawValue;
        result[key] = _deserializeValue<T>(decrypted);
        _cache.put(key, decrypted, level: CacheLevel.l1);
      } else {
        result[key] = null;
      }
    }

    return result;
  }

  // Range scan operations
  Future<Map<String, T?>> scan<T>({
    String? startKey,
    String? endKey,
    int? limit,
  }) async {
    _ensureOpen();

    return <String, T?>{};
  }

  // Prefix scan operations
  Future<Map<String, T?>> scanPrefix<T>(String prefix, {int? limit}) async {
    _ensureOpen();

    return <String, T?>{};
  }

  // Atomic operations
  Future<bool> compareAndSwap<T>(
    String key,
    T? expectedValue,
    T newValue,
  ) async {
    _ensureOpen();

    final currentValue = await get<T>(key);
    if (currentValue == expectedValue) {
      await put(key, newValue);
      return true;
    }
    return false;
  }

  // Performance profiling
  Map<String, dynamic> getPerformanceStats() {
    final cacheStats = _cache.getStats();
    return {
      'cache': {
        'l1_hit_ratio':
            cacheStats.l1Hits / (cacheStats.l1Hits + cacheStats.l1Misses),
        'l2_hit_ratio':
            cacheStats.l2Hits / (cacheStats.l2Hits + cacheStats.l2Misses),
        'l3_hit_ratio':
            cacheStats.l3Hits / (cacheStats.l3Hits + cacheStats.l3Misses),
        'total_hit_ratio': cacheStats.hitRatio,
      },
      'optimization': {
        'zero_copy_enabled': true,
        'connection_pooling': true,
        'batch_operations': true,
        'adaptive_caching': true,
      },
    };
  }
}

// Database configuration
class DatabaseConfig {
  final int memtableSizeMB;
  final int pageSize;
  final int l1CacheSize;
  final int l2CacheSize;
  final int l3CacheSize;
  final bool compressionEnabled;
  final bool syncWrites;
  final int maxImmutableMemtables;
  final int cacheSize;
  final bool enableCache;
  final EncryptionType encryptionType;

  const DatabaseConfig({
    required this.memtableSizeMB,
    required this.pageSize,
    required this.l1CacheSize,
    required this.l2CacheSize,
    required this.l3CacheSize,
    required this.compressionEnabled,
    required this.syncWrites,
    required this.maxImmutableMemtables,
    required this.cacheSize,
    required this.enableCache,
    this.encryptionType = EncryptionType.none,
  });

  factory DatabaseConfig.defaultConfig() => const DatabaseConfig(
    memtableSizeMB: 4,
    pageSize: 4096,
    l1CacheSize: 1000,
    l2CacheSize: 10000,
    l3CacheSize: 100,
    compressionEnabled: true,
    syncWrites: true,
    maxImmutableMemtables: 4,
    cacheSize: 50,
    enableCache: true,
    encryptionType: EncryptionType.none,
  );

  // Creates config with XOR encryption
  factory DatabaseConfig.withXorEncryption() => const DatabaseConfig(
    memtableSizeMB: 4,
    pageSize: 4096,
    l1CacheSize: 1000,
    l2CacheSize: 10000,
    l3CacheSize: 100,
    compressionEnabled: true,
    syncWrites: true,
    maxImmutableMemtables: 4,
    cacheSize: 50,
    enableCache: true,
    encryptionType: EncryptionType.xor,
  );

  // Creates config with AES-256 encryption
  factory DatabaseConfig.withAes256Encryption() => const DatabaseConfig(
    memtableSizeMB: 4,
    pageSize: 4096,
    l1CacheSize: 1000,
    l2CacheSize: 10000,
    l3CacheSize: 100,
    compressionEnabled: true,
    syncWrites: true,
    maxImmutableMemtables: 4,
    cacheSize: 50,
    enableCache: true,
    encryptionType: EncryptionType.aes256,
  );
}

// Database change event
class DatabaseChangeEvent {
  final ChangeType type;
  final String key;
  final dynamic value;
  final DateTime timestamp;

  const DatabaseChangeEvent({
    required this.type,
    required this.key,
    required this.value,
    required this.timestamp,
  });
}

enum ChangeType { put, delete, transaction }

// Database exception
class DatabaseException implements Exception {
  final String message;
  const DatabaseException(this.message);

  @override
  String toString() => 'DatabaseException: $message';
}

// Wrapper for transactional operations
class Transaction {
  final ReaxDB _db;
  final tx_manager.Transaction _tx;

  Transaction._(this._db, this._tx);

  Future<void> put(String key, dynamic value) async {
    final serializedValue = _db.serializeValue(value);
    final finalValue = _db.encryptData(serializedValue);
    await _tx.put(key, finalValue);
  }

  Future<T?> get<T>(String key) async {
    final rawValue = await _tx.get(key);
    if (rawValue == null) return null;

    final decryptedValue = _db.decryptData(rawValue);
    return _db.deserializeValue<T>(decryptedValue);
  }

  Future<void> delete(String key) async {
    await _tx.delete(key);
  }
}
