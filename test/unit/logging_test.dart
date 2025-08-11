import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';

void main() {
  group('Logging System Tests', () {
    late MemoryLogOutput memoryOutput;

    setUp(() {
      memoryOutput = MemoryLogOutput();
      logger.clearOutputs();
      logger.addOutput(memoryOutput);
      logger.setEnabled(true);
    });

    tearDown(() {
      memoryOutput.clear();
      logger.clearOutputs();
    });

    group('Log Levels', () {
      test('should respect log level settings', () async {
        logger.setLevel(LogLevel.warning);

        await logger.debug('Debug message');
        await logger.info('Info message');
        await logger.warning('Warning message');
        await logger.error('Error message');

        expect(memoryOutput.logs.length, equals(2));
        expect(memoryOutput.logs[0].level, equals(LogLevel.warning));
        expect(memoryOutput.logs[1].level, equals(LogLevel.error));
      });

      test('should log all levels when set to debug', () async {
        logger.setLevel(LogLevel.debug);

        await logger.debug('Debug');
        await logger.info('Info');
        await logger.warning('Warning');
        await logger.error('Error');

        expect(memoryOutput.logs.length, equals(4));
      });

      test('should log nothing when set to none', () async {
        logger.setLevel(LogLevel.none);

        await logger.debug('Debug');
        await logger.info('Info');
        await logger.warning('Warning');
        await logger.error('Error');

        expect(memoryOutput.logs.length, equals(0));
      });

      test('should handle enable/disable correctly', () async {
        logger.setLevel(LogLevel.debug);
        
        await logger.info('Message 1');
        logger.setEnabled(false);
        await logger.info('Message 2');
        logger.setEnabled(true);
        await logger.info('Message 3');

        expect(memoryOutput.logs.length, equals(2));
        expect(memoryOutput.logs[0].message, equals('Message 1'));
        expect(memoryOutput.logs[1].message, equals('Message 3'));
      });
    });

    group('Log Metadata', () {
      test('should include metadata in logs', () async {
        logger.setLevel(LogLevel.debug);

        await logger.info('User action', metadata: {
          'userId': 123,
          'action': 'login',
          'timestamp': '2025-01-01',
        });

        expect(memoryOutput.logs.length, equals(1));
        expect(memoryOutput.logs[0].metadata, isNotNull);
        expect(memoryOutput.logs[0].metadata!['userId'], equals(123));
        expect(memoryOutput.logs[0].metadata!['action'], equals('login'));
      });

      test('should include error and stacktrace in metadata', () async {
        logger.setLevel(LogLevel.error);

        final error = Exception('Test exception');
        final stackTrace = StackTrace.current;

        await logger.error('Operation failed', 
          error: error, 
          stackTrace: stackTrace
        );

        expect(memoryOutput.logs.length, equals(1));
        expect(memoryOutput.logs[0].metadata, isNotNull);
        expect(memoryOutput.logs[0].metadata!['error'], contains('Test exception'));
        expect(memoryOutput.logs[0].metadata!['stackTrace'], isNotNull);
      });
    });

    group('Multiple Outputs', () {
      test('should write to multiple outputs', () async {
        final secondMemoryOutput = MemoryLogOutput();
        logger.addOutput(secondMemoryOutput);
        logger.setLevel(LogLevel.info);

        await logger.info('Test message');

        expect(memoryOutput.logs.length, equals(1));
        expect(secondMemoryOutput.logs.length, equals(1));
        expect(memoryOutput.logs[0].message, equals('Test message'));
        expect(secondMemoryOutput.logs[0].message, equals('Test message'));
      });

      test('should handle output removal', () async {
        final secondMemoryOutput = MemoryLogOutput();
        logger.addOutput(secondMemoryOutput);
        logger.setLevel(LogLevel.info);

        await logger.info('Message 1');
        logger.removeOutput(memoryOutput);
        await logger.info('Message 2');

        expect(memoryOutput.logs.length, equals(1));
        expect(secondMemoryOutput.logs.length, equals(2));
      });
    });

    group('File Output', () {
      late String tempFilePath;
      late FileLogOutput fileOutput;

      setUp(() {
        tempFilePath = 'test/temp_log_${DateTime.now().millisecondsSinceEpoch}.log';
        fileOutput = FileLogOutput(tempFilePath);
        logger.addOutput(fileOutput);
      });

      tearDown(() async {
        await fileOutput.close();
        final file = File(tempFilePath);
        if (await file.exists()) {
          await file.delete();
        }
      });

      test('should write logs to file', () async {
        logger.setLevel(LogLevel.info);

        await logger.info('File log test');
        await logger.error('Error in file');
        
        await fileOutput.close();

        final file = File(tempFilePath);
        expect(await file.exists(), isTrue);
        
        final contents = await file.readAsString();
        expect(contents, contains('INFO: File log test'));
        expect(contents, contains('ERROR: Error in file'));
      });

      test('should append to existing file', () async {
        logger.setLevel(LogLevel.info);

        await logger.info('First message');
        await fileOutput.close();

        // Create new output for same file
        final newFileOutput = FileLogOutput(tempFilePath);
        logger.clearOutputs();
        logger.addOutput(newFileOutput);

        await logger.info('Second message');
        await newFileOutput.close();

        final file = File(tempFilePath);
        final contents = await file.readAsString();
        expect(contents, contains('First message'));
        expect(contents, contains('Second message'));
      });
    });

    group('Console Output', () {
      test('should create console output with colors', () {
        final consoleOutput = ConsoleLogOutput(useColors: true);
        expect(consoleOutput.useColors, isTrue);
      });

      test('should create console output without colors', () {
        final consoleOutput = ConsoleLogOutput(useColors: false);
        expect(consoleOutput.useColors, isFalse);
      });
    });

    group('Configuration', () {
      test('should configure logger with all options', () async {
        final customOutput = MemoryLogOutput();
        
        logger.configure(
          level: LogLevel.error,
          outputs: [customOutput],
          enabled: true,
        );

        await logger.debug('Debug');
        await logger.info('Info');
        await logger.warning('Warning');
        await logger.error('Error');

        expect(customOutput.logs.length, equals(1));
        expect(customOutput.logs[0].level, equals(LogLevel.error));
      });
    });

    group('Log Level Helpers', () {
      test('should correctly determine if level should log', () {
        expect(LogLevel.error.shouldLog(LogLevel.error), isTrue);
        expect(LogLevel.error.shouldLog(LogLevel.warning), isFalse);
        expect(LogLevel.error.shouldLog(LogLevel.info), isFalse);
        expect(LogLevel.error.shouldLog(LogLevel.debug), isFalse);

        expect(LogLevel.warning.shouldLog(LogLevel.error), isTrue);
        expect(LogLevel.warning.shouldLog(LogLevel.warning), isTrue);
        expect(LogLevel.warning.shouldLog(LogLevel.info), isFalse);
        expect(LogLevel.warning.shouldLog(LogLevel.debug), isFalse);

        expect(LogLevel.info.shouldLog(LogLevel.error), isTrue);
        expect(LogLevel.info.shouldLog(LogLevel.warning), isTrue);
        expect(LogLevel.info.shouldLog(LogLevel.info), isTrue);
        expect(LogLevel.info.shouldLog(LogLevel.debug), isFalse);

        expect(LogLevel.debug.shouldLog(LogLevel.error), isTrue);
        expect(LogLevel.debug.shouldLog(LogLevel.warning), isTrue);
        expect(LogLevel.debug.shouldLog(LogLevel.info), isTrue);
        expect(LogLevel.debug.shouldLog(LogLevel.debug), isTrue);
      });
    });

    group('Integration with ReaxDB', () {
      test('should log database operations', () async {
        logger.setLevel(LogLevel.debug);
        
        final testPath = 'test/logging_integration_db';
        
        // Clean up before test
        final dir = Directory(testPath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }

        final db = await ReaxDB.open(testPath);
        
        // Perform operations that should trigger logging
        await db.put('test_key', 'test_value');
        await db.get('test_key');
        
        await db.close();
        
        // Clean up after test
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }

        // Check that logs were created (at least for warnings/errors if any)
        // The exact number depends on internal implementation
        expect(memoryOutput.logs, isNotEmpty);
      });
    });
  });
}