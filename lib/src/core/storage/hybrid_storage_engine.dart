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

  // Batch timer for cleanup
  Timer? _batchTimer;

  // Write buffer for improved throughput
  final List<_WriteBufferEntry> _writeBuffer = [];
  Timer? _flushTimer;
  final int _writeBufferSize = 256;
  bool _isFlushingBuffer = false;

  bool _isOpen = false;

  HybridStorageEngine._({
    required String path,
    required StorageConfig config,
    required MemTable memtable,
    required LsmTree lsmTree,
    required BTree btree,
    required WriteAheadLog wal,
  }) : _path = path,
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
    final lsmTree = await LsmTree.create(basePath: path);
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

  /// Puts a key-value pair with optimized async processing
  Future<void> put(List<int> key, Uint8List value) async {
    _ensureOpen();

    // Fast path: write directly to memtable if not full
    if (!_memtable.isFull) {
      // Add to write buffer for async WAL write
      final entry = _WriteBufferEntry(key: key, value: value);
      _writeBuffer.add(entry);

      // Write to memtable immediately
      _memtable.put(key, value);

      // Optionally write to B+ tree
      if (_shouldUseBTree(key)) {
        _btree.put(key, value);
      }

      // Start async WAL write if needed
      _flushTimer ??= Timer(
        Duration(microseconds: 100),
        () => _flushWriteBuffer(),
      );

      // Flush if buffer is getting large
      if (_writeBuffer.length >= _writeBufferSize) {
        _flushWriteBuffer(); // Don't await - async
      }

      return; // Return immediately
    }

    // Slow path: need to rotate memtable
    await _rotateMemtable();
    await put(key, value); // Retry
  }

  /// Batch put operation with optimized WAL writes
  Future<void> putBatch(Map<List<int>, Uint8List> entries) async {
    _ensureOpen();

    // Group WAL writes for better performance
    final walWrites = <Future>[];
    for (final entry in entries.entries) {
      walWrites.add(_wal.append(entry.key, entry.value));
    }

    // Write to WAL in parallel
    await Future.wait(walWrites, eagerError: false);

    // Check if memtable needs rotation
    var totalSize = 0;
    for (final value in entries.values) {
      totalSize += value.length;
    }

    if (_memtable.currentSize + totalSize > _memtable.maxSize) {
      await _rotateMemtable();
    }

    // Write all entries to memtable at once
    for (final entry in entries.entries) {
      _memtable.put(entry.key, entry.value);

      // Optionally write to B+ tree
      if (_shouldUseBTree(entry.key)) {
        _btree.put(entry.key, entry.value);
      }
    }
  }

  /// Gets a value by key with connection pooling
  Future<Uint8List?> get(List<int> key) async {
    return _queueOperation(() => _getInternal(key));
  }

  /// Batch get operation for better performance
  Future<Map<List<int>, Uint8List?>> getBatch(List<List<int>> keys) async {
    final result = <List<int>, Uint8List?>{};
    final futures = keys.map(
      (key) => get(key).then((value) => result[key] = value),
    );
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

    // Flush any pending writes first
    if (_writeBuffer.isNotEmpty) {
      await _flushWriteBuffer();
      // Wait a bit for async operations to complete
      await Future.delayed(Duration(milliseconds: 10));
    }

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

    // Stop timers
    _batchTimer?.cancel();
    _flushTimer?.cancel();

    // Flush write buffer
    if (_writeBuffer.isNotEmpty) {
      await _flushWriteBuffer();
    }

    // Wait for all operations to complete
    while (_activeOperations > 0 || _isFlushingBuffer) {
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
      _operationQueue.add(
        Completer()
          ..future.then((_) async {
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
          }),
      );
    }

    return completer.future;
  }

  void _processQueue() {
    while (_operationQueue.isNotEmpty &&
        _activeOperations < _maxConcurrentOps) {
      final next = _operationQueue.removeFirst();
      next.complete();
    }
  }

  bool _shouldUseBTree(List<int> key) {
    // Use B+ tree for frequently accessed keys or range queries
    // This is a simple heuristic - could be more sophisticated
    final keyString = String.fromCharCodes(key);
    return keyString.contains(':') || keyString.length < 20;
  }

  /// Flushes write buffer to WAL asynchronously
  Future<void> _flushWriteBuffer() async {
    if (_writeBuffer.isEmpty || _isFlushingBuffer) return;

    _isFlushingBuffer = true;
    _flushTimer?.cancel();
    _flushTimer = null;

    final entriesToFlush = List<_WriteBufferEntry>.from(_writeBuffer);
    _writeBuffer.clear();

    try {
      // Write to WAL asynchronously
      for (final entry in entriesToFlush) {
        _wal.append(entry.key, entry.value); // Don't await
      }
    } finally {
      _isFlushingBuffer = false;

      // Schedule next flush if needed
      if (_writeBuffer.isNotEmpty) {
        _flushTimer = Timer(
          Duration(microseconds: 100),
          () => _flushWriteBuffer(),
        );
      }
    }
  }
}

/// Write buffer entry for async WAL writes
class _WriteBufferEntry {
  final List<int> key;
  final Uint8List value;

  _WriteBufferEntry({required this.key, required this.value});
}
