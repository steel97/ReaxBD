import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:path/path.dart' as path;

// WAL entry types
enum WALEntryType { put, delete, checkpoint }

// WAL entry
class WALEntry {
  final WALEntryType type;
  final List<int> key;
  final Uint8List? value;
  final DateTime timestamp;
  final int sequenceNumber;

  const WALEntry({
    required this.type,
    required this.key,
    this.value,
    required this.timestamp,
    required this.sequenceNumber,
  });

  // Serializes to bytes
  Uint8List toBytes() {
    final keyBytes = Uint8List.fromList(key);
    final valueBytes = value ?? Uint8List(0);
    final timestampBytes = _int64ToBytes(timestamp.millisecondsSinceEpoch);
    final sequenceBytes = _int64ToBytes(sequenceNumber);

    final buffer = BytesBuilder();

    buffer.addByte(type.index);

    buffer.add(sequenceBytes);

    buffer.add(timestampBytes);

    buffer.add(_int32ToBytes(keyBytes.length));

    buffer.add(keyBytes);

    buffer.add(_int32ToBytes(valueBytes.length));

    buffer.add(valueBytes);

    return buffer.toBytes();
  }

  // Deserializes from bytes
  static WALEntry fromBytes(Uint8List bytes) {
    int offset = 0;

    final type = WALEntryType.values[bytes[offset]];
    offset += 1;

    final sequenceNumber = _bytesToInt64(bytes.sublist(offset, offset + 8));
    offset += 8;

    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      _bytesToInt64(bytes.sublist(offset, offset + 8)),
    );
    offset += 8;

    final keyLength = _bytesToInt32(bytes.sublist(offset, offset + 4));
    offset += 4;

    final key = bytes.sublist(offset, offset + keyLength);
    offset += keyLength;

    final valueLength = _bytesToInt32(bytes.sublist(offset, offset + 4));
    offset += 4;

    final value =
        valueLength > 0 ? bytes.sublist(offset, offset + valueLength) : null;

