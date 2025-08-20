import 'package:flutter/material.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'package:path_provider/path_provider.dart';

class TodoDemoScreen extends StatefulWidget {
  const TodoDemoScreen({super.key});

  @override
  State<TodoDemoScreen> createState() => _TodoDemoScreenState();
}

class _TodoDemoScreenState extends State<TodoDemoScreen> {
  SimpleReaxDB? db;
  List<Map<String, dynamic>> todos = [];
  final TextEditingController todoController = TextEditingController();
  bool isLoading = true;
  
  @override
  void initState() {
    super.initState();
    initDatabase();
  }
  
  Future<void> initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    db = await ReaxDB.simple('todo_demo', path: '${dir.path}/reaxdb_todo');
    
    db!.watch('todo:*').listen((event) {
      loadTodos();
    });
    
    await loadTodos();
    setState(() {
      isLoading = false;
    });
  }
  
  Future<void> loadTodos() async {
    if (db == null) return;
    
    final allTodos = await db!.getAll('todo:*');
    setState(() {
      todos = allTodos.values
          .map((e) => e as Map<String, dynamic>)
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
    });
  }
  
  Future<void> addTodo(String title) async {
    if (title.isEmpty) return;
    
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await db!.put('todo:$id', {
      'id': id,
      'title': title,
      'completed': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    
    todoController.clear();
  }
  
  Future<void> toggleTodo(String id, bool currentStatus) async {
    final todo = await db!.get('todo:$id');
    if (todo != null) {
      todo['completed'] = !currentStatus;
      todo['completedAt'] = !currentStatus ? DateTime.now().toIso8601String() : null;
      await db!.put('todo:$id', todo);
    }
  }
  
  Future<void> deleteTodo(String id) async {
    await db!.delete('todo:$id');
  }
  
  @override
  void dispose() {
    todoController.dispose();
    db?.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final incompleteTodos = todos.where((t) => !(t['completed'] ?? false)).length;
    final completedTodos = todos.where((t) => t['completed'] ?? false).length;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todo App Demo'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '$incompleteTodos pending | $completedTodos done',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Add Todo
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: todoController,
                              decoration: const InputDecoration(
                                labelText: 'What needs to be done?',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: addTodo,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => addTodo(todoController.text),
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Todos List
                Expanded(
                  child: todos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, 
                                size: 64, 
                                color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              const Text('No todos yet!'),
                              const Text('Add your first task above'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: todos.length,
                          itemBuilder: (context, index) {
                            final todo = todos[index];
                            final isCompleted = todo['completed'] ?? false;
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Checkbox(
                                  value: isCompleted,
                                  onChanged: (_) => toggleTodo(todo['id'], isCompleted),
                                ),
                                title: Text(
                                  todo['title'] ?? '',
                                  style: TextStyle(
                                    decoration: isCompleted 
                                        ? TextDecoration.lineThrough 
                                        : null,
                                    color: isCompleted 
                                        ? Colors.grey 
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  _formatDate(todo['createdAt']),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => deleteTodo(todo['id']),
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
  
  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inDays == 0) {
        if (diff.inHours == 0) {
          if (diff.inMinutes == 0) {
            return 'Just now';
          }
          return '${diff.inMinutes}m ago';
        }
        return '${diff.inHours}h ago';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      }
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }
}