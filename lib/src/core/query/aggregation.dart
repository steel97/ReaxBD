/// Aggregation functions for queries
enum AggregationFunction {
  count,
  sum,
  avg,
  min,
  max,
  distinct,
}

/// Aggregation result
class AggregationResult {
  final AggregationFunction function;
  final String? field;
  final dynamic value;
  final Map<String, dynamic> metadata;

  AggregationResult({
    required this.function,
    this.field,
    required this.value,
    this.metadata = const {},
  });

  @override
  String toString() {
    return 'AggregationResult(${function.name}${field != null ? '($field)' : ''}: $value)';
  }
}

/// Group by result
class GroupByResult {
  final dynamic groupKey;
  final List<Map<String, dynamic>> documents;
  final Map<String, AggregationResult> aggregations;

  GroupByResult({
    required this.groupKey,
    required this.documents,
    this.aggregations = const {},
  });
}

/// Aggregation builder
class AggregationBuilder {
  final List<_AggregationSpec> _aggregations = [];
  String? _groupByField;

  /// Add count aggregation
  AggregationBuilder count([String? field]) {
    _aggregations.add(_AggregationSpec(
      function: AggregationFunction.count,
      field: field,
    ));
    return this;
  }

  /// Add sum aggregation
  AggregationBuilder sum(String field) {
    _aggregations.add(_AggregationSpec(
      function: AggregationFunction.sum,
      field: field,
    ));
    return this;
  }

  /// Add average aggregation
  AggregationBuilder avg(String field) {
    _aggregations.add(_AggregationSpec(
      function: AggregationFunction.avg,
      field: field,
    ));
    return this;
  }

  /// Add min aggregation
  AggregationBuilder min(String field) {
    _aggregations.add(_AggregationSpec(
      function: AggregationFunction.min,
      field: field,
    ));
    return this;
  }

  /// Add max aggregation
  AggregationBuilder max(String field) {
    _aggregations.add(_AggregationSpec(
      function: AggregationFunction.max,
      field: field,
    ));
    return this;
  }

  /// Add distinct count aggregation
  AggregationBuilder distinct(String field) {
    _aggregations.add(_AggregationSpec(
      function: AggregationFunction.distinct,
      field: field,
    ));
    return this;
  }

  /// Group by field
  AggregationBuilder groupBy(String field) {
    _groupByField = field;
    return this;
  }

  /// Execute aggregations on documents
  dynamic execute(List<Map<String, dynamic>> documents) {
    if (documents.isEmpty) {
      return _groupByField != null ? [] : _executeSimple([]);
    }

    if (_groupByField != null) {
      return _executeGrouped(documents);
    } else {
      return _executeSimple(documents);
    }
  }

  Map<String, AggregationResult> _executeSimple(List<Map<String, dynamic>> documents) {
    final results = <String, AggregationResult>{};

    for (final spec in _aggregations) {
      final key = spec.field != null 
        ? '${spec.function.name}_${spec.field}' 
        : spec.function.name;
      
      results[key] = _executeAggregation(spec, documents);
    }

    return results;
  }

  List<GroupByResult> _executeGrouped(List<Map<String, dynamic>> documents) {
    final groups = <dynamic, List<Map<String, dynamic>>>{};

    // Group documents
    for (final doc in documents) {
      final groupKey = _getFieldValue(doc, _groupByField!);
      groups.putIfAbsent(groupKey, () => []).add(doc);
    }

    // Execute aggregations for each group
    final results = <GroupByResult>[];
    for (final entry in groups.entries) {
      final groupAggregations = <String, AggregationResult>{};
      
      for (final spec in _aggregations) {
        final key = spec.field != null 
          ? '${spec.function.name}_${spec.field}' 
          : spec.function.name;
        
        groupAggregations[key] = _executeAggregation(spec, entry.value);
      }

      results.add(GroupByResult(
        groupKey: entry.key,
        documents: entry.value,
        aggregations: groupAggregations,
      ));
    }

    return results;
  }

  AggregationResult _executeAggregation(
    _AggregationSpec spec,
    List<Map<String, dynamic>> documents,
  ) {
    switch (spec.function) {
      case AggregationFunction.count:
        if (spec.field == null) {
          return AggregationResult(
            function: spec.function,
            value: documents.length,
          );
        } else {
          final count = documents.where((doc) => 
            _getFieldValue(doc, spec.field!) != null
          ).length;
          return AggregationResult(
            function: spec.function,
            field: spec.field,
            value: count,
          );
        }

      case AggregationFunction.sum:
        num sum = 0;
        for (final doc in documents) {
          final value = _getFieldValue(doc, spec.field!);
          if (value is num) {
            sum += value;
          }
        }
        return AggregationResult(
          function: spec.function,
          field: spec.field,
          value: sum,
        );

      case AggregationFunction.avg:
        num sum = 0;
        int count = 0;
        for (final doc in documents) {
          final value = _getFieldValue(doc, spec.field!);
          if (value is num) {
            sum += value;
            count++;
          }
        }
        return AggregationResult(
          function: spec.function,
          field: spec.field,
          value: count > 0 ? sum / count : 0,
        );

      case AggregationFunction.min:
        dynamic minValue;
        for (final doc in documents) {
          final value = _getFieldValue(doc, spec.field!);
          if (value != null) {
            if (minValue == null || (value as Comparable).compareTo(minValue) < 0) {
              minValue = value;
            }
          }
        }
        return AggregationResult(
          function: spec.function,
          field: spec.field,
          value: minValue,
        );

      case AggregationFunction.max:
        dynamic maxValue;
        for (final doc in documents) {
          final value = _getFieldValue(doc, spec.field!);
          if (value != null) {
            if (maxValue == null || (value as Comparable).compareTo(maxValue) > 0) {
              maxValue = value;
            }
          }
        }
        return AggregationResult(
          function: spec.function,
          field: spec.field,
          value: maxValue,
        );

      case AggregationFunction.distinct:
        final distinctValues = <dynamic>{};
        for (final doc in documents) {
          final value = _getFieldValue(doc, spec.field!);
          if (value != null) {
            distinctValues.add(value);
          }
        }
        return AggregationResult(
          function: spec.function,
          field: spec.field,
          value: distinctValues.length,
          metadata: {'values': distinctValues.toList()},
        );
    }
  }

  dynamic _getFieldValue(Map<String, dynamic> doc, String field) {
    final parts = field.split('.');
    dynamic value = doc;
    
    for (final part in parts) {
      if (value is Map<String, dynamic>) {
        value = value[part];
      } else {
        return null;
      }
    }
    
    return value;
  }
}

class _AggregationSpec {
  final AggregationFunction function;
  final String? field;

  _AggregationSpec({
    required this.function,
    this.field,
  });
}