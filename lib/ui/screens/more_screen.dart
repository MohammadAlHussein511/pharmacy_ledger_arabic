import 'package:flutter/material.dart';

import 'warehouses_screen.dart';
import 'weeks_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('تقرير الأسابيع'),
              subtitle: const Text('مبيعات ومدفوعات كل أسبوع (سبت → جمعة)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const WeeksScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.warehouse_outlined),
              title: const Text('المستودعات'),
              subtitle: const Text('إضافة وتعديل المستودعات'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const WarehousesScreen(standalone: true)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}