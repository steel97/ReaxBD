import 'dart:async';
import 'dart:math';
import '../logging/logger.dart';

/// Transaction isolation levels
enum IsolationLevel {
  readUncommitted,
  readCommitted,
  repeatableRead,
  serializable,
}

/// Transaction type
enum TransactionType { readWrite, readOnly }

/// Savepoint for nested transactions
class Savepoint {
  final String name;
  final Map<String, dynamic> snapshot;
  final DateTime created;

  Savepoint({required this.name, required this.snapshot})
    : created = DateTime.now();
}

/// Enhanced transaction with advanced features
class EnhancedTransaction {
  final String id;
  final TransactionType type;
  final IsolationLevel isolationLevel;
  final Duration? timeout;
  final int maxRetries;
  final Duration retryDelay;

  final Map<String, dynamic> _changes = {};
  final Map<String, dynamic> _originalValues = {};
  final List<Savepoint> _savepoints = [];
  final List<EnhancedTransaction> _nestedTransactions = [];

  bool _isCommitted = false;
  bool _isRolledBack = false;
  int _retryCount = 0;
  DateTime? _startTime;
  final EnhancedTransaction? _parent;

  EnhancedTransaction({
    required this.id,
    this.type = TransactionType.readWrite,
    this.isolationLevel = IsolationLevel.readCommitted,
    this.timeout,
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 100),
    EnhancedTransaction? parent,
  }) : _parent = parent {
    _startTime = DateTime.now();
  }

  /// Check if transaction is read-only
  bool get isReadOnly => type == TransactionType.readOnly;

  /// Check if transaction is active
  bool get isActive => !_isCommitted && !_isRolledBack;

  /// Check if transaction has timed out
  bool get hasTimedOut {
    if (timeout == null || _startTime == null) return false;
    return DateTime.now().difference(_startTime!) > timeout!;
  }

  /// Get a value within the transaction
  Future<T?> get<T>(String key, Future<T?> Function(String) getter) async {
    _checkActive();
    _checkTimeout();

    // Check local changes first
    if (_changes.containsKey(key)) {
      return _changes[key] as T?;
    }

    // Check parent transaction if nested
    if (_parent != null) {
      return _parent!.get(key, getter);
    }

    // Get from storage and track for repeatable read
    final value = await getter(key);
    if (isolationLevel == IsolationLevel.repeatableRead ||
        isolationLevel == IsolationLevel.serializable) {
      _originalValues[key] = value;
    }

    return value;
  }

  /// Put a value within the transaction
  Future<void> put(
    String key,
    dynamic value,
    Future<void> Function(String, dynamic) putter,
  ) async {
    _checkActive();
    _checkTimeout();
    _checkReadOnly();

    // Track original value if not already tracked
    if (!_originalValues.containsKey(key) && !_changes.containsKey(key)) {
      // This would need to be fetched from storage in real implementation
      _originalValues[key] = null;
    }

    _changes[key] = value;
  }

  /// Delete a value within the transaction
  Future<void> delete(String key, Future<void> Function(String) deleter) async {
    _checkActive();
    _checkTimeout();
    _checkReadOnly();

    // Track original value if not already tracked
    if (!_originalValues.containsKey(key) && !_changes.containsKey(key)) {
      _originalValues[key] = null;
    }

    _changes[key] = null; // null represents deletion
  }

  /// Create a savepoint
  Future<String> savepoint(String name) async {
    _checkActive();
    _checkTimeout();

    final savepoint = Savepoint(name: name, snapshot: Map.from(_changes));

    _savepoints.add(savepoint);
    logger.debug('Created savepoint: $name in transaction $id');

    return name;
  }

  /// Rollback to a savepoint
  Future<void> rollbackToSavepoint(String name) async {
    _checkActive();
    _checkTimeout();

    final index = _savepoints.lastIndexWhere((sp) => sp.name == name);
    if (index == -1) {
      throw StateError('Savepoint $name not found');
    }

    final savepoint = _savepoints[index];
    _changes.clear();
    _changes.addAll(savepoint.snapshot);

    // Remove all savepoints after this one
    _savepoints.removeRange(index + 1, _savepoints.length);

    logger.debug('Rolled back to savepoint: $name in transaction $id');
  }

  /// Release a savepoint
  Future<void> releaseSavepoint(String name) async {
    _checkActive();

    _savepoints.removeWhere((sp) => sp.name == name);
    logger.debug('Released savepoint: $name in transaction $id');
  }

  /// Begin a nested transaction
  Future<EnhancedTransaction> beginNested({
    TransactionType? type,
    IsolationLevel? isolationLevel,
  }) async {
    _checkActive();
    _checkTimeout();

    final nested = EnhancedTransaction(
      id: '$id-nested-${_nestedTransactions.length + 1}',
      type: type ?? this.type,
      isolationLevel: isolationLevel ?? this.isolationLevel,
      timeout: timeout,
      parent: this,
    );

    _nestedTransactions.add(nested);
    logger.debug('Started nested transaction: ${nested.id}');

    return nested;
  }

  /// Commit the transaction
  Future<void> commit(
    Future<void> Function(Map<String, dynamic>) committer,
  ) async {
    _checkActive();
    _checkTimeout();

    try {
      // Commit nested transactions first
      for (final nested in _nestedTransactions) {
        if (nested.isActive) {
          await nested.commit(committer);
        }
      }

      // Apply changes
      if (_parent == null) {
        // Root transaction - apply to storage
        await _executeWithRetry(() => committer(_changes));
      } else {
        // Nested transaction - merge changes to parent
        _parent!._changes.addAll(_changes);
      }

      _isCommitted = true;
      logger.info('Transaction $id committed successfully');
    } catch (e) {
      logger.error('Failed to commit transaction $id', error: e);
      rethrow;
    }
  }

  /// Rollback the transaction
  Future<void> rollback() async {
    if (_isRolledBack) return;

    try {
      // Rollback nested transactions
      for (final nested in _nestedTransactions) {
        if (nested.isActive) {
          await nested.rollback();
        }
      }

      _changes.clear();
      _savepoints.clear();
      _isRolledBack = true;

      logger.info('Transaction $id rolled back');
    } catch (e) {
      logger.error('Error during rollback of transaction $id', error: e);
      rethrow;
    }
  }

  /// Execute with retry logic
  Future<T> _executeWithRetry<T>(Future<T> Function() operation) async {
    while (_retryCount < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        _retryCount++;

        if (_retryCount >= maxRetries) {
          logger.error(
            'Transaction $id failed after $maxRetries retries',
            error: e,
          );
          rethrow;
        }

        logger.warning(
          'Transaction $id retry $_retryCount/$maxRetries after error',
          metadata: {'error': e.toString()},
        );

        // Exponential backoff with jitter
        final delay = retryDelay * pow(2, _retryCount - 1);
        final jitter = Random().nextInt(100);
        await Future.delayed(delay + Duration(milliseconds: jitter));
      }
    }

    throw StateError('Retry logic failed unexpectedly');
  }

  /// Check if transaction is active
  void _checkActive() {
    if (!isActive) {
      throw StateError('Transaction $id is not active');
    }
  }

  /// Check if transaction has timed out
  void _checkTimeout() {
    if (hasTimedOut) {
      throw TimeoutException('Transaction $id has timed out', timeout);
    }
  }

  /// Check if transaction is read-only
  void _checkReadOnly() {
    if (isReadOnly) {
      throw StateError('Cannot modify data in read-only transaction $id');
    }
  }

  /// Get transaction statistics
  Map<String, dynamic> getStats() {
    return {
      'id': id,
      'type': type.toString(),
      'isolationLevel': isolationLevel.toString(),
      'changes': _changes.length,
      'savepoints': _savepoints.length,
      'nestedTransactions': _nestedTransactions.length,
      'retryCount': _retryCount,
      'isActive': isActive,
      'duration':
          _startTime != null
              ? DateTime.now().difference(_startTime!).inMilliseconds
              : 0,
    };
  }
}

