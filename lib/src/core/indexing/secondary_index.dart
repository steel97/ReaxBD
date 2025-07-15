import 'dart:typed_data';
import '../storage/btree.dart';
import '../storage/hybrid_storage_engine.dart';

/// Secondary index for fast field-based queries
class SecondaryIndex {
  final String collection;
  final String fieldName;
  final BTree _indexTree;

  SecondaryIndex({
    required this.collection,
    required this.fieldName,
    required BTree indexTree,
    required HybridStorageEngine storageEngine,
  }) : _indexTree = indexTree;

  /// Creates a new secondary index
  static Future<SecondaryIndex> create({
    required String collection,
    required String fieldName,
    required String basePath,
    required HybridStorageEngine storageEngine,
  }) async {
    final indexPath = '$basePath/indexes/${collection}_$fieldName';
    final indexTree = await BTree.create(basePath: indexPath);

    return SecondaryIndex(
      collection: collection,
      fieldName: fieldName,
      indexTree: indexTree,
      storageEngine: storageEngine,
    );
  }

  /// Adds an entry to the index
  Future<void> addEntry(dynamic fieldValue, String documentId) async {
    final indexKey = _createIndexKey(fieldValue);

    // Get existing entries for this field value
    final existingBytes = await _indexTree.get(indexKey);
    final documentIds = <String>[];

    if (existingBytes != null) {
      // Parse existing document IDs
      documentIds.addAll(_parseDocumentIds(existingBytes));
    }

    // Add new document ID if not already present
    if (!documentIds.contains(documentId)) {
      documentIds.add(documentId);

      // Store updated list
      final updatedBytes = _serializeDocumentIds(documentIds);
      await _indexTree.put(indexKey, updatedBytes);
    }
  }

  /// Removes an entry from the index
  Future<void> removeEntry(dynamic fieldValue, String documentId) async {
    final indexKey = _createIndexKey(fieldValue);
    final existingBytes = await _indexTree.get(indexKey);

    if (existingBytes == null) return;

    final documentIds = _parseDocumentIds(existingBytes);
    documentIds.remove(documentId);

    if (documentIds.isEmpty) {
      // Remove the index entry completely
      await _indexTree.delete(indexKey);
    } else {
      // Update with remaining document IDs
      final updatedBytes = _serializeDocumentIds(documentIds);
      await _indexTree.put(indexKey, updatedBytes);
    }
  }

  /// Updates an index entry when a document's field value changes
  Future<void> updateEntry(
    dynamic oldValue,
    dynamic newValue,
    String documentId,
  ) async {
    if (oldValue != newValue) {
      await removeEntry(oldValue, documentId);
      await addEntry(newValue, documentId);
    }
  }

  /// Finds all documents with the given field value
  Future<List<String>> findEquals(dynamic value) async {
    final indexKey = _createIndexKey(value);
    final bytes = await _indexTree.get(indexKey);

    if (bytes == null) return [];
    return _parseDocumentIds(bytes);
  }

  /// Finds all documents with field values in a range
  Future<List<String>> findRange(
    dynamic startValue,
    dynamic endValue, {
    bool includeStart = true,
    bool includeEnd = true,
  }) async {
    final startKey = startValue != null ? _createIndexKey(startValue) : null;
    final endKey = endValue != null ? _createIndexKey(endValue) : null;

    final documentIds = <String>{};

    // Get all entries in range from B+Tree
    await _indexTree.scan(
      startKey: startKey,
      endKey: endKey,
      callback: (key, value) {
        final docs = _parseDocumentIds(value);
        documentIds.addAll(docs);

        return true; // Continue scanning
      },
    );

    return documentIds.toList();
  }

  /// Creates an index key from a field value
  List<int> _createIndexKey(dynamic value) {
    // Convert different types to bytes
    if (value == null) {
      return [0]; // Null marker
    } else if (value is String) {
      return [1, ...value.codeUnits];
    } else if (value is int) {
      return [2, ..._intToBytes(value)];
    } else if (value is double) {
      return [3, ..._doubleToBytes(value)];
    } else if (value is bool) {
      return [4, value ? 1 : 0];
    } else {
      // Fallback to string representation
      return [255, ...value.toString().codeUnits];
    }
  }

  List<int> _intToBytes(int value) {
    final bytes = Uint8List(8);
    bytes.buffer.asByteData().setInt64(0, value, Endian.big);
    return bytes;
  }

  List<int> _doubleToBytes(double value) {
    final bytes = Uint8List(8);
    bytes.buffer.asByteData().setFloat64(0, value, Endian.big);
    return bytes;
  }

  /// Serializes a list of document IDs
  Uint8List _serializeDocumentIds(List<String> documentIds) {
    final buffer = BytesBuilder();

    // Write count
    buffer.add(_intToBytes(documentIds.length).sublist(4)); // 4 bytes for count

    // Write each document ID
    for (final id in documentIds) {
      final idBytes = id.codeUnits;
      buffer.add(_intToBytes(idBytes.length).sublist(4)); // 4 bytes for length
      buffer.add(idBytes);
    }

    return buffer.toBytes();
  }

  /// Parses document IDs from bytes
  List<String> _parseDocumentIds(Uint8List bytes) {
    final documentIds = <String>[];
    int offset = 0;

    // Read count
    final count = bytes.buffer.asByteData().getUint32(offset, Endian.big);
    offset += 4;

    // Read each document ID
    for (int i = 0; i < count; i++) {
      final length = bytes.buffer.asByteData().getUint32(offset, Endian.big);
      offset += 4;

      final idBytes = bytes.sublist(offset, offset + length);
      documentIds.add(String.fromCharCodes(idBytes));
      offset += length;
    }

    return documentIds;
  }

  /// Rebuilds the entire index from scratch
  Future<void> rebuild() async {
    // Clear existing index
    await _indexTree.clear();

    // For now, we'll rely on documents being added individually
    // In a real implementation, we would scan all keys with the collection prefix
    // from the storage engine and rebuild the index
  }

  /// Closes the index
  Future<void> close() async {
    await _indexTree.close();
  }
}
