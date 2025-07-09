import 'dart:io';
import 'package:flutter/foundation.dart';

import 'secondary_index.dart';
import '../storage/hybrid_storage_engine.dart';

/// Manages all secondary indexes for the database
class IndexManager {
  final String _basePath;
  final HybridStorageEngine _storageEngine;
  final Map<String, SecondaryIndex> _indexes = {};
  
  IndexManager({
    required String basePath,
    required HybridStorageEngine storageEngine,
  }) : _basePath = basePath,
       _storageEngine = storageEngine;
  
  /// Creates a new index on a collection field
  Future<void> createIndex(String collection, String fieldName) async {
    final indexKey = '$collection.$fieldName';
    
    // Check if index already exists
    if (_indexes.containsKey(indexKey)) {
      throw StateError('Index already exists for $indexKey');
    }
    
    // Create index directory if needed
    final indexDir = Directory('$_basePath/indexes');
    if (!await indexDir.exists()) {
      await indexDir.create(recursive: true);
    }
    
    // Create the index
    final index = await SecondaryIndex.create(
      collection: collection,
      fieldName: fieldName,
      basePath: _basePath,
      storageEngine: _storageEngine,
    );
    
    _indexes[indexKey] = index;
    
    // TODO: In a production system, we would scan existing documents
    // and rebuild the index here. For now, new documents will be indexed
    // as they are inserted.
  }
  
  /// Drops an index
  Future<void> dropIndex(String collection, String fieldName) async {
    final indexKey = '$collection.$fieldName';
    final index = _indexes[indexKey];
    
    if (index == null) {
      throw StateError('Index does not exist for $indexKey');
    }
    
    // Close and remove index
    await index.close();
    _indexes.remove(indexKey);
    
    // Delete index files
    final indexPath = '$_basePath/indexes/${collection}_$fieldName';
    final indexDir = Directory(indexPath);
    if (await indexDir.exists()) {
      await indexDir.delete(recursive: true);
    }
  }
  
  /// Gets an index for a collection field
  SecondaryIndex? getIndex(String collection, String fieldName) {
    return _indexes['$collection.$fieldName'];
  }
  
  /// Lists all indexes
  List<String> listIndexes() {
    return _indexes.keys.toList();
  }
  
  /// Updates indexes when a document is inserted
  Future<void> onDocumentInsert(
    String collection,
    String documentId,
    Map<String, dynamic> document,
  ) async {
    // Update all indexes for this collection
    for (final entry in _indexes.entries) {
      if (entry.key.startsWith('$collection.')) {
        final fieldName = entry.key.split('.')[1];
        final fieldValue = document[fieldName];
        
        if (fieldValue != null) {
          await entry.value.addEntry(fieldValue, documentId);
        }
      }
    }
  }
  
  /// Updates indexes when a document is updated
  Future<void> onDocumentUpdate(
    String collection,
    String documentId,
    Map<String, dynamic> oldDocument,
    Map<String, dynamic> newDocument,
  ) async {
    // Update all indexes for this collection
    for (final entry in _indexes.entries) {
      if (entry.key.startsWith('$collection.')) {
        final fieldName = entry.key.split('.')[1];
        final oldValue = oldDocument[fieldName];
        final newValue = newDocument[fieldName];
        
        await entry.value.updateEntry(oldValue, newValue, documentId);
      }
    }
  }
  
  /// Updates indexes when a document is deleted
  Future<void> onDocumentDelete(
    String collection,
    String documentId,
    Map<String, dynamic> document,
  ) async {
    // Update all indexes for this collection
    for (final entry in _indexes.entries) {
      if (entry.key.startsWith('$collection.')) {
        final fieldName = entry.key.split('.')[1];
        final fieldValue = document[fieldName];
        
        if (fieldValue != null) {
          await entry.value.removeEntry(fieldValue, documentId);
        }
      }
    }
  }
  
  /// Loads existing indexes from disk
  Future<void> loadIndexes() async {
    final indexDir = Directory('$_basePath/indexes');
    if (!await indexDir.exists()) {
      return;
    }
    
    // List all index directories
    await for (final entity in indexDir.list()) {
      if (entity is Directory) {
        final dirName = entity.path.split('/').last;
        final parts = dirName.split('_');
        
        if (parts.length >= 2) {
          final collection = parts[0];
          final fieldName = parts.sublist(1).join('_');
          
          try {
            final index = await SecondaryIndex.create(
              collection: collection,
              fieldName: fieldName,
              basePath: _basePath,
              storageEngine: _storageEngine,
            );
            
            _indexes['$collection.$fieldName'] = index;
          } catch (e) {
            debugPrint('Failed to load index $collection.$fieldName: $e');
          }
        }
      }
    }
  }
  
  /// Closes all indexes
  Future<void> close() async {
    for (final index in _indexes.values) {
      await index.close();
    }
    _indexes.clear();
  }
}