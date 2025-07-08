import 'package:flutter_test/flutter_test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';

void main() {
  test('ReaxDB library should export main classes', () {
    // Test that main classes are available for import
    expect(DatabaseConfig, isNotNull);
    expect(HybridStorageEngine, isNotNull);
    expect(MultiLevelCache, isNotNull);
  });
}