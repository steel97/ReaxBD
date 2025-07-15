import 'dart:typed_data';
import 'dart:collection';

/// In-memory table for fast writes before flushing to disk - OPTIMIZED
class MemTable {
  final int _maxSize;
  final SplayTreeMap<String, Uint8List?> _data = SplayTreeMap();
  final Map<String, String> _keyCache = {}; // Cache for key conversions
  int _currentSize = 0;

  MemTable({required int maxSize}) : _maxSize = maxSize;

  /// Creates a copy of another memtable
  MemTable.from(MemTable other) : _maxSize = other._maxSize {
    _data.addAll(other._data);
    _currentSize = other._currentSize;
  }

  /// Puts a key-value pair - OPTIMIZED
  void put(List<int> key, Uint8List value) {
    final keyString = _keyToStringOptimized(key);
    final oldValue = _data[keyString];

    _data[keyString] = value;

    // Update size efficiently
    if (oldValue != null) {
      _currentSize -= oldValue.length;
    }
    _currentSize += value.length + keyString.length;
  }

  /// Gets a value by key - OPTIMIZED for speed
  Uint8List? get(List<int> key) {
    final keyString = _keyToStringOptimized(key);
    final value = _data[keyString];

    // Return null if value is null (deleted) or if it's a tombstone
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Deletes a key (adds tombstone) - OPTIMIZED
  void delete(List<int> key) {
    final keyString = _keyToStringOptimized(key);
    final oldValue = _data[keyString];

    // Add tombstone (empty value)
    _data[keyString] = Uint8List(0);

    // Update size
    if (oldValue != null) {
      _currentSize -= oldValue.length;
    }
    _currentSize += keyString.length;
  }

  /// Checks if key exists - OPTIMIZED
  bool containsKey(List<int> key) {
    final keyString = _keyToStringOptimized(key);
    return _data.containsKey(keyString) && _data[keyString]!.isNotEmpty;
  }

  /// Gets all entries as a map
  Map<List<int>, Uint8List> get entries {
    final result = <List<int>, Uint8List>{};
    for (final entry in _data.entries) {
      if (entry.value != null && entry.value!.isNotEmpty) {
        result[_stringToKey(entry.key)] = entry.value!;
      }
    }
    return result;
  }

  /// Gets all entries including tombstones
  Map<List<int>, Uint8List?> get allEntries {
    final result = <List<int>, Uint8List?>{};
    for (final entry in _data.entries) {
      result[_stringToKey(entry.key)] = entry.value;
    }
    return result;
  }

  /// Clears the memtable - OPTIMIZED
  void clear() {
    _data.clear();
    _keyCache.clear();
    _currentSize = 0;
  }

  /// Checks if memtable is full
  bool get isFull => _currentSize >= _maxSize;

  /// Checks if memtable is empty
  bool get isEmpty => _data.isEmpty;

  /// Gets current size in bytes
  int get size => _data.length;

  /// Gets current memory usage in bytes
  int get memoryUsage => _currentSize;

  /// Gets current size in bytes (for compatibility)
  int get currentSize => _currentSize;

  /// Gets maximum size in bytes
  int get maxSize => _maxSize;

  /// Gets keys in sorted order
  Iterable<List<int>> get keys => _data.keys.map(_stringToKey);

  /// Gets first key
  List<int>? get firstKey {
    if (_data.isEmpty) return null;
    return _stringToKey(_data.firstKey()!);
  }

  /// Gets last key
  List<int>? get lastKey {
    if (_data.isEmpty) return null;
    return _stringToKey(_data.lastKey()!);
  }

  /// Gets range of entries
  Map<List<int>, Uint8List> getRange(List<int>? startKey, List<int>? endKey) {
    final result = <List<int>, Uint8List>{};

    final startKeyString = startKey != null ? _keyToString(startKey) : null;
    final endKeyString = endKey != null ? _keyToString(endKey) : null;

    for (final entry in _data.entries) {
      if (startKeyString != null && entry.key.compareTo(startKeyString) < 0) {
        continue;
      }
      if (endKeyString != null && entry.key.compareTo(endKeyString) >= 0) {
        break;
      }
      if (entry.value != null && entry.value!.isNotEmpty) {
        result[_stringToKey(entry.key)] = entry.value!;
      }
    }

    return result;
  }

  /// Optimized key conversion with caching for frequently used keys
  String _keyToStringOptimized(List<int> key) {
    // For small keys, use direct conversion (fastest)
    if (key.length <= 32) {
      return String.fromCharCodes(key);
    }

    // For larger keys, use caching
    final keyHash = key.fold(0, (prev, element) => prev ^ element).toString();
    return _keyCache.putIfAbsent(keyHash, () => String.fromCharCodes(key));
  }

  String _keyToString(List<int> key) {
    return String.fromCharCodes(key);
  }

  List<int> _stringToKey(String keyString) {
    return keyString.codeUnits;
  }

  /// Batch operations for better performance
  void putBatch(Map<List<int>, Uint8List> entries) {
    for (final entry in entries.entries) {
      put(entry.key, entry.value);
    }
  }

  /// Get multiple keys at once
  Map<List<int>, Uint8List?> getBatch(List<List<int>> keys) {
    final result = <List<int>, Uint8List?>{};
    for (final key in keys) {
      result[key] = get(key);
    }
    return result;
  }

  /// Efficient prefix scan
  Map<List<int>, Uint8List> scanPrefix(List<int> prefix) {
    final result = <List<int>, Uint8List>{};
    final prefixString = _keyToString(prefix);

    for (final entry in _data.entries) {
      if (entry.key.startsWith(prefixString) &&
          entry.value != null &&
          entry.value!.isNotEmpty) {
        result[_stringToKey(entry.key)] = entry.value!;
      }
    }

    return result;
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'entries': _data.length,
      'memoryUsage': _currentSize,
      'maxSize': _maxSize,
      'utilizationPercent': (_currentSize / _maxSize * 100).toStringAsFixed(1),
      'cacheHits': _keyCache.length,
    };
  }

  @override
  String toString() {
    return 'MemTable(entries: ${_data.length}, size: ${(_currentSize / 1024).toStringAsFixed(1)}KB, util: ${(_currentSize / _maxSize * 100).toStringAsFixed(1)}%)';
  }
}
