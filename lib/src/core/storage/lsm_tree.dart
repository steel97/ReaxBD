import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;

import 'memtable.dart';
import 'sstable.dart';

/// LSM (Log-Structured Merge) Tree implementation for write optimization
class LsmTree {
  final String _path;
  final List<List<SSTable>> _levels = [];
  final Map<int, int> _levelSizes = {};
  
  static const int _maxLevel = 7;
  static const int _levelMultiplier = 10;

  LsmTree._({
    required String path,
  })  : _path = path {
    // Initialize levels
    for (int i = 0; i < _maxLevel; i++) {
      _levels.add(<SSTable>[]);
      _levelSizes[i] = _calculateLevelSize(i);
    }
  }

  /// Creates a new LSM tree
  static Future<LsmTree> create({
    required String basePath,
  }) async {
    final lsmPath = path.join(basePath, 'lsm');
    final directory = Directory(lsmPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final lsmTree = LsmTree._(path: lsmPath);
    await lsmTree._loadExistingSSTables();
    return lsmTree;
  }

  /// Flushes a memtable to Level 0
  Future<void> flush(MemTable memtable) async {
    if (memtable.isEmpty) return;

    final sstable = await SSTable.create(
      basePath: _path,
      level: 0,
      entries: memtable.entries,
    );

    _levels[0].add(sstable);

    // Check if Level 0 needs compaction
    if (_levels[0].length >= _levelSizes[0]!) {
      await _compactLevel(0);
    }
  }

  /// Gets a value by key
  Future<Uint8List?> get(List<int> key) async {
    // Search from Level 0 (newest) to higher levels (oldest)
    for (int level = 0; level < _levels.length; level++) {
      for (final sstable in _levels[level].reversed) {
        final value = await sstable.get(key);
        if (value != null) {
          // Check if it's a tombstone
          if (value.isEmpty) return null;
          return value;
        }
      }
    }
    return null;
  }

  /// Compacts the LSM tree
  Future<void> compact() async {
    for (int level = 0; level < _levels.length - 1; level++) {
      if (_levels[level].length >= _levelSizes[level]!) {
        await _compactLevel(level);
      }
    }
  }

  /// Gets entry count across all levels
  Future<int> getEntryCount() async {
    int count = 0;
    for (final level in _levels) {
      for (final sstable in level) {
        count += await sstable.getEntryCount();
      }
    }
    return count;
  }

  /// Closes the LSM tree
  Future<void> close() async {
    for (final level in _levels) {
      for (final sstable in level) {
        await sstable.close();
      }
    }
  }

  Future<void> _loadExistingSSTables() async {
    final directory = Directory(_path);
    if (!await directory.exists()) return;

    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.sst')) {
        final fileName = path.basename(entity.path);
        final parts = fileName.split('_');
        if (parts.length >= 3) {
          final level = int.tryParse(parts[1]);
          if (level != null && level < _levels.length) {
            final sstable = await SSTable.load(entity.path);
            _levels[level].add(sstable);
          }
        }
      }
    }

    // Sort SSTables in each level by creation time
    for (final level in _levels) {
      level.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
  }

  Future<void> _compactLevel(int level) async {
    if (level >= _levels.length - 1) return;

    final currentLevel = _levels[level];
    final nextLevel = _levels[level + 1];

    if (currentLevel.isEmpty) return;

    // Simple compaction strategy: merge all SSTables in current level
    final mergedEntries = <List<int>, Uint8List>{};
    
    for (final sstable in currentLevel) {
      final entries = await sstable.getAllEntries();
      for (final entry in entries.entries) {
        // Latest write wins
        mergedEntries[entry.key] = entry.value;
      }
    }

    // Create new SSTable in next level
    if (mergedEntries.isNotEmpty) {
      final newSSTable = await SSTable.create(
        basePath: _path,
        level: level + 1,
        entries: mergedEntries,
      );
      nextLevel.add(newSSTable);
    }

    // Remove old SSTables
    for (final sstable in currentLevel) {
      await sstable.delete();
    }
    currentLevel.clear();

    // Check if next level needs compaction
    if (nextLevel.length >= _levelSizes[level + 1]!) {
      await _compactLevel(level + 1);
    }
  }

  int _calculateLevelSize(int level) {
    if (level == 0) return 4; // Level 0 can have up to 4 SSTables
    return _levelMultiplier * level; // Each level is 10x larger than previous
  }
}