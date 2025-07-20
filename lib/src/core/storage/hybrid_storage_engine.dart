import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:collection';

import '../../domain/entities/database_entity.dart';
import 'lsm_tree.dart';
import 'btree.dart';
import 'memtable.dart';
import '../wal/write_ahead_log.dart';

// Storage engine
class HybridStorageEngine {
  final String _path;
  final StorageConfig _config;
  final MemTable _memtable;
  final List<MemTable> _immutableMemtables = [];
  final LsmTree _lsmTree;
  final BTree _btree;
  final WriteAheadLog _wal;

  final Queue<Completer> _operationQueue = Queue();
  final int _maxConcurrentOps = 10;
  int _activeOperations = 0;

  Timer? _batchTimer;

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

  // Creates storage engine
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

    // Recover data from WAL
    final walEntries = await wal.recover();
    for (final entry in walEntries) {
      if (entry.type == WALEntryType.put) {
        memtable.put(entry.key, entry.value!);
        if (_shouldUseBTreeStatic(entry.key)) {
          await btree.put(entry.key, entry.value!);
        }
      } else if (entry.type == WALEntryType.delete) {
        memtable.delete(entry.key);
        await btree.delete(entry.key);
      }
    }

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

  // Static helper for BTree check during recovery
  static bool _shouldUseBTreeStatic(List<int> key) {
    final keyString = String.fromCharCodes(key);
    return keyString.contains(':') || keyString.length < 20;
  }

  // Saves key-value
  Future<void> put(List<int> key, Uint8List value) async {
    _ensureOpen();

    if (!_memtable.isFull) {
      final entry = _WriteBufferEntry(key: key, value: value);
      _writeBuffer.add(entry);

      _memtable.put(key, value);

      if (_shouldUseBTree(key)) {
        _btree.put(key, value);
      }

      _flushTimer ??= Timer(
        Duration(microseconds: 100),
        () => _flushWriteBuffer(),
      );

      if (_writeBuffer.length >= _writeBufferSize) {
        _flushWriteBuffer();
      }

      return;
    }

    await _rotateMemtable();
    await put(key, value); // Retry
  }

  // Batch put operation
  Future<void> putBatch(Map<List<int>, Uint8List> entries) async {
    _ensureOpen();

    final walWrites = <Future>[];
    for (final entry in entries.entries) {
      walWrites.add(_wal.append(entry.key, entry.value));
    }

    await Future.wait(walWrites, eagerError: false);

    var totalSize = 0;
    for (final value in entries.values) {
      totalSize += value.length;
    }

    if (_memtable.currentSize + totalSize > _memtable.maxSize) {
      await _rotateMemtable();
    }

    for (final entry in entries.entries) {
      _memtable.put(entry.key, entry.value);

      if (_shouldUseBTree(entry.key)) {
        _btree.put(entry.key, entry.value);
      }
    }
  }

  // Gets value
  Future<Uint8List?> get(List<int> key) async {
    return _queueOperation(() => _getInternal(key));
  }

  // Batch get operation
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

    // Check memtable first - it might have a tombstone
    final keyString = String.fromCharCodes(key);
    if (_memtable.data.containsKey(keyString)) {
      final value = _memtable.data[keyString];
      // If it's a tombstone (null value), return null
      return value;
    }

    for (final immutableMemtable in _immutableMemtables.reversed) {
      final value = immutableMemtable.get(key);
      if (value != null) return value;
    }

    if (_shouldUseBTree(key)) {
      final btreeValue = await _btree.get(key);
      if (btreeValue != null) return btreeValue;
    }

    return await _lsmTree.get(key);
  }

  // Deletes key
  Future<void> delete(List<int> key) async {
    return _queueOperation(() => _deleteInternal(key));
  }

  Future<void> _deleteInternal(List<int> key) async {
    _ensureOpen();

    // Flush any pending writes first to maintain order
    if (_writeBuffer.isNotEmpty) {
      await _flushWriteBuffer();
    }

    await _wal.appendTombstone(key);

    _memtable.delete(key);

    await _btree.delete(key);
  }

  // Compacts database
  Future<void> compact() async {
    _ensureOpen();

    if (_writeBuffer.isNotEmpty) {
      await _flushWriteBuffer();
      await Future.delayed(Duration(milliseconds: 10));
    }

    for (final memtable in _immutableMemtables) {
      await _lsmTree.flush(memtable);
    }
    _immutableMemtables.clear();

    await _lsmTree.compact();

    await _wal.checkpoint();
  }

  // Gets database size
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

  // Gets entry count
  Future<int> getEntryCount() async {
    _ensureOpen();

    int count = _memtable.size;
    for (final memtable in _immutableMemtables) {
      count += memtable.size;
    }
    count += await _lsmTree.getEntryCount();

    return count;
  }

  // Closes storage engine
  Future<void> close() async {
    if (!_isOpen) return;

    _batchTimer?.cancel();
    _flushTimer?.cancel();

    if (_writeBuffer.isNotEmpty) {
      await _flushWriteBuffer();
    }

    while (_activeOperations > 0 || _isFlushingBuffer) {
      await Future.delayed(Duration(milliseconds: 10));
    }

    if (!_memtable.isEmpty) {
      await _lsmTree.flush(_memtable);
    }

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
    final currentMemtable = MemTable.from(_memtable);
    _immutableMemtables.add(currentMemtable);

    _memtable.clear();

    if (_immutableMemtables.length > _config.maxImmutableMemtables) {
      final oldestMemtable = _immutableMemtables.removeAt(0);
      await _lsmTree.flush(oldestMemtable);
    }
  }

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
    final keyString = String.fromCharCodes(key);
    return keyString.contains(':') || keyString.length < 20;
  }

  Future<void> _flushWriteBuffer() async {
    if (_writeBuffer.isEmpty || _isFlushingBuffer) return;

    _isFlushingBuffer = true;
    _flushTimer?.cancel();
    _flushTimer = null;

    final entriesToFlush = List<_WriteBufferEntry>.from(_writeBuffer);
    _writeBuffer.clear();

    try {
      for (final entry in entriesToFlush) {
        await _wal.append(entry.key, entry.value);
      }
    } finally {
      _isFlushingBuffer = false;

      if (_writeBuffer.isNotEmpty) {
        _flushTimer = Timer(
          Duration(microseconds: 100),
          () => _flushWriteBuffer(),
        );
      }
    }
  }
}

// Write buffer entry
class _WriteBufferEntry {
  final List<int> key;
  final Uint8List value;

  _WriteBufferEntry({required this.key, required this.value});
}
