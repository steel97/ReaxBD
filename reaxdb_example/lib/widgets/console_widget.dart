import 'package:flutter/material.dart';

class ConsoleWidget extends StatelessWidget {
  final List<String> logs;
  final VoidCallback onClear;

  const ConsoleWidget({
    Key? key,
    required this.logs,
    required this.onClear,
  }) : super(key: key);

  Color _getLogColor(String log) {
    if (log.contains('❌') || log.contains('Error') || log.contains('FAILED')) {
      return Colors.red[300]!;
    } else if (log.contains('⚠️') || log.contains('WARNING')) {
      return Colors.orange[300]!;
    } else if (log.contains('✅') || log.contains('PASSED')) {
      return Colors.green[300]!;
    } else if (log.contains('📊') || log.contains('📝')) {
      return Colors.blue[300]!;
    } else if (log.contains('🔒') || log.contains('🔐') || log.contains('🚀')) {
      return Colors.purple[300]!;
    } else if (log.contains('⚡')) {
      return Colors.yellow[300]!;
    }
    return Colors.green[300]!;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      height: 400,
      child: Card(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.terminal, color: Colors.green[400], size: 20),
                  SizedBox(width: 8),
                  Text('ReaxDB Console', style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold, 
                    color: Colors.white
                  )),
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[600],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${logs.length} logs', style: TextStyle(
                      color: Colors.white, 
                      fontSize: 12,
                      fontWeight: FontWeight.bold
                    )),
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    onPressed: onClear,
                    icon: Icon(Icons.clear_all, color: Colors.white),
                    tooltip: 'Clear logs',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: logs.isEmpty 
                    ? Center(
                        child: Text(
                          'No logs yet. Run some tests to see output.',
                          style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          return Container(
                            margin: EdgeInsets.only(bottom: 2),
                            child: Text(
                              log,
                              style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 11,
                                color: _getLogColor(log),
                                height: 1.3,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}