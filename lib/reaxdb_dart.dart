/// ReaxDB - High-performance NoSQL database for Dart
library;

// Domain exports
export 'src/domain/entities/database_entity.dart';

// Core exports
export 'src/core/storage/hybrid_storage_engine.dart';
export 'src/core/cache/multi_level_cache.dart';
export 'src/core/transactions/transaction_manager.dart' hide Transaction, IsolationLevel;
export 'src/core/encryption/encryption_type.dart';
export 'src/core/encryption/encryption_engine.dart';

// Logging exports
export 'src/core/logging/logger.dart';
export 'src/core/logging/log_level.dart';
export 'src/core/logging/log_output.dart';

// Streams exports
export 'src/core/streams/reactive_stream.dart';

// Query exports
export 'src/core/query/query_builder.dart';
export 'src/core/query/aggregation.dart';

// Enhanced transaction exports
export 'src/core/transactions/enhanced_transaction.dart';

// Main ReaxDB class
export 'src/reaxdb.dart';

// Simple API for easy adoption
export 'src/simple_api.dart';
