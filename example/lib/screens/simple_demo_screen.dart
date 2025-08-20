import 'package:flutter/material.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class SimpleDemoScreen extends StatefulWidget {
  const SimpleDemoScreen({super.key});

  @override
  State<SimpleDemoScreen> createState() => _SimpleDemoScreenState();
}

class _SimpleDemoScreenState extends State<SimpleDemoScreen> {
  SimpleReaxDB? db;
  List<MapEntry<String, dynamic>> items = [];
  bool isLoading = true;
  
  final keyController = TextEditingController();
  final valueController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    initDatabase();
  }
  
  Future<void> initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    db = await ReaxDB.simple('simple_demo', path: '${dir.path}/reaxdb_simple');
    
    db!.watch().listen((event) {
      loadItems();
    });
    
    await loadItems();
    setState(() {
      isLoading = false;
    });
  }
  
  Future<void> loadItems() async {
    if (db == null) return;
    
    final allItems = await db!.getAll('*');
    setState(() {
      items = allItems.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
    });
  }
  
  Future<void> addItem() async {
    if (keyController.text.isEmpty || valueController.text.isEmpty) return;
    
    dynamic value = valueController.text;
    try {
      if (value.startsWith('{') || value.startsWith('[')) {
        value = jsonDecode(value);
      } else if (value == 'true' || value == 'false') {
        value = value == 'true';
      } else if (int.tryParse(value) != null) {
        value = int.parse(value);
      } else if (double.tryParse(value) != null) {
        value = double.parse(value);
      }
    } catch (_) {}
    
    final key = keyController.text;
    await db!.put(key, value);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $key')),
      );
    }
    
    keyController.clear();
    valueController.clear();
  }
  
  @override
  void dispose() {
    keyController.dispose();
    valueController.dispose();
    db?.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple ReaxDB Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box),
            onPressed: () async {
              await db!.putAll({
                'user:1': {'name': 'Alice', 'age': 28},
                'user:2': {'name': 'Bob', 'age': 32},
                'settings': {'theme': 'dark', 'notifications': true},
                'counter': 42,
              });
            },
            tooltip: 'Add Sample Data',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Add Item Form
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: keyController,
                              decoration: const InputDecoration(
                                labelText: 'Key',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: valueController,
                              decoration: const InputDecoration(
                                labelText: 'Value',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: addItem,
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Items List
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('No items yet'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Card(
                              child: ListTile(
                                title: Text(item.key),
                                subtitle: Text(
                                  item.value is Map || item.value is List
                                      ? jsonEncode(item.value)
                                      : item.value.toString(),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () async {
                                    await db!.delete(item.key);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}