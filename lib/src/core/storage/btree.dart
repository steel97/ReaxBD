import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:path/path.dart' as path;

/// B+ Tree node types
enum BTreeNodeType { internal, leaf }

/// B+ Tree node
class BTreeNode {
  final BTreeNodeType type;
  final List<List<int>> keys = [];
  final List<dynamic> values = []; // Uint8List for leaf, BTreeNode for internal
  BTreeNode? parent;
  BTreeNode? next; // For leaf nodes linked list
  bool isDirty = false;
  
  BTreeNode(this.type);
  
  bool get isLeaf => type == BTreeNodeType.leaf;
  bool get isFull => keys.length >= BTree._maxKeys;
  
  void insertKey(List<int> key, dynamic value, int index) {
    keys.insert(index, key);
    values.insert(index, value);
    isDirty = true;
  }
  
  void removeKey(int index) {
    keys.removeAt(index);
    values.removeAt(index);
    isDirty = true;
  }
  
  int findKeyIndex(List<int> key) {
    final keyString = String.fromCharCodes(key);
    for (int i = 0; i < keys.length; i++) {
      final currentKeyString = String.fromCharCodes(keys[i]);
      if (currentKeyString.compareTo(keyString) >= 0) {
        return i;
      }
    }
    return keys.length;
  }
}

/// B+ Tree implementation for range queries and fast random access
class BTree {
  final String _path;
  BTreeNode? _root;
  BTreeNode? _firstLeaf;
  int _nodeCounter = 0;
  
  static const int _maxKeys = 100;
  static const int _minKeys = 50;
  
  BTree._(this._path);
  
