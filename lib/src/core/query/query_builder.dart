import 'package:flutter/foundation.dart';

import '../indexing/index_manager.dart';
import '../indexing/secondary_index.dart';
import '../../reaxdb.dart';

/// Query operators
enum QueryOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  between,
  inList,
  contains,
}

/// Query condition
class QueryCondition {
  final String field;
  final QueryOperator operator;
  final dynamic value;

  QueryCondition({
    required this.field,
    required this.operator,
    required this.value,
  });
}

/// Query builder for ReaxDB
class QueryBuilder {
  final String collection;
  final ReaxDB _db;
  final IndexManager _indexManager;
  final List<QueryCondition> _conditions = [];
  int? _limitValue;
  int? _offsetValue;
  String? _orderByField;
  bool _orderDescending = false;

  QueryBuilder({
    required this.collection,
    required ReaxDB db,
    required IndexManager indexManager,
  }) : _db = db,
       _indexManager = indexManager;

  /// Adds a where condition
  QueryBuilder where(String field, QueryOperator operator, dynamic value) {
    _conditions.add(
      QueryCondition(field: field, operator: operator, value: value),
    );
    return this;
  }

  /// Convenience method for equality
  QueryBuilder whereEquals(String field, dynamic value) {
    return where(field, QueryOperator.equals, value);
  }

  /// Convenience method for greater than
  QueryBuilder whereGreaterThan(String field, dynamic value) {
    return where(field, QueryOperator.greaterThan, value);
  }

  /// Convenience method for less than
  QueryBuilder whereLessThan(String field, dynamic value) {
    return where(field, QueryOperator.lessThan, value);
  }

  /// Convenience method for range queries
  QueryBuilder whereBetween(String field, dynamic start, dynamic end) {
    return where(field, QueryOperator.between, [start, end]);
  }

  /// Convenience method for IN queries
  QueryBuilder whereIn(String field, List<dynamic> values) {
    return where(field, QueryOperator.inList, values);
  }

  /// Orders results by a field
  QueryBuilder orderBy(String field, {bool descending = false}) {
    _orderByField = field;
    _orderDescending = descending;
    return this;
  }

  /// Limits the number of results
  QueryBuilder limit(int count) {
    _limitValue = count;
    return this;
  }

  /// Skips a number of results
  QueryBuilder offset(int count) {
    _offsetValue = count;
    return this;
  }

  /// Executes the query and returns all matching documents
  Future<List<Map<String, dynamic>>> find() async {
    // Start with all document IDs or use index if available
    Set<String> candidateIds = {};
    bool hasIndexedQuery = false;

    // Try to use indexes for efficient filtering
    for (final condition in _conditions) {
      final index = _indexManager.getIndex(collection, condition.field);

      if (index != null && _canUseIndex(condition)) {
        hasIndexedQuery = true;
        final indexResults = await _queryIndex(index, condition);

        if (candidateIds.isEmpty) {
          candidateIds = indexResults.toSet();
        } else {
          // Intersect with previous results
          candidateIds = candidateIds.intersection(indexResults.toSet());
        }

        // Early exit if no candidates left
        if (candidateIds.isEmpty) {
          return [];
        }
      }
    }

    // If no indexed query, we need to scan all documents
    if (!hasIndexedQuery) {
      // For ordering without conditions, we need all documents
      if (_orderByField != null &&
          _indexManager.getIndex(collection, _orderByField!) != null) {
        // We have an index on the order field, so we can use it
        final index = _indexManager.getIndex(collection, _orderByField!)!;

        // Get all documents via the index by doing a full range scan
        candidateIds = (await index.findRange(null, null)).toSet();
      } else {
        // Collection scanning not implemented - requires storage engine enhancement
        // Current architecture limitation: HybridStorageEngine doesn't support
        // efficient prefix scanning needed for collection-wide queries.
        //
        // Workaround: Create indexes on fields you want to query.
        // Future enhancement: Add scanPrefix method to HybridStorageEngine.
        debugPrint('Warning: Query without index not yet implemented');
        return [];
      }
    }

    // Load documents and apply remaining filters
    final results = <Map<String, dynamic>>[];

    for (final docId in candidateIds) {
      final doc = await _loadDocument(docId);

      if (doc != null && _matchesAllConditions(doc)) {
        results.add(doc);
      }
    }

    // Apply sorting
    if (_orderByField != null) {
      _sortResults(results);
    }

    // Apply offset and limit
    final start = _offsetValue ?? 0;
    final end = _limitValue != null ? start + _limitValue! : results.length;

    return results.sublist(
      start.clamp(0, results.length),
      end.clamp(0, results.length),
    );
  }

