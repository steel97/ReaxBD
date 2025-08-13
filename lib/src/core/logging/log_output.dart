import 'dart:io';
import 'log_level.dart';

/// Base class for log outputs
abstract class LogOutput {
  Future<void> write(LogLevel level, String message, {Map<String, dynamic>? metadata});
  Future<void> close() async {}
}

/// Console output for logging
class ConsoleLogOutput extends LogOutput {
  final bool useColors;
  
  ConsoleLogOutput({this.useColors = true});

  @override
  Future<void> write(LogLevel level, String message, {Map<String, dynamic>? metadata}) async {
    final timestamp = DateTime.now().toIso8601String();
    final prefix = _getPrefix(level);
    final color = useColors ? _getColor(level) : '';
    final reset = useColors ? '\x1B[0m' : '';
    
    final logMessage = '$color[$timestamp] $prefix: $message$reset';
    
    if (metadata != null && metadata.isNotEmpty) {
      print('$logMessage $metadata');
    } else {
      print(logMessage);
    }
  }

  String _getPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.none:
        return '';
    }
  }

  String _getColor(LogLevel level) {
    if (!stdout.supportsAnsiEscapes) return '';
    
    switch (level) {
      case LogLevel.error:
        return '\x1B[31m'; // Red
      case LogLevel.warning:
        return '\x1B[33m'; // Yellow
      case LogLevel.info:
        return '\x1B[34m'; // Blue
      case LogLevel.debug:
        return '\x1B[90m'; // Gray
      case LogLevel.none:
        return '';
    }
  }
}

/// File output for logging
class FileLogOutput extends LogOutput {
  final String filePath;
  late final IOSink _sink;
  
  FileLogOutput(this.filePath) {
    final file = File(filePath);
    _sink = file.openWrite(mode: FileMode.append);
  }

  @override
  Future<void> write(LogLevel level, String message, {Map<String, dynamic>? metadata}) async {
    final timestamp = DateTime.now().toIso8601String();
    final prefix = _getPrefix(level);
    
    final logLine = StringBuffer('[$timestamp] $prefix: $message');
    
    if (metadata != null && metadata.isNotEmpty) {
      logLine.write(' | metadata: $metadata');
    }
    
    _sink.writeln(logLine.toString());
    await _sink.flush();
  }

  @override
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }

  String _getPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.none:
        return '';
    }
  }
}

/// Memory output for testing
class MemoryLogOutput extends LogOutput {
  final List<LogEntry> logs = [];

  @override
  Future<void> write(LogLevel level, String message, {Map<String, dynamic>? metadata}) async {
    logs.add(LogEntry(
      level: level,
      message: message,
      metadata: metadata,
      timestamp: DateTime.now(),
    ));
  }

  void clear() {
    logs.clear();
  }
}

class LogEntry {
  final LogLevel level;
  final String message;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.message,
    this.metadata,
    required this.timestamp,
  });
}