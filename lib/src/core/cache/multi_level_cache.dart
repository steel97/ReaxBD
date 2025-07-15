import 'dart:typed_data';
import 'dart:collection';
import '../../domain/entities/database_entity.dart';

// Cache levels
enum CacheLevel { l1, l2, l3 }

// Cache entry
class CacheEntry {
  final String key;
  final Uint8List value;
  final DateTime accessTime;
  final DateTime createdTime;
  final int accessCount;
  final int size;

  CacheEntry({
    required this.key,
    required this.value,
    required this.accessTime,
    required this.createdTime,
    required this.accessCount,
    required this.size,
  });

  CacheEntry copyWithAccess() {
    return CacheEntry(
      key: key,
      value: value,
      accessTime: DateTime.now(),
      createdTime: createdTime,
      accessCount: accessCount + 1,
      size: size,
    );
  }
}

// LRU Cache
class LRUCache {
  final int _maxSize;
  final int _maxMemory;
  final LinkedHashMap<String, CacheEntry> _cache = LinkedHashMap();
  int _currentMemory = 0;
  int _hits = 0;
  int _misses = 0;

  LRUCache({required int maxSize, required int maxMemory})
    : _maxSize = maxSize,
      _maxMemory = maxMemory;

  // Gets value
  Uint8List? get(String key) {
    final entry = _cache[key];
    if (entry != null) {
      _cache.remove(key);
      final updatedEntry = entry.copyWithAccess();
      _cache[key] = updatedEntry;
      _hits++;
      return entry.value;
    }
    _misses++;
    return null;
  }

  // Puts value
  void put(String key, Uint8List value) {
    final entrySize = key.length + value.length + 64;

    if (_cache.containsKey(key)) {
      final oldEntry = _cache.remove(key)!;
      _currentMemory -= oldEntry.size;
    }

    while ((_cache.length >= _maxSize ||
            _currentMemory + entrySize > _maxMemory) &&
        _cache.isNotEmpty) {
      _evictLeastRecentlyUsed();
    }

    final entry = CacheEntry(
      key: key,
      value: value,
      accessTime: DateTime.now(),
      createdTime: DateTime.now(),
      accessCount: 1,
      size: entrySize,
    );

    _cache[key] = entry;
    _currentMemory += entrySize;
  }

  // Removes key
  void remove(String key) {
    final entry = _cache.remove(key);
    if (entry != null) {
      _currentMemory -= entry.size;
    }
  }

  // Clears cache
  void clear() {
    _cache.clear();
    _currentMemory = 0;
  }

  // Gets statistics
  Map<String, dynamic> getStats() {
    final totalRequests = _hits + _misses;
    final hitRatio = totalRequests > 0 ? _hits / totalRequests : 0.0;

    return {
      'entries': _cache.length,
      'memory': _currentMemory,
      'hits': _hits,
      'misses': _misses,
      'hitRatio': hitRatio,
    };
  }

  void _evictLeastRecentlyUsed() {
    if (_cache.isNotEmpty) {
      final firstKey = _cache.keys.first;
      final entry = _cache.remove(firstKey)!;
      _currentMemory -= entry.size;
    }
  }

  // Gets size
  int get size => _cache.length;

  // Gets memory usage
  int get memoryUsage => _currentMemory;

  // Gets hits
  int get hits => _hits;

  // Gets misses
  int get misses => _misses;
}

// LFU Cache
class LFUCache {
  final int _maxSize;
  final int _maxMemory;
  final Map<String, CacheEntry> _cache = {};
  final Map<String, int> _frequencies = {};
  final Map<int, LinkedHashSet<String>> _frequencyGroups = {};
  int _minFrequency = 1;
  int _currentMemory = 0;
  int _hits = 0;
  int _misses = 0;

  LFUCache({required int maxSize, required int maxMemory})
    : _maxSize = maxSize,
      _maxMemory = maxMemory;

  // Gets value
  Uint8List? get(String key) {
    final entry = _cache[key];
    if (entry != null) {
      _updateFrequency(key);
      _hits++;
      return entry.value;
    }
    _misses++;
    return null;
  }

  // Puts value
  void put(String key, Uint8List value) {
    final entrySize = key.length + value.length + 64;

    if (_cache.containsKey(key)) {
      final oldEntry = _cache[key]!;
      _currentMemory -= oldEntry.size;

      final updatedEntry = CacheEntry(
        key: key,
        value: value,
        accessTime: DateTime.now(),
        createdTime: oldEntry.createdTime,
        accessCount: oldEntry.accessCount + 1,
        size: entrySize,
      );

      _cache[key] = updatedEntry;
      _currentMemory += entrySize;
      _updateFrequency(key);
      return;
    }

    while ((_cache.length >= _maxSize ||
            _currentMemory + entrySize > _maxMemory) &&
        _cache.isNotEmpty) {
      _evictLeastFrequentlyUsed();
    }

    final entry = CacheEntry(
      key: key,
      value: value,
      accessTime: DateTime.now(),
      createdTime: DateTime.now(),
      accessCount: 1,
      size: entrySize,
    );

    _cache[key] = entry;
    _frequencies[key] = 1;
    _frequencyGroups.putIfAbsent(1, () => LinkedHashSet()).add(key);
    _currentMemory += entrySize;
    _minFrequency = 1;
  }

  // Removes key
  void remove(String key) {
    final entry = _cache.remove(key);
    if (entry != null) {
      final frequency = _frequencies.remove(key)!;
      _frequencyGroups[frequency]?.remove(key);
      _currentMemory -= entry.size;
    }
  }

  // Clears cache
  void clear() {
    _cache.clear();
    _frequencies.clear();
    _frequencyGroups.clear();
    _currentMemory = 0;
    _minFrequency = 1;
  }

