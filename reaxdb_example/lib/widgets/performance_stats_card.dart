import 'package:flutter/material.dart';

class PerformanceStatsCard extends StatelessWidget {
  final int totalOperations;
  final int successfulOperations;
  final List<int> latencies;

  const PerformanceStatsCard({
    Key? key,
    required this.totalOperations,
    required this.successfulOperations,
    required this.latencies,
  }) : super(key: key);

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final avgLatency = latencies.isEmpty 
        ? '0μs' 
        : '${(latencies.reduce((a, b) => a + b) / latencies.length).toStringAsFixed(1)}μs';
    
    return Container(
      margin: EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildStatItem('Total Ops', totalOperations.toString(), Icons.trending_up, Colors.blue),
              ),
              Expanded(
                child: _buildStatItem('Success', successfulOperations.toString(), Icons.check_circle, Colors.green),
              ),
              Expanded(
                child: _buildStatItem('Avg Latency', avgLatency, Icons.speed, Colors.orange),
              ),
            ],
          ),
        ),
      ),
    );
  }
}