  /// Creates a new B+ Tree
  static Future<BTree> create({required String basePath}) async {
    final btreePath = path.join(basePath, 'btree');
    final directory = Directory(btreePath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    final btree = BTree._(btreePath);
    await btree._initialize();
    return btree;
  }
  
  /// Puts a key-value pair
  Future<void> put(List<int> key, Uint8List value) async {
    if (_root == null) {
      _root = BTreeNode(BTreeNodeType.leaf);
      _firstLeaf = _root;
    }
    
    await _insertKey(_root!, key, value);
  }
  
  /// Gets a value by key
  Future<Uint8List?> get(List<int> key) async {
    if (_root == null) return null;
    
    final node = await _findLeafNode(_root!, key);
    final index = node.findKeyIndex(key);
    
    if (index < node.keys.length) {
      final keyString = String.fromCharCodes(key);
      final nodeKeyString = String.fromCharCodes(node.keys[index]);
      if (keyString == nodeKeyString) {
        return node.values[index] as Uint8List;
      }
    }
    
    return null;
  }
  
  /// Deletes a key
  Future<void> delete(List<int> key) async {
    if (_root == null) return;
    
    final node = await _findLeafNode(_root!, key);
    final index = node.findKeyIndex(key);
    
    if (index < node.keys.length) {
      final keyString = String.fromCharCodes(key);
      final nodeKeyString = String.fromCharCodes(node.keys[index]);
      if (keyString == nodeKeyString) {
        node.removeKey(index);
        await _handleUnderflow(node);
      }
    }
  }
  
  /// Gets a range of entries
  Future<Map<List<int>, Uint8List>> getRange(
    List<int>? startKey, 
    List<int>? endKey
  ) async {
    final result = <List<int>, Uint8List>{};
    if (_firstLeaf == null) return result;
    
    BTreeNode? currentNode = _firstLeaf;
    
    while (currentNode != null) {
      for (int i = 0; i < currentNode.keys.length; i++) {
        final key = currentNode.keys[i];
        final keyString = String.fromCharCodes(key);
        
        // Check if key is within range
        if (startKey != null) {
          final startKeyString = String.fromCharCodes(startKey);
          if (keyString.compareTo(startKeyString) < 0) continue;
        }
        
        if (endKey != null) {
          final endKeyString = String.fromCharCodes(endKey);
          if (keyString.compareTo(endKeyString) >= 0) {
            return result; // We've gone past the end
          }
        }
        
        result[key] = currentNode.values[i] as Uint8List;
      }
      
      currentNode = currentNode.next;
    }
    
    return result;
  }
  
  /// Closes the B+ Tree
  Future<void> close() async {
    await _persistTree();
  }
  
  Future<void> _initialize() async {
    // Try to load existing tree structure
    final metaFile = File(path.join(_path, 'btree.meta'));
    if (await metaFile.exists()) {
      await _loadTree();
    }
  }
  
  Future<BTreeNode> _findLeafNode(BTreeNode node, List<int> key) async {
    if (node.isLeaf) return node;
    
    final index = node.findKeyIndex(key);
    final childIndex = min(index, node.values.length - 1);
    return await _findLeafNode(node.values[childIndex] as BTreeNode, key);
  }
  
  Future<void> _insertKey(BTreeNode node, List<int> key, Uint8List value) async {
    if (node.isLeaf) {
      final index = node.findKeyIndex(key);
      
      // Check if key already exists
      if (index < node.keys.length) {
        final keyString = String.fromCharCodes(key);
        final nodeKeyString = String.fromCharCodes(node.keys[index]);
        if (keyString == nodeKeyString) {
          node.values[index] = value; // Update existing
          node.isDirty = true;
          return;
        }
      }
      
      node.insertKey(key, value, index);
      
      if (node.isFull) {
        await _splitLeafNode(node);
      }
    } else {
      final index = node.findKeyIndex(key);
      final childIndex = min(index, node.values.length - 1);
      await _insertKey(node.values[childIndex] as BTreeNode, key, value);
    }
  }
  
  Future<void> _splitLeafNode(BTreeNode node) async {
    final midIndex = node.keys.length ~/ 2;
    final newNode = BTreeNode(BTreeNodeType.leaf);
    
    // Move half the keys to new node
    for (int i = midIndex; i < node.keys.length; i++) {
      newNode.keys.add(node.keys[i]);
      newNode.values.add(node.values[i]);
    }
    
    // Remove moved keys from original node
    node.keys.removeRange(midIndex, node.keys.length);
    node.values.removeRange(midIndex, node.values.length);
    
    // Update linked list
    newNode.next = node.next;
    node.next = newNode;
    newNode.parent = node.parent;
    
    // If this is root, create new root
    if (node.parent == null) {
      final newRoot = BTreeNode(BTreeNodeType.internal);
      newRoot.keys.add(newNode.keys.first);
      newRoot.values.add(node);
      newRoot.values.add(newNode);
      
      node.parent = newRoot;
      newNode.parent = newRoot;
      _root = newRoot;
    } else {
      await _insertIntoParent(node.parent!, newNode.keys.first, newNode);
    }
    
    node.isDirty = true;
    newNode.isDirty = true;
  }
  
  Future<void> _insertIntoParent(
    BTreeNode parent, 
    List<int> key, 
    BTreeNode newChild
  ) async {
    final index = parent.findKeyIndex(key);
    parent.insertKey(key, newChild, index);
    
    if (parent.isFull) {
      await _splitInternalNode(parent);
    }
  }
  
  Future<void> _splitInternalNode(BTreeNode node) async {
    final midIndex = node.keys.length ~/ 2;
    final newNode = BTreeNode(BTreeNodeType.internal);
    final promotedKey = node.keys[midIndex];
    
    // Move half the keys to new node (excluding promoted key)
    for (int i = midIndex + 1; i < node.keys.length; i++) {
      newNode.keys.add(node.keys[i]);
      newNode.values.add(node.values[i + 1]);
      (node.values[i + 1] as BTreeNode).parent = newNode;
    }
    
    // Remove moved keys from original node
    node.keys.removeRange(midIndex, node.keys.length);
    node.values.removeRange(midIndex + 1, node.values.length);
    
    newNode.parent = node.parent;
    
    // If this is root, create new root
    if (node.parent == null) {
      final newRoot = BTreeNode(BTreeNodeType.internal);
      newRoot.keys.add(promotedKey);
      newRoot.values.add(node);
      newRoot.values.add(newNode);
      
      node.parent = newRoot;
      newNode.parent = newRoot;
      _root = newRoot;
    } else {
      await _insertIntoParent(node.parent!, promotedKey, newNode);
    }
    
    node.isDirty = true;
    newNode.isDirty = true;
  }
  
  Future<void> _handleUnderflow(BTreeNode node) async {
    if (node.keys.length >= _minKeys || node.parent == null) return;
    
    // Try to borrow from siblings or merge
    // Simplified implementation - just mark as dirty for now
    node.isDirty = true;
  }
  
  Future<void> _persistTree() async {
    // Simplified persistence - in production would serialize entire tree
    final metaFile = File(path.join(_path, 'btree.meta'));
    final meta = {
      'nodeCounter': _nodeCounter,
      'hasRoot': _root != null,
    };
    await metaFile.writeAsString(jsonEncode(meta));
  }
  
  Future<void> _loadTree() async {
    // Simplified loading - in production would deserialize entire tree
    final metaFile = File(path.join(_path, 'btree.meta'));
    final content = await metaFile.readAsString();
    final meta = jsonDecode(content) as Map<String, dynamic>;
    _nodeCounter = meta['nodeCounter'] as int;
  }
}