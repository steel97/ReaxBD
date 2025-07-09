import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// Sorted String Table for persistent storage
class SSTable {
  final String _filePath;
  final int _level;
  final DateTime _createdAt;
  final Map<String, int> _index = {}; // Key -> file offset
  RandomAccessFile? _file;
  
  SSTable._({
    required String filePath,
    required int level,
    required DateTime createdAt,
  })  : _filePath = filePath,
        _level = level,
        _createdAt = createdAt;

  /// Creates a new SSTable from entries
  static Future<SSTable> create({
    required String basePath,
    required int level,
    required Map<List<int>, Uint8List> entries,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'level_${level}_$timestamp.sst';
    final filePath = path.join(basePath, fileName);
    
    final sstable = SSTable._(
      filePath: filePath,
      level: level,
      createdAt: DateTime.now(),
    );
    
    await sstable._writeEntries(entries);
    return sstable;
  }

  /// Loads an existing SSTable
  static Future<SSTable> load(String filePath) async {
    final fileName = path.basename(filePath);
    final parts = fileName.split('_');
    
    final level = int.parse(parts[1]);
    final timestamp = int.parse(parts[2].replaceAll('.sst', ''));
    final createdAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    
    final sstable = SSTable._(
      filePath: filePath,
      level: level,
      createdAt: createdAt,
    );
    
    await sstable._loadIndex();
    return sstable;
  }

  /// Gets a value by key
  Future<Uint8List?> get(List<int> key) async {
    final keyString = String.fromCharCodes(key);
    final offset = _index[keyString];
    if (offset == null) return null;
    
    await _ensureFileOpen();
    await _file!.setPosition(offset);
    
    // Read key length
    final keyLengthBytes = await _file!.read(4);
    final keyLength = ByteData.sublistView(Uint8List.fromList(keyLengthBytes))
        .getUint32(0, Endian.little);
    
    // Read key (skip it)
    await _file!.read(keyLength);
    
    // Read value length
    final valueLengthBytes = await _file!.read(4);
    final valueLength = ByteData.sublistView(Uint8List.fromList(valueLengthBytes))
        .getUint32(0, Endian.little);
    
    // Read value
    final valueBytes = await _file!.read(valueLength);
    return Uint8List.fromList(valueBytes);
  }

  /// Gets all entries
  Future<Map<List<int>, Uint8List>> getAllEntries() async {
    final result = <List<int>, Uint8List>{};
    
    for (final keyString in _index.keys) {
      final key = keyString.codeUnits;
      final value = await get(key);
      if (value != null && value.isNotEmpty) {
        result[key] = value;
      }
    }
    
    return result;
  }

  /// Gets entry count
  Future<int> getEntryCount() async {
    return _index.length;
  }

  /// Closes the SSTable
  Future<void> close() async {
    await _file?.close();
    _file = null;
  }

  /// Deletes the SSTable file
  Future<void> delete() async {
    await close();
    final file = File(_filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  DateTime get createdAt => _createdAt;
  int get level => _level;
  String get filePath => _filePath;

  Future<void> _writeEntries(Map<List<int>, Uint8List> entries) async {
    final file = File(_filePath);
    final sink = file.openWrite();
    
    try {
      // Sort entries by key
      final sortedEntries = entries.entries.toList();
      sortedEntries.sort((a, b) {
        final keyA = String.fromCharCodes(a.key);
        final keyB = String.fromCharCodes(b.key);
        return keyA.compareTo(keyB);
      });
      
      int offset = 0;
      
      // Write entries
      for (final entry in sortedEntries) {
        final keyBytes = Uint8List.fromList(entry.key);
        final valueBytes = entry.value;
        final keyString = String.fromCharCodes(entry.key);
        
        _index[keyString] = offset;
        
        // Write key length (4 bytes)
        final keyLengthBytes = ByteData(4);
        keyLengthBytes.setUint32(0, keyBytes.length, Endian.little);
        sink.add(keyLengthBytes.buffer.asUint8List());
        offset += 4;
        
        // Write key
        sink.add(keyBytes);
        offset += keyBytes.length;
        
        // Write value length (4 bytes)
        final valueLengthBytes = ByteData(4);
        valueLengthBytes.setUint32(0, valueBytes.length, Endian.little);
        sink.add(valueLengthBytes.buffer.asUint8List());
        offset += 4;
        
        // Write value
        sink.add(valueBytes);
        offset += valueBytes.length;
      }
      
      // Write index at the end
      await _writeIndex(sink);
      
    } finally {
      await sink.close();
    }
  }

  Future<void> _writeIndex(IOSink sink) async {
    final indexData = <String, dynamic>{};
    for (final entry in _index.entries) {
      indexData[entry.key] = entry.value;
    }
    
    final indexJson = jsonEncode(indexData);
    final indexBytes = utf8.encode(indexJson);
    
    // Write index length
    final indexLengthBytes = ByteData(4);
    indexLengthBytes.setUint32(0, indexBytes.length, Endian.little);
    sink.add(indexLengthBytes.buffer.asUint8List());
    
    // Write index
    sink.add(indexBytes);
  }

  Future<void> _loadIndex() async {
    final file = File(_filePath);
    if (!await file.exists()) return;
    
    final fileSize = await file.length();
    if (fileSize < 4) {
      // File is too small to be valid
      return;
    }
    
    final randomAccessFile = await file.open();
    
    try {
      // Read index length from end of file
      await randomAccessFile.setPosition(fileSize - 4);
      final indexLengthBytes = await randomAccessFile.read(4);
      if (indexLengthBytes.length != 4) {
        // Corrupted file
        return;
      }
      
      final indexLength = ByteData.sublistView(Uint8List.fromList(indexLengthBytes))
          .getUint32(0, Endian.little);
      
      // Validate index length
      if (indexLength <= 0 || indexLength > fileSize - 4) {
        // Invalid index length
        return;
      }
      
      // Read index
      await randomAccessFile.setPosition(fileSize - 4 - indexLength);
      final indexBytes = await randomAccessFile.read(indexLength);
      if (indexBytes.length != indexLength) {
        // Could not read full index
        return;
      }
      
      try {
        final indexJson = utf8.decode(indexBytes);
        final indexData = jsonDecode(indexJson) as Map<String, dynamic>;
        
        // Populate index
        for (final entry in indexData.entries) {
          _index[entry.key] = entry.value as int;
        }
      } catch (e) {
        // Invalid JSON or UTF-8 - corrupted index
        return;
      }
      
    } catch (e) {
      // Any other error - treat as corrupted file
      return;
    } finally {
      await randomAccessFile.close();
    }
  }

  Future<void> _ensureFileOpen() async {
    if (_file == null) {
      final file = File(_filePath);
      _file = await file.open();
    }
  }

  @override
  String toString() {
    return 'SSTable(level: $_level, entries: ${_index.length}, file: ${path.basename(_filePath)})';
  }
}