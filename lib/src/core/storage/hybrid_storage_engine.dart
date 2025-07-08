import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:collection';

import '../../domain/entities/database_entity.dart';
import 'lsm_tree.dart';
import 'btree.dart';
import 'memtable.dart';
import '../wal/write_ahead_log.dart';

/// Hybrid storage engine combining LSM Tree and B+ Tree for mobile optimization
class HybridStorageEngine {
  final String _path;
  final StorageConfig _config;
  final MemTable _memtable;
  final List<MemTable> _immutableMemtables = [];
  final LsmTree _lsmTree;
  final BTree _btree;
  final WriteAheadLog _wal;
  
  // Connection pooling to fix StreamSink conflicts
  final Queue<Completer> _operationQueue = Queue();
  final int _maxConcurrentOps = 10;
  int _activeOperations = 0;
  
  // Batch processing for performance
  final Queue<_BatchOperation> _batchQueue = Queue();
  Timer? _batchTimer;
  final int _batchSize = 50;
  final Duration _batchInterval = Duration(milliseconds: 5);
  
  bool _isOpen = false;

  HybridStorageEngine._({
    required String path,
    required StorageConfig config,
    required MemTable memtable,
    required LsmTree lsmTree,
    required BTree btree,
    required WriteAheadLog wal,
  })  : _path = path,
        _config = config,
        _memtable = memtable,
        _lsmTree = lsmTree,
        _btree = btree,
        _wal = wal;

  /// Creates a new HybridStorageEngine
  static Future<HybridStorageEngine> create({
    required String path,
    required StorageConfig config,
  }) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final memtable = MemTable(maxSize: config.memtableSize);
    final lsmTree = await LsmTree.create(
      basePath: path,
    );
    final btree = await BTree.create(basePath: path);
    final wal = await WriteAheadLog.create(basePath: path);

    final engine = HybridStorageEngine._(
      path: path,
      config: config,
      memtable: memtable,
      lsmTree: lsmTree,
      btree: btree,
      wal: wal,
    );

