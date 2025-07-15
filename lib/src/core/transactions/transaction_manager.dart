import 'dart:typed_data';
import 'dart:async';
import '../../domain/entities/database_entity.dart';
import '../storage/hybrid_storage_engine.dart';

// Transaction isolation levels
enum IsolationLevel {
  readUncommitted,
  readCommitted,
  repeatableRead,
  serializable,
}

// Transaction states
enum TransactionState { active, committed, aborted, preparing, prepared }

// Lock types
enum LockType { shared, exclusive }

// Lock entry
class LockEntry {
  final String transactionId;
  final LockType type;
  final DateTime acquiredAt;

  LockEntry({
    required this.transactionId,
    required this.type,
    required this.acquiredAt,
  });
}

// Lock manager
class LockManager {
  final Map<String, List<LockEntry>> _locks = {};
  final Map<String, Completer<void>> _waitingQueue = {};

  // Acquires lock
  Future<bool> acquireLock(
    String key,
    String transactionId,
    LockType type,
  ) async {
    if (_canGrantLock(key, transactionId, type)) {
      _grantLock(key, transactionId, type);
      return true;
    }

    final completer = Completer<void>();
    _waitingQueue['${key}_$transactionId'] = completer;

    try {
      await completer.future.timeout(Duration(seconds: 30));
      if (_canGrantLock(key, transactionId, type)) {
        _grantLock(key, transactionId, type);
        return true;
      }
      return false;
    } catch (e) {
      _waitingQueue.remove('${key}_$transactionId');
      return false;
    }
  }

  // Releases locks
  void releaseLocks(String transactionId) {
    final keysToRemove = <String>[];

    for (final entry in _locks.entries) {
      entry.value.removeWhere((lock) => lock.transactionId == transactionId);
      if (entry.value.isEmpty) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _locks.remove(key);
      _notifyWaiters(key);
    }
  }

  // Checks if holds lock
  bool holdsLock(String key, String transactionId, LockType type) {
    final locks = _locks[key] ?? [];
    return locks.any(
      (lock) =>
          lock.transactionId == transactionId &&
          (lock.type == type || lock.type == LockType.exclusive),
    );
  }

  bool _canGrantLock(String key, String transactionId, LockType type) {
    final existingLocks = _locks[key] ?? [];

    if (existingLocks.isEmpty) return true;

    final ownLocks = existingLocks.where(
      (l) => l.transactionId == transactionId,
    );
    if (ownLocks.isNotEmpty) {
      return ownLocks.any(
        (l) => l.type == LockType.exclusive || type == LockType.shared,
      );
    }

    if (type == LockType.shared) {
      return existingLocks.every((l) => l.type == LockType.shared);
    } else {
      return false;
    }
  }

  void _grantLock(String key, String transactionId, LockType type) {
    final locks = _locks.putIfAbsent(key, () => []);
    locks.add(
      LockEntry(
        transactionId: transactionId,
        type: type,
        acquiredAt: DateTime.now(),
      ),
    );
  }

  void _notifyWaiters(String key) {
    final waitersToNotify = <Completer<void>>[];

    for (final entry in _waitingQueue.entries) {
      if (entry.key.startsWith('${key}_')) {
        waitersToNotify.add(entry.value);
      }
    }

    for (final waiter in waitersToNotify) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}

// Transaction operation
class TransactionOperation {
  final String type;
  final String key;
  final Uint8List? value;
  final DateTime timestamp;

  TransactionOperation({
    required this.type,
    required this.key,
    this.value,
    required this.timestamp,
  });
}

// MVCC version
class MVCCVersion {
  final Uint8List value;
  final String transactionId;
  final DateTime timestamp;
  final bool isDeleted;

  MVCCVersion({
    required this.value,
    required this.transactionId,
    required this.timestamp,
    this.isDeleted = false,
  });
}

// Transaction
class Transaction {
  final String id;
  final IsolationLevel isolationLevel;
  final DateTime startTime;
  final HybridStorageEngine _storageEngine;
  final LockManager _lockManager;

  TransactionState _state = TransactionState.active;
  final Map<String, TransactionOperation> _writeSet = {};
  final Map<String, MVCCVersion> _readSet = {};
  final List<TransactionOperation> _operationLog = [];

  Transaction({
    required this.id,
    required this.isolationLevel,
    required HybridStorageEngine storageEngine,
    required LockManager lockManager,
  }) : startTime = DateTime.now(),
       _storageEngine = storageEngine,
       _lockManager = lockManager;

  // Gets value
  Future<Uint8List?> get(String key) async {
    if (_state != TransactionState.active) {
      throw StateError('Transaction is not active');
    }

    final keyBytes = key.codeUnits;

    final writeOp = _writeSet[key];
    if (writeOp != null) {
      return writeOp.type == 'delete' ? null : writeOp.value;
    }

    if (isolationLevel != IsolationLevel.readUncommitted) {
      final lockAcquired = await _lockManager.acquireLock(
        key,
        id,
        LockType.shared,
      );
      if (!lockAcquired) {
        throw Exception('Failed to acquire read lock for key: $key');
      }
    }

    final value = await _storageEngine.get(keyBytes);

    if (value != null) {
      _readSet[key] = MVCCVersion(
        value: value,
        transactionId: id,
        timestamp: DateTime.now(),
      );
    }

    return value;
  }

  // Puts value
  Future<void> put(String key, Uint8List value) async {
    if (_state != TransactionState.active) {
      throw StateError('Transaction is not active');
    }

    final lockAcquired = await _lockManager.acquireLock(
      key,
      id,
      LockType.exclusive,
    );
    if (!lockAcquired) {
      throw Exception('Failed to acquire write lock for key: $key');
    }

    final operation = TransactionOperation(
      type: 'put',
      key: key,
      value: value,
      timestamp: DateTime.now(),
    );

    _writeSet[key] = operation;
    _operationLog.add(operation);
  }

