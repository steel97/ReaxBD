import 'package:flutter/material.dart';
import 'package:reaxdb_dart/reaxdb_dart.dart';
import 'package:path_provider/path_provider.dart';

class ChatDemoScreen extends StatefulWidget {
  const ChatDemoScreen({super.key});

  @override
  State<ChatDemoScreen> createState() => _ChatDemoScreenState();
}

class _ChatDemoScreenState extends State<ChatDemoScreen> {
  SimpleReaxDB? db;
  List<Map<String, dynamic>> messages = [];
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  bool isLoading = true;
  String currentUser = 'Alice';
  
  @override
  void initState() {
    super.initState();
    initDatabase();
  }
  
  Future<void> initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    db = await ReaxDB.simple('chat_demo', path: '${dir.path}/reaxdb_chat');
    
    db!.watch('message:*').listen((event) {
      loadMessages();
    });
    
    await loadMessages();
    setState(() {
      isLoading = false;
    });
    
    _scrollToBottom();
  }
  
  Future<void> loadMessages() async {
    if (db == null) return;
    
    final allMessages = await db!.getAll('message:*');
    setState(() {
      messages = allMessages.values
          .map((e) => e as Map<String, dynamic>)
          .toList()
        ..sort((a, b) => (a['timestamp'] ?? '').compareTo(b['timestamp'] ?? ''));
    });
    
    _scrollToBottom();
  }
  
  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;
    
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await db!.put('message:$id', {
      'id': id,
      'text': text,
      'sender': currentUser,
      'timestamp': DateTime.now().toIso8601String(),
    });
    
    messageController.clear();
    
    // Simulate reply from other user
    if (currentUser == 'Alice') {
      Future.delayed(const Duration(seconds: 1), () async {
        final replyId = DateTime.now().millisecondsSinceEpoch.toString();
        await db!.put('message:$replyId', {
          'id': replyId,
          'text': _generateReply(text),
          'sender': 'Bob',
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
    }
  }
  
  String _generateReply(String message) {
    final replies = [
      'That\'s interesting!',
      'I see what you mean.',
      'Tell me more about that.',
      'Cool! ReaxDB makes this so easy!',
      'Real-time sync is amazing!',
      'I love how fast this is!',
    ];
    return replies[message.length % replies.length];
  }
  
  void _scrollToBottom() {
    if (scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }
  
  void switchUser() {
    setState(() {
      currentUser = currentUser == 'Alice' ? 'Bob' : 'Alice';
    });
  }
  
  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    db?.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Demo'),
        actions: [
          TextButton.icon(
            onPressed: switchUser,
            icon: const Icon(Icons.person, color: Colors.white),
            label: Text(
              'Current: $currentUser',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              await db!.clear();
              setState(() {
                messages.clear();
              });
            },
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Messages
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, 
                                size: 64, 
                                color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              const Text('No messages yet!'),
                              const Text('Start a conversation below'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMe = message['sender'] == currentUser;
                            
                            return Align(
                              alignment: isMe 
                                  ? Alignment.centerRight 
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16, 
                                  vertical: 10,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe 
                                      ? Theme.of(context).colorScheme.primary 
                                      : Colors.grey[300],
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message['sender'] ?? '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isMe ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      message['text'] ?? '',
                                      style: TextStyle(
                                        color: isMe ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                
                // Input
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: sendMessage,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: () => sendMessage(messageController.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}