  // Gets statistics
  Map<String, dynamic> getStats() {
    final totalRequests = _hits + _misses;
    final hitRatio = totalRequests > 0 ? _hits / totalRequests : 0.0;

    return {
      'entries': _cache.length,
      'memory': _currentMemory,
      'hits': _hits,
      'misses': _misses,
      'hitRatio': hitRatio,
    };
  }

  void _updateFrequency(String key) {
    final frequency = _frequencies[key]!;
    _frequencyGroups[frequency]!.remove(key);

    if (_frequencyGroups[frequency]!.isEmpty && frequency == _minFrequency) {
      _minFrequency++;
    }

    final newFrequency = frequency + 1;
    _frequencies[key] = newFrequency;
    _frequencyGroups.putIfAbsent(newFrequency, () => LinkedHashSet()).add(key);
  }

  void _evictLeastFrequentlyUsed() {
    final keys = _frequencyGroups[_minFrequency]!;
    final keyToEvict = keys.first;

    keys.remove(keyToEvict);
    _frequencies.remove(keyToEvict);
    final entry = _cache.remove(keyToEvict)!;
    _currentMemory -= entry.size;
  }

  // Gets size
  int get size => _cache.length;

  // Gets memory usage
  int get memoryUsage => _currentMemory;

  // Gets hits
  int get hits => _hits;

  // Gets misses
  int get misses => _misses;
}

// Multi-level cache
class MultiLevelCache {
  final LRUCache _l1Cache;
  final LRUCache _l2Cache;
  final LFUCache _l3Cache;

  MultiLevelCache({
    int l1MaxSize = 1000,
    int l1MaxMemory = 16 * 1024 * 1024,
    int l2MaxSize = 5000,
    int l2MaxMemory = 64 * 1024 * 1024,
    int l3MaxSize = 10000,
    int l3MaxMemory = 256 * 1024 * 1024,
  }) : _l1Cache = LRUCache(maxSize: l1MaxSize, maxMemory: l1MaxMemory),
       _l2Cache = LRUCache(maxSize: l2MaxSize, maxMemory: l2MaxMemory),
       _l3Cache = LFUCache(maxSize: l3MaxSize, maxMemory: l3MaxMemory);

  // Gets value from cache
  Uint8List? get(String key, {CacheLevel? preferredLevel}) {
    final l1Value = _l1Cache.get(key);
    if (l1Value != null) {
      return l1Value;
    }

    final l2Value = _l2Cache.get(key);
    if (l2Value != null) {
      _l1Cache.put(key, l2Value);
      return l2Value;
    }

    final l3Value = _l3Cache.get(key);
    if (l3Value != null) {
      _l2Cache.put(key, l3Value);
      _l1Cache.put(key, l3Value);
      return l3Value;
    }

    return null;
  }

  // Puts value in cache
  void put(String key, Uint8List value, {CacheLevel level = CacheLevel.l1}) {
    switch (level) {
      case CacheLevel.l1:
        _l1Cache.put(key, value);
        break;
      case CacheLevel.l2:
        _l2Cache.put(key, value);
        _l1Cache.put(key, value);
        break;
      case CacheLevel.l3:
        _l3Cache.put(key, value);
        break;
    }
  }

  // Removes key from all levels
  void remove(String key) {
    _l1Cache.remove(key);
    _l2Cache.remove(key);
    _l3Cache.remove(key);
  }

  // Clears all levels
  void clear() {
    _l1Cache.clear();
    _l2Cache.clear();
    _l3Cache.clear();
  }

  // Gets cache statistics
  CacheStats getStats() {
    final l1Stats = _l1Cache.getStats();
    final l2Stats = _l2Cache.getStats();
    final l3Stats = _l3Cache.getStats();

    final totalHits = l1Stats['hits'] + l2Stats['hits'] + l3Stats['hits'];
    final totalMisses =
        l1Stats['misses'] + l2Stats['misses'] + l3Stats['misses'];
    final totalRequests = totalHits + totalMisses;
    final hitRatio = totalRequests > 0 ? totalHits / totalRequests : 0.0;

    return CacheStats(
      l1Hits: l1Stats['hits'],
      l1Misses: l1Stats['misses'],
      l2Hits: l2Stats['hits'],
      l2Misses: l2Stats['misses'],
      l3Hits: l3Stats['hits'],
      l3Misses: l3Stats['misses'],
      totalEntries:
          l1Stats['entries'] + l2Stats['entries'] + l3Stats['entries'],
      hitRatio: hitRatio,
    );
  }

  // Gets total memory usage
  int getTotalMemoryUsage() {
    return _l1Cache.memoryUsage + _l2Cache.memoryUsage + _l3Cache.memoryUsage;
  }

  // Gets total entries
  int getTotalEntryCount() {
    return _l1Cache.size + _l2Cache.size + _l3Cache.size;
  }

  // Invalidates by pattern
  void invalidatePattern(String pattern) {
    final regex = RegExp(pattern);

    final l1Keys = _l1Cache._cache.keys.where(regex.hasMatch).toList();
    final l2Keys = _l2Cache._cache.keys.where(regex.hasMatch).toList();
    final l3Keys = _l3Cache._cache.keys.where(regex.hasMatch).toList();

    for (final key in l1Keys) {
      _l1Cache.remove(key);
    }
    for (final key in l2Keys) {
      _l2Cache.remove(key);
    }
    for (final key in l3Keys) {
      _l3Cache.remove(key);
    }
  }

  // Preloads data
  void preload(
    Map<String, Uint8List> data, {
    CacheLevel level = CacheLevel.l2,
  }) {
    for (final entry in data.entries) {
      put(entry.key, entry.value, level: level);
    }
  }
}
