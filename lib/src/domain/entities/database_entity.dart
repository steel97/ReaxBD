/// Represents a database entry
class DatabaseEntry {
  final String key;
  final dynamic value;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  const DatabaseEntry({
    required this.key,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });

  DatabaseEntry copyWith({
    String? key,
    dynamic value,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
  }) {
    return DatabaseEntry(
      key: key ?? this.key,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatabaseEntry &&
        other.key == key &&
        other.value == value &&
        other.version == version;
  }

  @override
  int get hashCode {
    return key.hashCode ^ value.hashCode ^ version.hashCode;
  }

  @override
  String toString() {
    return 'DatabaseEntry(key: $key, value: $value, version: $version)';
  }
}

/// Database state information
class DatabaseInfo {
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime lastAccessed;
  final int entryCount;
  final int sizeBytes;
  final bool isEncrypted;

  const DatabaseInfo({
    required this.name,
    required this.path,
    required this.createdAt,
    required this.lastAccessed,
    required this.entryCount,
    required this.sizeBytes,
    required this.isEncrypted,
  });

  @override
  String toString() {
    return 'DatabaseInfo(name: $name, entries: $entryCount, size: ${(sizeBytes / 1024).toStringAsFixed(1)}KB)';
  }
}

/// Storage engine configuration
class StorageConfig {
  final int memtableSize;
  final int pageSize;
  final bool compressionEnabled;
  final bool syncWrites;
  final int maxImmutableMemtables;

  const StorageConfig({
    required this.memtableSize,
    required this.pageSize,
    required this.compressionEnabled,
    required this.syncWrites,
    required this.maxImmutableMemtables,
  });

  factory StorageConfig.defaultConfig() => const StorageConfig(
    memtableSize: 4 * 1024 * 1024, // 4MB
    pageSize: 4096, // 4KB
    compressionEnabled: true,
    syncWrites: true,
    maxImmutableMemtables: 4,
  );
}

/// Cache statistics
class CacheStats {
  final int l1Hits;
  final int l1Misses;
  final int l2Hits;
  final int l2Misses;
  final int l3Hits;
  final int l3Misses;
  final int totalEntries;
  final double hitRatio;

  const CacheStats({
    required this.l1Hits,
    required this.l1Misses,
    required this.l2Hits,
    required this.l2Misses,
    required this.l3Hits,
    required this.l3Misses,
    required this.totalEntries,
    required this.hitRatio,
  });

  @override
  String toString() {
    return 'CacheStats(entries: $totalEntries, hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%)';
  }
}

/// Transaction statistics
class TransactionStats {
  final int activeTransactions;
  final int committedTransactions;
  final int abortedTransactions;
  final double averageTransactionTime;

  const TransactionStats({
    required this.activeTransactions,
    required this.committedTransactions,
    required this.abortedTransactions,
    required this.averageTransactionTime,
  });

  @override
  String toString() {
    return 'TransactionStats(active: $activeTransactions, committed: $committedTransactions, aborted: $abortedTransactions)';
  }
}