  /// Executes the query and returns the first matching document
  Future<Map<String, dynamic>?> findOne() async {
    final results = await limit(1).find();
    return results.isEmpty ? null : results.first;
  }

  /// Counts matching documents
  Future<int> count() async {
    final results = await find();
    return results.length;
  }

  /// Checks if a condition can use an index
  bool _canUseIndex(QueryCondition condition) {
    switch (condition.operator) {
      case QueryOperator.equals:
      case QueryOperator.greaterThan:
      case QueryOperator.greaterThanOrEqual:
      case QueryOperator.lessThan:
      case QueryOperator.lessThanOrEqual:
      case QueryOperator.between:
        return true;
      default:
        return false;
    }
  }

  /// Queries an index for matching document IDs
  Future<List<String>> _queryIndex(
    SecondaryIndex index,
    QueryCondition condition,
  ) async {
    switch (condition.operator) {
      case QueryOperator.equals:
        return index.findEquals(condition.value);

      case QueryOperator.greaterThan:
      case QueryOperator.greaterThanOrEqual:
        return index.findRange(
          condition.value,
          null,
          includeStart: condition.operator == QueryOperator.greaterThanOrEqual,
        );

      case QueryOperator.lessThan:
      case QueryOperator.lessThanOrEqual:
        return index.findRange(
          null,
          condition.value,
          includeEnd: condition.operator == QueryOperator.lessThanOrEqual,
        );

      case QueryOperator.between:
        if (condition.value is List && condition.value.length == 2) {
          return index.findRange(
            condition.value[0],
            condition.value[1],
            includeStart: true,
            includeEnd: true,
          );
        }
        return [];

      default:
        return [];
    }
  }

  /// Loads a document by ID
  Future<Map<String, dynamic>?> _loadDocument(String docId) async {
    final key = '$collection:$docId';
    return await _db.get<Map<String, dynamic>>(key);
  }

  /// Checks if a document matches all conditions
  bool _matchesAllConditions(Map<String, dynamic> doc) {
    for (final condition in _conditions) {
      if (!_matchesCondition(doc, condition)) {
        return false;
      }
    }
    return true;
  }

  /// Checks if a document matches a single condition
  bool _matchesCondition(Map<String, dynamic> doc, QueryCondition condition) {
    final fieldValue = doc[condition.field];

    switch (condition.operator) {
      case QueryOperator.equals:
        return fieldValue == condition.value;

      case QueryOperator.notEquals:
        return fieldValue != condition.value;

      case QueryOperator.greaterThan:
        return _compare(fieldValue, condition.value) > 0;

      case QueryOperator.greaterThanOrEqual:
        return _compare(fieldValue, condition.value) >= 0;

      case QueryOperator.lessThan:
        return _compare(fieldValue, condition.value) < 0;

      case QueryOperator.lessThanOrEqual:
        return _compare(fieldValue, condition.value) <= 0;

      case QueryOperator.between:
        if (condition.value is List && condition.value.length == 2) {
          return _compare(fieldValue, condition.value[0]) >= 0 &&
              _compare(fieldValue, condition.value[1]) <= 0;
        }
        return false;

      case QueryOperator.inList:
        return (condition.value as List).contains(fieldValue);

      case QueryOperator.contains:
        if (fieldValue is String && condition.value is String) {
          return fieldValue.contains(condition.value);
        }
        return false;
    }
  }

  /// Compares two values
  int _compare(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;

    if (a is num && b is num) {
      return a.compareTo(b);
    }

    return a.toString().compareTo(b.toString());
  }

  /// Sorts results by the order field
  void _sortResults(List<Map<String, dynamic>> results) {
    results.sort((a, b) {
      final aValue = a[_orderByField!];
      final bValue = b[_orderByField!];

      final comparison = _compare(aValue, bValue);
      return _orderDescending ? -comparison : comparison;
    });
  }
}