    engine._isOpen = true;
    return engine;
  }

  /// Puts a key-value pair with connection pooling
  Future<void> put(List<int> key, Uint8List value) async {
    return _queueOperation(() => _putInternal(key, value));
  }
  
  /// Batch put operation for better performance
  Future<void> putBatch(Map<List<int>, Uint8List> entries) async {
    final futures = <Future>[];
    for (final entry in entries.entries) {
      futures.add(_addToBatch(_BatchOperation.put(entry.key, entry.value)));
    }
    await Future.wait(futures);
  }
  
  Future<void> _putInternal(List<int> key, Uint8List value) async {
    _ensureOpen();

    // Write to WAL first for durability
    await _wal.append(key, value);

    // Check if memtable is full
    if (_memtable.isFull) {
      await _rotateMemtable();
    }

    // Write to memtable
    _memtable.put(key, value);

    // Optionally write to B+ tree for fast reads
    if (_shouldUseBTree(key)) {
      await _btree.put(key, value);
    }
  }

  /// Gets a value by key with connection pooling
  Future<Uint8List?> get(List<int> key) async {
    return _queueOperation(() => _getInternal(key));
  }
  
  /// Batch get operation for better performance
  Future<Map<List<int>, Uint8List?>> getBatch(List<List<int>> keys) async {
    final result = <List<int>, Uint8List?>{};
    final futures = keys.map((key) => get(key).then((value) => result[key] = value));
    await Future.wait(futures);
    return result;
  }
  
  Future<Uint8List?> _getInternal(List<int> key) async {
    _ensureOpen();

    // Check memtable first (fastest)
    final memtableValue = _memtable.get(key);
    if (memtableValue != null) return memtableValue;

    // Check immutable memtables
    for (final immutableMemtable in _immutableMemtables.reversed) {
      final value = immutableMemtable.get(key);
      if (value != null) return value;
    }

    // Check B+ tree for frequently accessed data
    if (_shouldUseBTree(key)) {
      final btreeValue = await _btree.get(key);
      if (btreeValue != null) return btreeValue;
    }

    // Check LSM tree
    return await _lsmTree.get(key);
  }

  /// Deletes a key with connection pooling
  Future<void> delete(List<int> key) async {
    return _queueOperation(() => _deleteInternal(key));
  }
  
  Future<void> _deleteInternal(List<int> key) async {
    _ensureOpen();

    // Write tombstone to WAL
    await _wal.appendTombstone(key);

    // Add tombstone to memtable
    _memtable.delete(key);

    // Remove from B+ tree if present
    await _btree.delete(key);
  }

  /// Compacts the database
  Future<void> compact() async {
    _ensureOpen();

    // Flush all immutable memtables
    for (final memtable in _immutableMemtables) {
      await _lsmTree.flush(memtable);
    }
    _immutableMemtables.clear();

    // Compact LSM tree
    await _lsmTree.compact();

    // Checkpoint WAL
    await _wal.checkpoint();
  }

  /// Gets database size in bytes
  Future<int> getDatabaseSize() async {
    _ensureOpen();
    
    int totalSize = 0;
    final directory = Directory(_path);
    
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    
    return totalSize;
  }

  /// Gets entry count
  Future<int> getEntryCount() async {
    _ensureOpen();
    
    int count = _memtable.size;
    for (final memtable in _immutableMemtables) {
      count += memtable.size;
    }
    count += await _lsmTree.getEntryCount();
    
    return count;
  }

  /// Closes the storage engine
  Future<void> close() async {
    if (!_isOpen) return;

    // Stop batch processing
    _batchTimer?.cancel();
    if (_batchQueue.isNotEmpty) {
      await _processBatch();
    }

    // Wait for all operations to complete
    while (_activeOperations > 0) {
      await Future.delayed(Duration(milliseconds: 10));
    }

    // Flush current memtable
    if (!_memtable.isEmpty) {
      await _lsmTree.flush(_memtable);
    }

    // Flush all immutable memtables
    for (final memtable in _immutableMemtables) {
      await _lsmTree.flush(memtable);
    }

    await _wal.close();
    await _lsmTree.close();
    await _btree.close();

    _isOpen = false;
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw StateError('Storage engine is not open');
    }
  }

  Future<void> _rotateMemtable() async {
    // Move current memtable to immutable list
    final currentMemtable = MemTable.from(_memtable);
    _immutableMemtables.add(currentMemtable);

    // Clear current memtable
    _memtable.clear();

    // Flush oldest immutable memtable if we have too many
    if (_immutableMemtables.length > _config.maxImmutableMemtables) {
      final oldestMemtable = _immutableMemtables.removeAt(0);
      await _lsmTree.flush(oldestMemtable);
    }
  }

  /// Connection pooling to prevent StreamSink conflicts
  Future<T> _queueOperation<T>(Future<T> Function() operation) async {
    final completer = Completer<T>();
    
    if (_activeOperations < _maxConcurrentOps) {
      _activeOperations++;
      try {
        final result = await operation();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      } finally {
        _activeOperations--;
        _processQueue();
      }
    } else {
      _operationQueue.add(Completer()..future.then((_) async {
        _activeOperations++;
        try {
          final result = await operation();
          completer.complete(result);
        } catch (e) {
          completer.completeError(e);
        } finally {
          _activeOperations--;
          _processQueue();
        }
      }));
    }
    
    return completer.future;
  }
  
  void _processQueue() {
    while (_operationQueue.isNotEmpty && _activeOperations < _maxConcurrentOps) {
      final next = _operationQueue.removeFirst();
      next.complete();
    }
  }
  
  /// Batch processing for improved throughput
  Future<void> _addToBatch(_BatchOperation operation) async {
    final completer = Completer<void>();
    operation.completer = completer;
    _batchQueue.add(operation);
    
    _batchTimer ??= Timer.periodic(_batchInterval, (_) => _processBatch());
    
    if (_batchQueue.length >= _batchSize) {
      await _processBatch();
    }
    
    return completer.future;
  }
  
  Future<void> _processBatch() async {
    if (_batchQueue.isEmpty) return;
    
    final batch = List<_BatchOperation>.from(_batchQueue);
    _batchQueue.clear();
    
    try {
      for (final op in batch) {
        try {
          switch (op.type) {
            case _BatchOpType.put:
              await _putInternal(op.key!, op.value!);
              break;
            case _BatchOpType.delete:
              await _deleteInternal(op.key!);
              break;
          }
          op.completer?.complete();
        } catch (e) {
          op.completer?.completeError(e);
        }
      }
    } catch (e) {
      for (final op in batch) {
        op.completer?.completeError(e);
      }
    }
  }
  
  bool _shouldUseBTree(List<int> key) {
    // Use B+ tree for frequently accessed keys or range queries
    // This is a simple heuristic - could be more sophisticated
    final keyString = String.fromCharCodes(key);
    return keyString.contains(':') || keyString.length < 20;
  }
}

/// Batch operation types
enum _BatchOpType { put, delete }

/// Batch operation container
class _BatchOperation {
  final _BatchOpType type;
  final List<int>? key;
  final Uint8List? value;
  Completer<void>? completer;
  
  _BatchOperation.put(this.key, this.value) : type = _BatchOpType.put;
  _BatchOperation.delete(this.key) : type = _BatchOpType.delete, value = null;
}