    return WALEntry(
      type: type,
      key: key,
      value: value,
      timestamp: timestamp,
      sequenceNumber: sequenceNumber,
    );
  }

  static Uint8List _int32ToBytes(int value) {
    final bytes = ByteData(4);
    bytes.setUint32(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static Uint8List _int64ToBytes(int value) {
    final bytes = ByteData(8);
    bytes.setUint64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static int _bytesToInt32(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    return byteData.getUint32(0, Endian.little);
  }

  static int _bytesToInt64(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    return byteData.getUint64(0, Endian.little);
  }

  @override
  String toString() {
    return 'WALEntry(type: $type, key: ${String.fromCharCodes(key)}, seq: $sequenceNumber)';
  }
}

// Write-Ahead Log
class WriteAheadLog {
  final String _path;
  final int _maxFileSize;
  final List<File> _logFiles = [];
  File? _currentLogFile;
  IOSink? _currentSink;
  int _currentSequenceNumber = 0;
  int _currentFileSize = 0;

  final List<WALEntry> _pendingWrites = [];
  Timer? _flushTimer;
  bool _isFlushing = false;

  static const int _defaultMaxFileSize = 64 * 1024 * 1024;

  WriteAheadLog._({required String path, int maxFileSize = _defaultMaxFileSize})
    : _path = path,
      _maxFileSize = maxFileSize;

  // Creates WAL
  static Future<WriteAheadLog> create({
    required String basePath,
    int maxFileSize = _defaultMaxFileSize,
  }) async {
    final walPath = path.join(basePath, 'wal');
    final directory = Directory(walPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final wal = WriteAheadLog._(path: walPath, maxFileSize: maxFileSize);
    await wal._initialize();
    return wal;
  }

  // Appends put operation
  Future<void> append(List<int> key, Uint8List value) async {
    final entry = WALEntry(
      type: WALEntryType.put,
      key: key,
      value: value,
      timestamp: DateTime.now(),
      sequenceNumber: _currentSequenceNumber++,
    );

    await _writeEntry(entry);
  }

  // Appends delete operation
  Future<void> appendTombstone(List<int> key) async {
    final entry = WALEntry(
      type: WALEntryType.delete,
      key: key,
      value: null,
      timestamp: DateTime.now(),
      sequenceNumber: _currentSequenceNumber++,
    );

    await _writeEntry(entry);
    await _flushPendingWrites();
  }

  // Appends checkpoint
  Future<void> checkpoint() async {
    if (_pendingWrites.isNotEmpty) {
      await _flushPendingWrites();
    }

    final entry = WALEntry(
      type: WALEntryType.checkpoint,
      key: [],
      value: null,
      timestamp: DateTime.now(),
      sequenceNumber: _currentSequenceNumber++,
    );

    await _writeEntry(entry);
    await _rotateLogFile();
  }

  // Recovers operations
  Future<List<WALEntry>> recover() async {
    final entries = <WALEntry>[];

    _logFiles.sort(
      (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
    );

    for (final logFile in _logFiles) {
      final fileEntries = await _readLogFile(logFile);
      entries.addAll(fileEntries);
    }

    return entries;
  }

  // Truncates log files
  Future<void> truncate() async {
    for (final logFile in _logFiles.toList()) {
      if (logFile != _currentLogFile) {
        await logFile.delete();
        _logFiles.remove(logFile);
      }
    }
  }

  // Closes WAL
  Future<void> close() async {
    _flushTimer?.cancel();
    _flushTimer = null;

    while (_pendingWrites.isNotEmpty || _isFlushing) {
      if (!_isFlushing && _pendingWrites.isNotEmpty) {
        await _flushPendingWrites();
      } else if (_isFlushing) {
        await Future.delayed(Duration(milliseconds: 1));
      }
    }

    if (_currentSink != null) {
      try {
        await _currentSink!.close();
      } catch (e) {
        // Ignore close errors during shutdown
      }
      _currentSink = null;
    }
  }

  // Gets sequence number
  int get currentSequenceNumber => _currentSequenceNumber;

  // Gets file count
  int get logFileCount => _logFiles.length;

  Future<void> _initialize() async {
    await _loadExistingLogFiles();
    await _createNewLogFile();
  }

  Future<void> _loadExistingLogFiles() async {
    final directory = Directory(_path);
    if (!await directory.exists()) return;

    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.wal')) {
        _logFiles.add(entity);

        final entries = await _readLogFile(entity);
        for (final entry in entries) {
          if (entry.sequenceNumber >= _currentSequenceNumber) {
            _currentSequenceNumber = entry.sequenceNumber + 1;
          }
        }
      }
    }
  }

  Future<void> _createNewLogFile() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'wal_${timestamp.toString().padLeft(16, '0')}.wal';
    final filePath = path.join(_path, fileName);

    _currentLogFile = File(filePath);
    _logFiles.add(_currentLogFile!);
    _currentSink = _currentLogFile!.openWrite();
    _currentFileSize = 0;
  }

  Future<void> _writeEntry(WALEntry entry) async {
    _pendingWrites.add(entry);

    _flushTimer ??= Timer(
      Duration(milliseconds: 1),
      () => _flushPendingWrites(),
    );

    if (_pendingWrites.length >= 1000) {
      _flushPendingWrites();
    }
  }

  Future<void> _flushPendingWrites() async {
    if (_pendingWrites.isEmpty || _isFlushing) return;

    _isFlushing = true;
    _flushTimer?.cancel();
    _flushTimer = null;

    final entriesToFlush = List<WALEntry>.from(_pendingWrites);
    _pendingWrites.clear();

    try {
      final buffer = BytesBuilder();

      for (final entry in entriesToFlush) {
        final entryBytes = entry.toBytes();
        final lengthBytes = WALEntry._int32ToBytes(entryBytes.length);

        buffer.add(lengthBytes);
        buffer.add(entryBytes);

        _currentFileSize += lengthBytes.length + entryBytes.length;
      }

      final allBytes = buffer.toBytes();
      if (_currentSink != null) {
        _currentSink!.add(allBytes);
        await _currentSink!.flush();
      }

      if (_currentFileSize >= _maxFileSize) {
        await _rotateLogFile();
      }
    } finally {
      _isFlushing = false;

      if (_pendingWrites.isNotEmpty) {
        _flushTimer = Timer(
          Duration(milliseconds: 1),
          () => _flushPendingWrites(),
        );
      }
    }
  }

  Future<void> _rotateLogFile() async {
    if (_currentSink != null) {
      try {
        await _currentSink!.close();
      } catch (e) {
        // Ignore close errors during rotation
      }
      _currentSink = null;
    }
    await _createNewLogFile();
  }

  Future<List<WALEntry>> _readLogFile(File logFile) async {
    final entries = <WALEntry>[];

    if (!await logFile.exists()) return entries;

    final bytes = await logFile.readAsBytes();
    int offset = 0;

    while (offset < bytes.length) {
      try {
        if (offset + 4 > bytes.length) break;
        final entryLength = WALEntry._bytesToInt32(
          bytes.sublist(offset, offset + 4),
        );
        offset += 4;

        if (offset + entryLength > bytes.length) break;
        final entryBytes = bytes.sublist(offset, offset + entryLength);
        offset += entryLength;

        final entry = WALEntry.fromBytes(entryBytes);
        entries.add(entry);
      } catch (e) {
        break;
      }
    }

    return entries;
  }
}