/// Transaction manager for enhanced transactions
class EnhancedTransactionManager {
  final Map<String, EnhancedTransaction> _activeTransactions = {};
  int _transactionCounter = 0;

  /// Begin a new transaction
  Future<EnhancedTransaction> begin({
    TransactionType type = TransactionType.readWrite,
    IsolationLevel isolationLevel = IsolationLevel.readCommitted,
    Duration? timeout,
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 100),
  }) async {
    _transactionCounter++;
    final id =
        'txn-$_transactionCounter-${DateTime.now().millisecondsSinceEpoch}';

    final transaction = EnhancedTransaction(
      id: id,
      type: type,
      isolationLevel: isolationLevel,
      timeout: timeout,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
    );

    _activeTransactions[id] = transaction;
    logger.info(
      'Started transaction $id',
      metadata: {
        'type': type.toString(),
        'isolationLevel': isolationLevel.toString(),
      },
    );

    return transaction;
  }

  /// Begin a read-only transaction
  Future<EnhancedTransaction> beginReadOnly({
    IsolationLevel isolationLevel = IsolationLevel.readCommitted,
    Duration? timeout,
  }) {
    return begin(
      type: TransactionType.readOnly,
      isolationLevel: isolationLevel,
      timeout: timeout,
    );
  }

  /// Execute a function within a transaction with automatic retry
  Future<T> withTransaction<T>(
    Future<T> Function(EnhancedTransaction) operation, {
    TransactionType type = TransactionType.readWrite,
    IsolationLevel isolationLevel = IsolationLevel.readCommitted,
    Duration? timeout,
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 100),
  }) async {
    int attempts = 0;
    Exception? lastException;

    while (attempts < maxRetries) {
      final transaction = await begin(
        type: type,
        isolationLevel: isolationLevel,
        timeout: timeout,
        maxRetries: maxRetries,
        retryDelay: retryDelay,
      );

      try {
        final result = await operation(transaction);
        // Commit would be called here in real implementation
        _activeTransactions.remove(transaction.id);
        return result;
      } catch (e) {
        await transaction.rollback();
        _activeTransactions.remove(transaction.id);
        lastException = e as Exception;
        attempts++;

        if (attempts >= maxRetries) {
          throw lastException;
        }

        // Exponential backoff with jitter
        final delay = retryDelay * pow(2, attempts - 1);
        final jitter = Random().nextInt(100);
        await Future.delayed(delay + Duration(milliseconds: jitter));
      }
    }

    throw lastException ??
        Exception('Transaction failed after $maxRetries attempts');
  }

  /// Get active transaction count
  int get activeTransactionCount => _activeTransactions.length;

  /// Get all active transactions
  List<EnhancedTransaction> get activeTransactions =>
      _activeTransactions.values.toList();

  /// Close all active transactions
  Future<void> closeAll() async {
    for (final transaction in _activeTransactions.values) {
      if (transaction.isActive) {
        await transaction.rollback();
      }
    }
    _activeTransactions.clear();
  }
}
