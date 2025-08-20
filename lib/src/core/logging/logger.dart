import 'log_level.dart';
import 'log_output.dart';

/// ReaxDB Logger with configurable outputs and levels
class ReaxLogger {
  static ReaxLogger? _instance;
  static ReaxLogger get instance => _instance ??= ReaxLogger._();

  LogLevel _level = LogLevel.info;
  final List<LogOutput> _outputs = [];
  bool _enabled = true;

  ReaxLogger._() {
    // Default to console output in debug mode
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      _outputs.add(ConsoleLogOutput());
    }
  }

  /// Configure the logger
  void configure({LogLevel? level, List<LogOutput>? outputs, bool? enabled}) {
    if (level != null) _level = level;
    if (outputs != null) {
      _outputs.clear();
      _outputs.addAll(outputs);
    }
    if (enabled != null) _enabled = enabled;
  }

  /// Add a log output
  void addOutput(LogOutput output) {
    _outputs.add(output);
  }

  /// Remove a log output
  void removeOutput(LogOutput output) {
    _outputs.remove(output);
  }

  /// Clear all outputs
  void clearOutputs() {
    _outputs.clear();
  }

  /// Set log level
  void setLevel(LogLevel level) {
    _level = level;
  }

  /// Enable/disable logging
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Log an error message
  Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) async {
    await _log(
      LogLevel.error,
      message,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Log a warning message
  Future<void> warning(String message, {Map<String, dynamic>? metadata}) async {
    await _log(LogLevel.warning, message, metadata: metadata);
  }

  /// Log an info message
  Future<void> info(String message, {Map<String, dynamic>? metadata}) async {
    await _log(LogLevel.info, message, metadata: metadata);
  }

  /// Log a debug message
  Future<void> debug(String message, {Map<String, dynamic>? metadata}) async {
    await _log(LogLevel.debug, message, metadata: metadata);
  }

  /// Internal log method
  Future<void> _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_enabled || !_level.shouldLog(level)) {
      return;
    }

    final fullMetadata = <String, dynamic>{
      if (metadata != null) ...metadata,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    };

    for (final output in _outputs) {
      try {
        await output.write(
          level,
          message,
          metadata: fullMetadata.isEmpty ? null : fullMetadata,
        );
      } catch (e) {
        // Silently ignore output errors to prevent cascading failures
      }
    }
  }

  /// Close all outputs
  Future<void> close() async {
    for (final output in _outputs) {
      await output.close();
    }
  }
}

/// Global logger instance
final logger = ReaxLogger.instance;
