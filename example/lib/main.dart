import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:math';

import 'services/database_service.dart';
import 'widgets/performance_stats_card.dart';
import 'widgets/console_widget.dart';
import 'widgets/action_button.dart';

void main() {
  runApp(ReaxDBExampleApp());
}

class ReaxDBExampleApp extends StatelessWidget {
  const ReaxDBExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReaxDB Demo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1976D2),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: DatabaseExampleScreen(),
    );
  }
}

class DatabaseExampleScreen extends StatefulWidget {
  const DatabaseExampleScreen({super.key});

  @override
  DatabaseExampleScreenState createState() => DatabaseExampleScreenState();
}

class DatabaseExampleScreenState extends State<DatabaseExampleScreen> {
  final List<String> _logs = [];
  bool _isLoading = false;
  bool _realTimeMode = false;
  int _realTimeCounter = 0;
  Timer? _realTimeTimer;
  
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  
  // Performance metrics
  int _totalOperations = 0;
  int _successfulOperations = 0;
  final List<int> _latencies = [];

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    setState(() {
      _isLoading = true;
      _logs.clear();
    });

    try {
      _addLog('Initializing ReaxDB...');
      
      final directory = await getApplicationDocumentsDirectory();
      final dbPath = '${directory.path}/reaxdb_example';
      
      _addLog('Database path: $dbPath');
      
      await DatabaseService.initialize(dbPath);
      
      _addLog('Database opened successfully!');
      
      await _testBasicOperations();
      
    } catch (e) {
      _addLog('Error initializing database: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testBasicOperations() async {
    try {
      _addLog('\n--- Testing Basic Operations ---');
      
      await DatabaseService.database!.put('test_key', {
        'message': 'Hello ReaxDB!', 
        'timestamp': DateTime.now().toIso8601String()
      });
      _addLog('✓ Put operation successful');
      
      final value = await DatabaseService.database!.get('test_key');
      _addLog('✓ Get operation successful: $value');
      
      final info = await DatabaseService.database!.getDatabaseInfo();
      _addLog('✓ Database info: $info');
      
    } catch (e) {
      _addLog('Error in basic operations: $e');
    }
  }

  Future<void> _runSecurityTests() async {
    try {
      final logs = await DatabaseService.runSecurityTests();
      for (final log in logs) {
        _addLog(log);
      }
    } catch (e) {
      _addLog('❌ Security test error: $e');
    }
  }

  Future<void> _runConcurrencyTest() async {
    try {
      final logs = await DatabaseService.runConcurrencyTest();
      for (final log in logs) {
        _addLog(log);
      }
    } catch (e) {
      _addLog('❌ Concurrency test error: $e');
    }
  }

  Future<void> _runOptimizedConcurrencyTest() async {
    try {
      final logs = await DatabaseService.runOptimizedConcurrencyTest();
      for (final log in logs) {
        _addLog(log);
      }
    } catch (e) {
      _addLog('❌ Optimized test error: $e');
    }
  }

  Future<void> _runExtremeStressTest() async {
    try {
      final logs = await DatabaseService.runExtremeStressTest();
      for (final log in logs) {
        _addLog(log);
      }
    } catch (e) {
      _addLog('❌ Extreme stress test error: $e');
    }
  }

  Future<void> _startRealTimeTest() async {
    if (_realTimeMode) {
      _stopRealTimeTest();
      return;
    }

    try {
      _addLog('\n⚡ --- REAL-TIME PERFORMANCE TEST STARTED ---');
      
      setState(() {
        _realTimeMode = true;
        _realTimeCounter = 0;
        _latencies.clear();
        _totalOperations = 0;
        _successfulOperations = 0;
      });

      _realTimeTimer = Timer.periodic(Duration(milliseconds: 100), (timer) async {
        if (!_realTimeMode) {
          timer.cancel();
          return;
        }

        final stopwatch = Stopwatch()..start();
        
        try {
          await DatabaseService.database!.put('realtime_$_realTimeCounter', {
            'sensor_id': _realTimeCounter % 10,
            'value': Random().nextDouble() * 100,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'location': {
              'lat': 40.7128 + Random().nextDouble(), 
              'lng': -74.0060 + Random().nextDouble()
            },
          });
          
          stopwatch.stop();
          _latencies.add(stopwatch.elapsedMicroseconds);
          _successfulOperations++;
          
          if (_realTimeCounter % 50 == 0) {
            final avgLatency = _latencies.isEmpty ? 0 : 
                _latencies.reduce((a, b) => a + b) / _latencies.length;
            final opsPerSec = _successfulOperations / ((_realTimeCounter + 1) * 0.1);
            
            _addLog('⚡ Real-time: ${_realTimeCounter + 1} ops, ${opsPerSec.toStringAsFixed(1)} ops/sec, ${avgLatency.toStringAsFixed(1)}μs avg');
          }
          
        } catch (e) {
          _addLog('❌ Real-time error at operation $_realTimeCounter: $e');
        }
        
        _totalOperations++;
        _realTimeCounter++;
        
        if (_realTimeCounter >= 1000) {
          _stopRealTimeTest();
        }
      });
      
    } catch (e) {
      _addLog('❌ Real-time test error: $e');
    }
  }

  void _stopRealTimeTest() {
    if (!_realTimeMode) return;
    
    _realTimeTimer?.cancel();
    setState(() {
      _realTimeMode = false;
    });
    
    final avgLatency = _latencies.isEmpty ? 0 : 
        _latencies.reduce((a, b) => a + b) / _latencies.length;
    final totalTime = _totalOperations * 0.1;
    final opsPerSec = _successfulOperations / totalTime;
    
    _addLog('\n📊 REAL-TIME TEST RESULTS:');
    _addLog('   Operations: $_successfulOperations/$_totalOperations');
    _addLog('   Success rate: ${(_successfulOperations / _totalOperations * 100).toStringAsFixed(2)}%');
    _addLog('   Throughput: ${opsPerSec.toStringAsFixed(2)} ops/sec');
    _addLog('   Avg latency: ${avgLatency.toStringAsFixed(2)}μs');
    _addLog('   Max latency: ${_latencies.isEmpty ? 0 : _latencies.reduce((a, b) => a > b ? a : b)}μs');
  }

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
      });
    }
    debugPrint(message);
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  @override
  void dispose() {
    _realTimeTimer?.cancel();
    DatabaseService.close();
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.storage, size: 24),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ReaxDB Demo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('High-Performance NoSQL Database', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
              ],
            ),
          ],
        ),
        actions: [
          if (_realTimeMode)
            Container(
              margin: EdgeInsets.only(right: 16),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 8, color: Colors.white),
                  SizedBox(width: 4),
                  Text('LIVE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(height: 16),
                  Text('Initializing ReaxDB...', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Performance Stats
                  PerformanceStatsCard(
                    totalOperations: _totalOperations,
                    successfulOperations: _successfulOperations,
                    latencies: _latencies,
                  ),
                  
                  // Control Panel with Demo Tests
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security, color: Colors.red[700], size: 20),
                                SizedBox(width: 8),
                                Text('Database Demonstrations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            SizedBox(height: 16),
                            
                            Row(
                              children: [
                                Expanded(child: ActionButton(
                                  text: 'Security Tests',
                                  onPressed: _runSecurityTests,
                                  color: Colors.red[700]!,
                                  icon: Icons.shield,
                                )),
                                SizedBox(width: 8),
                                Expanded(child: ActionButton(
                                  text: _realTimeMode ? 'Stop Real-Time' : 'Real-Time Test',
                                  onPressed: _startRealTimeTest,
                                  color: _realTimeMode ? Colors.orange[700]! : Colors.green[700]!,
                                  icon: _realTimeMode ? Icons.stop : Icons.speed,
                                  isActive: _realTimeMode,
                                )),
                              ],
                            ),
                            SizedBox(height: 12),
                            
                            Row(
                              children: [
                                Expanded(child: ActionButton(
                                  text: 'Basic Stress',
                                  onPressed: _runConcurrencyTest,
                                  color: Colors.purple[700]!,
                                  icon: Icons.fitness_center,
                                )),
                                SizedBox(width: 8),
                                Expanded(child: ActionButton(
                                  text: 'Optimized 🚀',
                                  onPressed: _runOptimizedConcurrencyTest,
                                  color: Colors.green[700]!,
                                  icon: Icons.rocket_launch,
                                )),
                              ],
                            ),
                            SizedBox(height: 12),
                            
                            SizedBox(
                              width: double.infinity,
                              child: ActionButton(
                                text: '💀 EXTREME STRESS (10K ops)',
                                onPressed: _runExtremeStressTest,
                                color: Colors.red[900]!,
                                icon: Icons.warning,
                              ),
                            ),
                            SizedBox(height: 12),
                            
                            SizedBox(
                              width: double.infinity,
                              child: ActionButton(
                                text: '🔍 Secondary Indexes',
                                onPressed: () async {
                                  final logs = await DatabaseService.runSecondaryIndexTest();
                                  logs.forEach(_addLog);
                                },
                                color: Colors.indigo[700]!,
                                icon: Icons.search,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Console Output
                  ConsoleWidget(
                    logs: _logs,
                    onClear: _clearLogs,
                  ),
                ],
              ),
            ),
    );
  }
}