  // Deletes key
  Future<void> delete(String key) async {
    if (_state != TransactionState.active) {
      throw StateError('Transaction is not active');
    }

    final lockAcquired = await _lockManager.acquireLock(
      key,
      id,
      LockType.exclusive,
    );
    if (!lockAcquired) {
      throw Exception('Failed to acquire write lock for key: $key');
    }

    final operation = TransactionOperation(
      type: 'delete',
      key: key,
      value: null,
      timestamp: DateTime.now(),
    );

    _writeSet[key] = operation;
    _operationLog.add(operation);
  }

  // Commits transaction
  Future<void> commit() async {
    if (_state != TransactionState.active) {
      throw StateError('Transaction is not active');
    }

    _state = TransactionState.preparing;

    try {
      if (isolationLevel == IsolationLevel.repeatableRead ||
          isolationLevel == IsolationLevel.serializable) {
        await _validateReadSet();
      }

      for (final operation in _writeSet.values) {
        final keyBytes = operation.key.codeUnits;

        if (operation.type == 'put') {
          await _storageEngine.put(keyBytes, operation.value!);
        } else if (operation.type == 'delete') {
          await _storageEngine.delete(keyBytes);
        }
      }

      _state = TransactionState.committed;
    } catch (e) {
      _state = TransactionState.aborted;
      rethrow;
    } finally {
      _lockManager.releaseLocks(id);
    }
  }

  // Aborts transaction
  Future<void> abort() async {
    _state = TransactionState.aborted;
    _lockManager.releaseLocks(id);
  }

  // Gets state
  TransactionState get state => _state;

  // Gets write set size
  int get writeSetSize => _writeSet.length;

  // Gets read set size
  int get readSetSize => _readSet.length;

  // Gets operation count
  int get operationCount => _operationLog.length;

  Future<void> _validateReadSet() async {
    for (final entry in _readSet.entries) {
      final key = entry.key;
      final expectedVersion = entry.value;

      final currentValue = await _storageEngine.get(key.codeUnits);

      if (currentValue == null && expectedVersion.value.isNotEmpty) {
        throw Exception('Read set validation failed: key $key was deleted');
      }

      if (currentValue != null &&
          !_bytesEqual(currentValue, expectedVersion.value)) {
        throw Exception('Read set validation failed: key $key was modified');
      }
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// Transaction manager
class TransactionManager {
  final HybridStorageEngine _storageEngine;
  final LockManager _lockManager = LockManager();
  final Map<String, Transaction> _activeTransactions = {};
  final IsolationLevel _defaultIsolationLevel;

  int _transactionCounter = 0;
  int _committedCount = 0;
  int _abortedCount = 0;

  TransactionManager({
    required HybridStorageEngine storageEngine,
    IsolationLevel defaultIsolationLevel = IsolationLevel.readCommitted,
  }) : _storageEngine = storageEngine,
       _defaultIsolationLevel = defaultIsolationLevel;

  // Begins transaction
  Transaction beginTransaction({IsolationLevel? isolationLevel}) {
    final id =
        'tx_${++_transactionCounter}_${DateTime.now().millisecondsSinceEpoch}';

    final transaction = Transaction(
      id: id,
      isolationLevel: isolationLevel ?? _defaultIsolationLevel,
      storageEngine: _storageEngine,
      lockManager: _lockManager,
    );

    _activeTransactions[id] = transaction;
    return transaction;
  }

  // Commits transaction
  Future<void> commitTransaction(Transaction transaction) async {
    try {
      await transaction.commit();
      _activeTransactions.remove(transaction.id);
      _committedCount++;
    } catch (e) {
      await abortTransaction(transaction);
      rethrow;
    }
  }

  // Aborts transaction
  Future<void> abortTransaction(Transaction transaction) async {
    await transaction.abort();
    _activeTransactions.remove(transaction.id);
    _abortedCount++;
  }

  // Gets transaction by ID
  Transaction? getTransaction(String id) {
    return _activeTransactions[id];
  }

  // Gets active transactions
  List<Transaction> getActiveTransactions() {
    return _activeTransactions.values.toList();
  }

  // Gets statistics
  TransactionStats getStats() {
    final avgTransactionTime =
        _activeTransactions.values.isNotEmpty
            ? _activeTransactions.values
                    .map(
                      (tx) =>
                          DateTime.now()
                              .difference(tx.startTime)
                              .inMilliseconds,
                    )
                    .reduce((a, b) => a + b) /
                _activeTransactions.length
            : 0.0;

    return TransactionStats(
      activeTransactions: _activeTransactions.length,
      committedTransactions: _committedCount,
      abortedTransactions: _abortedCount,
      averageTransactionTime: avgTransactionTime,
    );
  }

  // Executes in transaction
  Future<T> executeTransaction<T>(
    Future<T> Function(Transaction) operation, {
    IsolationLevel? isolationLevel,
    int maxRetries = 3,
  }) async {
    int retries = 0;

    while (retries <= maxRetries) {
      final transaction = beginTransaction(isolationLevel: isolationLevel);

      try {
        final result = await operation(transaction);
        await commitTransaction(transaction);
        return result;
      } catch (e) {
        await abortTransaction(transaction);

        if (retries == maxRetries) {
          rethrow;
        }

        retries++;
        await Future.delayed(Duration(milliseconds: 100 * (1 << retries)));
      }
    }

    throw Exception('Transaction failed after $maxRetries retries');
  }

  // Closes manager
  Future<void> close() async {
    for (final transaction in _activeTransactions.values.toList()) {
      await abortTransaction(transaction);
    }
  }
}
