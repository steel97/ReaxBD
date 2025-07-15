/// Entyties
class TransactionEntity {
  final String id;
  final DateTime startTime;
  final TransactionStatus status;
  final Map<String, dynamic> readSet;
  final Map<String, dynamic> writeSet;
  final int isolationLevel;

  const TransactionEntity({
    required this.id,
    required this.startTime,
    required this.status,
    required this.readSet,
    required this.writeSet,
    required this.isolationLevel,
  });

  TransactionEntity copyWith({
    String? id,
    DateTime? startTime,
    TransactionStatus? status,
    Map<String, dynamic>? readSet,
    Map<String, dynamic>? writeSet,
    int? isolationLevel,
  }) {
    return TransactionEntity(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      status: status ?? this.status,
      readSet: readSet ?? this.readSet,
      writeSet: writeSet ?? this.writeSet,
      isolationLevel: isolationLevel ?? this.isolationLevel,
    );
  }

  @override
  String toString() {
    return 'Transaction(id: $id, status: $status, reads: ${readSet.length}, writes: ${writeSet.length})';
  }
}

/// Estados de una transacción
enum TransactionStatus { active, preparing, committed, aborted, rolledBack }

/// Niveles de aislamiento de transacciones
class IsolationLevel {
  static const int readUncommitted = 0;
  static const int readCommitted = 1;
  static const int repeatableRead = 2;
  static const int serializable = 3;
}

/// Log de operaciones de una transacción
class TransactionLog {
  final String transactionId;
  final List<TransactionOperation> operations;
  final DateTime timestamp;

  const TransactionLog({
    required this.transactionId,
    required this.operations,
    required this.timestamp,
  });
}

/// Operación dentro de una transacción
class TransactionOperation {
  final OperationType type;
  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final DateTime timestamp;

  const TransactionOperation({
    required this.type,
    required this.key,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'Operation($type: $key)';
  }
}

/// Tipos de operaciones en transacciones
enum OperationType { read, write, delete, create }

/// Conflicto entre transacciones
class TransactionConflict {
  final String transaction1Id;
  final String transaction2Id;
  final String conflictingKey;
  final ConflictType type;
  final DateTime detectedAt;

  const TransactionConflict({
    required this.transaction1Id,
    required this.transaction2Id,
    required this.conflictingKey,
    required this.type,
    required this.detectedAt,
  });

  @override
  String toString() {
    return 'Conflict($type on $conflictingKey between $transaction1Id and $transaction2Id)';
  }
}

/// Tipos de conflictos entre transacciones
enum ConflictType { writeWrite, readWrite, writeRead }

/// Punto de guardado dentro de una transacción
class Savepoint {
  final String id;
  final String transactionId;
  final DateTime createdAt;
  final Map<String, dynamic> state;

  const Savepoint({
    required this.id,
    required this.transactionId,
    required this.createdAt,
    required this.state,
  });

  @override
  String toString() {
    return 'Savepoint(id: $id, transaction: $transactionId)';
  }
}
