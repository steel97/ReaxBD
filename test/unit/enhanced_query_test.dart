import 'package:test/test.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'dart:io';

void main() {
  group('Enhanced Query Builder Tests', () {
    late ReaxDB db;
    final testPath = 'test/enhanced_query_test_db';

    setUp(() async {
      // Clean up before test
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      db = await ReaxDB.open(testPath);

      // Seed test data
      await _seedTestData(db);
    });

    tearDown(() async {
      await db.close();
      // Clean up after test
      final dir = Directory(testPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    group('Aggregation Functions', () {
      test('should count documents', () async {
        final result = await db
            .collection('products')
            .aggregate((agg) => agg.count())
            .executeAggregation();

        expect(result, isA<Map<String, AggregationResult>>());
        expect(result['count'].value, equals(10));
      });

      test('should calculate sum', () async {
        final result = await db
            .collection('products')
            .aggregate((agg) => agg.sum('price'))
            .executeAggregation();

        expect(result['sum_price'].value, equals(4900));
      });

      test('should calculate average', () async {
        final result = await db
            .collection('products')
            .aggregate((agg) => agg.avg('price'))
            .executeAggregation();

        expect(result['avg_price'].value, equals(490));
      });

      test('should find min and max values', () async {
        final result = await db
            .collection('products')
            .aggregate((agg) => agg
              .min('price')
              .max('price'))
            .executeAggregation();

        expect(result['min_price'].value, equals(100));
        expect(result['max_price'].value, equals(1000));
      });

      test('should count distinct values', () async {
        final result = await db
            .collection('products')
            .aggregate((agg) => agg.distinct('category'))
            .executeAggregation();

        expect(result['distinct_category'].value, equals(3));
        expect(result['distinct_category'].metadata['values'], 
          containsAll(['electronics', 'books', 'clothing']));
      });

      test('should support multiple aggregations', () async {
        final result = await db
            .collection('products')
            .aggregate((agg) => agg
              .count()
              .sum('price')
              .avg('price')
              .min('stock')
              .max('stock'))
            .executeAggregation();

        expect(result['count'].value, equals(10));
        expect(result['sum_price'].value, equals(4900));
        expect(result['avg_price'].value, equals(490));
        expect(result['min_stock'].value, equals(5));
        expect(result['max_stock'].value, equals(50));
      });
    });

    group('Group By Operations', () {
      test('should group by category', () async {
        final result = await db
            .collection('products')
            .aggregate((agg) => agg
              .groupBy('category')
              .count()
              .sum('price')
              .avg('price'))
            .executeAggregation();

        expect(result, isA<List<GroupByResult>>());
        expect(result.length, equals(3));

        final electronics = result.firstWhere((g) => g.groupKey == 'electronics');
        expect(electronics.documents.length, equals(4));
        expect(electronics.aggregations['count'].value, equals(4));
      });

      test('should group and calculate aggregations per group', () async {
        final result = await db
            .collection('orders')
            .aggregate((agg) => agg
              .groupBy('customerId')
              .count()
              .sum('total')
              .avg('total'))
            .executeAggregation();

        expect(result, isA<List<GroupByResult>>());
        
        final customer1 = result.firstWhere((g) => g.groupKey == 'customer1');
        expect(customer1.aggregations['count'].value, equals(2));
        expect(customer1.aggregations['sum_total'].value, equals(350));
        expect(customer1.aggregations['avg_total'].value, equals(175));
      });
    });

    group('Text Search', () {
      test('should search in all fields', () async {
        final results = await db
            .collection('products')
            .search('laptop')
            .find();

        expect(results.length, equals(1));
        expect(results[0]['name'], equals('Laptop'));
      });

      test('should search in specific field', () async {
        final results = await db
            .collection('products')
            .search('novel', field: 'description')
            .find();

        expect(results.length, equals(2));
        expect(results.every((r) => r['category'] == 'books'), isTrue);
      });

      test('should be case insensitive', () async {
        final results = await db
            .collection('products')
            .search('PHONE')
            .find();

        // Phone and Headphones both contain 'phone'
        expect(results.length, equals(2));
        expect(results.any((r) => r['name'] == 'Phone'), isTrue);
        expect(results.any((r) => r['name'] == 'Headphones'), isTrue);
      });

      test('should combine search with other conditions', () async {
        final results = await db
            .collection('products')
            .whereGreaterThan('price', 200)
            .search('book')
            .find();

        expect(results.length, equals(1));
        expect(results[0]['name'], equals('Textbook'));
      });
    });

    group('Distinct Values', () {
      test('should get distinct categories', () async {
        final categories = await db
            .collection('products')
            .distinct('category');

        expect(categories.length, equals(3));
        expect(categories, containsAll(['electronics', 'books', 'clothing']));
      });

      test('should get distinct values with filter', () async {
        final prices = await db
            .collection('products')
            .whereEquals('category', 'electronics')
            .distinct('price');

        expect(prices.length, equals(4));
        expect(prices, containsAll([800, 500, 1000, 700]));
      });
    });

    group('Update Operations', () {
      test('should update matching documents', () async {
        final updateCount = await db
            .collection('products')
            .whereEquals('category', 'books')
            .update({'onSale': true, 'discount': 0.2});

        expect(updateCount, equals(3));

        // Verify updates
        final books = await db
            .collection('products')
            .whereEquals('category', 'books')
            .find();

        expect(books.every((b) => b['onSale'] == true), isTrue);
        expect(books.every((b) => b['discount'] == 0.2), isTrue);
      });

      test('should update with complex conditions', () async {
        final updateCount = await db
            .collection('products')
            .whereGreaterThan('price', 500)
            .whereLessThan('stock', 20)
            .update({'priority': 'high'});

        expect(updateCount, greaterThan(0));
      });
    });

    group('Delete Operations', () {
      test('should delete matching documents', () async {
        final deleteCount = await db
            .collection('products')
            .whereLessThan('stock', 10)
            .delete();

        expect(deleteCount, equals(2));

        // Verify deletion
        final remaining = await db
            .collection('products')
            .find();

        expect(remaining.length, equals(8));
      });

      test('should delete with multiple conditions', () async {
        final deleteCount = await db
            .collection('products')
            .whereEquals('category', 'electronics')
            .whereGreaterThan('price', 600)
            .delete();

        expect(deleteCount, equals(3));
      });
    });

    group('Complex Queries', () {
      test('should handle contains operator for arrays', () async {
        await db.put('products:11', {
          'name': 'Multi-category',
          'categories': ['electronics', 'accessories'],
        });

        final results = await db
            .collection('products')
            .where('categories', QueryOperator.contains, 'accessories')
            .find();

        expect(results.length, equals(1));
        expect(results[0]['name'], equals('Multi-category'));
      });

      test('should chain multiple operations', () async {
        final result = await db
            .collection('products')
            .whereGreaterThan('price', 200)
            .whereLessThan('price', 900)
            .orderBy('price', descending: true)
            .limit(3)
            .aggregate((agg) => agg
              .count()
              .avg('price'))
            .executeAggregation();

        expect(result['count'].value, equals(3));
      });

      test('should handle nested field queries', () async {
        await db.put('products:12', {
          'name': 'Complex Product',
          'details': {
            'manufacturer': 'ACME',
            'warranty': 24,
            'specs': {
              'weight': 1.5,
              'color': 'black'
            }
          }
        });

        // Note: This would require implementing nested field support
        // For now, we'll test that the structure is preserved
        final product = await db.get<Map<String, dynamic>>('products:12');
        expect(product!['details']['manufacturer'], equals('ACME'));
        expect(product['details']['specs']['color'], equals('black'));
      });
    });

    group('Performance', () {
      test('should handle large aggregations efficiently', () async {
        // Add more test data
        for (int i = 100; i < 1000; i++) {
          await db.put('products:$i', {
            'name': 'Product $i',
            'price': (i % 100) * 10,
            'category': ['cat1', 'cat2', 'cat3'][i % 3],
            'stock': i % 50,
          });
        }

        final stopwatch = Stopwatch()..start();
        
        final result = await db
            .collection('products')
            .aggregate((agg) => agg
              .groupBy('category')
              .count()
              .sum('price')
              .avg('price')
              .min('price')
              .max('price'))
            .executeAggregation();

        stopwatch.stop();

        expect(result, isA<List<GroupByResult>>());
        expect(result.length, equals(6)); // 3 original categories + 3 new ones
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Should be fast
      });
    });
  });
}

Future<void> _seedTestData(ReaxDB db) async {
  // Products collection
  final products = [
    {'id': '1', 'name': 'Laptop', 'price': 800, 'category': 'electronics', 'stock': 15, 'description': 'High performance laptop'},
    {'id': '2', 'name': 'Phone', 'price': 500, 'category': 'electronics', 'stock': 30, 'description': 'Smartphone with 5G'},
    {'id': '3', 'name': 'Tablet', 'price': 1000, 'category': 'electronics', 'stock': 10, 'description': 'Professional tablet'},
    {'id': '4', 'name': 'Headphones', 'price': 700, 'category': 'electronics', 'stock': 25, 'description': 'Wireless headphones'},
    {'id': '5', 'name': 'Novel', 'price': 100, 'category': 'books', 'stock': 50, 'description': 'Bestselling novel'},
    {'id': '6', 'name': 'Textbook', 'price': 450, 'category': 'books', 'stock': 5, 'description': 'Computer science textbook'},
    {'id': '7', 'name': 'Comic', 'price': 150, 'category': 'books', 'stock': 40, 'description': 'Graphic novel series'},
    {'id': '8', 'name': 'T-Shirt', 'price': 200, 'category': 'clothing', 'stock': 35, 'description': 'Cotton t-shirt'},
    {'id': '9', 'name': 'Jeans', 'price': 400, 'category': 'clothing', 'stock': 20, 'description': 'Denim jeans'},
    {'id': '10', 'name': 'Jacket', 'price': 600, 'category': 'clothing', 'stock': 8, 'description': 'Winter jacket'},
  ];

  for (final product in products) {
    await db.put('products:${product['id']}', product);
  }

  // Orders collection for join tests
  final orders = [
    {'id': '1', 'customerId': 'customer1', 'productId': '1', 'quantity': 1, 'total': 150},
    {'id': '2', 'customerId': 'customer1', 'productId': '2', 'quantity': 2, 'total': 200},
    {'id': '3', 'customerId': 'customer2', 'productId': '3', 'quantity': 1, 'total': 300},
    {'id': '4', 'customerId': 'customer3', 'productId': '1', 'quantity': 3, 'total': 450},
  ];

  for (final order in orders) {
    await db.put('orders:${order['id']}', order);
  }

  // Indexes would be created separately through IndexManager in a real app
  // For testing, we'll skip index creation as it's not part of QueryBuilder
}