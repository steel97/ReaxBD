import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;

/// Write-Ahead Log entry types
enum WALEntryType { put, delete, checkpoint }

/// Write-Ahead Log entry
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
  
  /// Serializes entry to bytes
  Uint8List toBytes() {
    final keyBytes = Uint8List.fromList(key);
    final valueBytes = value ?? Uint8List(0);
    final timestampBytes = _int64ToBytes(timestamp.millisecondsSinceEpoch);
    final sequenceBytes = _int64ToBytes(sequenceNumber);
    
    final buffer = BytesBuilder();
    
    // Entry type (1 byte)
    buffer.addByte(type.index);
    
    // Sequence number (8 bytes)
    buffer.add(sequenceBytes);
    
    // Timestamp (8 bytes)
    buffer.add(timestampBytes);
    
    // Key length (4 bytes)
    buffer.add(_int32ToBytes(keyBytes.length));
    
    // Key
    buffer.add(keyBytes);
    
    // Value length (4 bytes)
    buffer.add(_int32ToBytes(valueBytes.length));
    
    // Value
    buffer.add(valueBytes);
    
    return buffer.toBytes();
  }
  
  /// Deserializes entry from bytes
  static WALEntry fromBytes(Uint8List bytes) {
    int offset = 0;
    
    // Entry type
    final type = WALEntryType.values[bytes[offset]];
    offset += 1;
    
    // Sequence number
    final sequenceNumber = _bytesToInt64(bytes.sublist(offset, offset + 8));
    offset += 8;
    
    // Timestamp
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      _bytesToInt64(bytes.sublist(offset, offset + 8))
    );
    offset += 8;
    
    // Key length
    final keyLength = _bytesToInt32(bytes.sublist(offset, offset + 4));
    offset += 4;
    
    // Key
    final key = bytes.sublist(offset, offset + keyLength);
    offset += keyLength;
    
    // Value length
    final valueLength = _bytesToInt32(bytes.sublist(offset, offset + 4));
    offset += 4;
    
    // Value
    final value = valueLength > 0 ? bytes.sublist(offset, offset + valueLength) : null;
    
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

/// Write-Ahead Log for durability and crash recovery
class WriteAheadLog {
  final String _path;
  final int _maxFileSize;
  final List<File> _logFiles = [];
  File? _currentLogFile;
  IOSink? _currentSink;
  int _currentSequenceNumber = 0;
  int _currentFileSize = 0;
  
  static const int _defaultMaxFileSize = 64 * 1024 * 1024; // 64MB
  
  WriteAheadLog._({
    required String path,
    int maxFileSize = _defaultMaxFileSize,
  })  : _path = path,
        _maxFileSize = maxFileSize;
  
  /// Creates a new Write-Ahead Log
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
  
  /// Appends a put operation to the log
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
  
  /// Appends a delete operation (tombstone) to the log
  Future<void> appendTombstone(List<int> key) async {
    final entry = WALEntry(
      type: WALEntryType.delete,
      key: key,
      value: null,
      timestamp: DateTime.now(),
      sequenceNumber: _currentSequenceNumber++,
    );
    
    await _writeEntry(entry);
  }
  
  /// Appends a checkpoint marker to the log
  Future<void> checkpoint() async {
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
  
  /// Recovers operations from the log
  Future<List<WALEntry>> recover() async {
    final entries = <WALEntry>[];
    
    // Sort log files by name (timestamp)
    _logFiles.sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
    
    for (final logFile in _logFiles) {
      if (logFile == _currentLogFile) continue; // Skip current active file
      
      final fileEntries = await _readLogFile(logFile);
      entries.addAll(fileEntries);
    }
    
    return entries;
  }
  
  /// Truncates log files after successful recovery
  Future<void> truncate() async {
    for (final logFile in _logFiles.toList()) {
      if (logFile != _currentLogFile) {
        await logFile.delete();
        _logFiles.remove(logFile);
      }
    }
  }
  
  /// Closes the Write-Ahead Log
  Future<void> close() async {
    await _currentSink?.close();
    _currentSink = null;
  }
  
  /// Gets current sequence number
  int get currentSequenceNumber => _currentSequenceNumber;
  
  /// Gets log file count
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
        
        // Find highest sequence number from existing files
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
    final entryBytes = entry.toBytes();
    final lengthBytes = WALEntry._int32ToBytes(entryBytes.length);
    
    // Write entry length first, then entry data
    _currentSink!.add(lengthBytes);
    _currentSink!.add(entryBytes);
    await _currentSink!.flush();
    
    _currentFileSize += lengthBytes.length + entryBytes.length;
    
    // Rotate log file if it gets too large
    if (_currentFileSize >= _maxFileSize) {
      await _rotateLogFile();
    }
  }
  
  Future<void> _rotateLogFile() async {
    await _currentSink?.close();
    await _createNewLogFile();
  }
  
  Future<List<WALEntry>> _readLogFile(File logFile) async {
    final entries = <WALEntry>[];
    
    if (!await logFile.exists()) return entries;
    
    final bytes = await logFile.readAsBytes();
    int offset = 0;
    
    while (offset < bytes.length) {
      try {
        // Read entry length
        if (offset + 4 > bytes.length) break;
        final entryLength = WALEntry._bytesToInt32(bytes.sublist(offset, offset + 4));
        offset += 4;
        
        // Read entry data
        if (offset + entryLength > bytes.length) break;
        final entryBytes = bytes.sublist(offset, offset + entryLength);
        offset += entryLength;
        
        final entry = WALEntry.fromBytes(entryBytes);
        entries.add(entry);
      } catch (e) {
        // Skip corrupted entries
        break;
      }
    }
    
    return entries;
  }
}