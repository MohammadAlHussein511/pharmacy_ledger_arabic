import 'package:flutter/material.dart';

import 'settings_screen.dart';

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
              leading: const Icon(Icons.info_outline),
              title: const Text('عن التطبيق'),
              subtitle: const Text('الإصدار 2.2.0'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'دفتر الصيدلية',
                  applicationVersion: '2.2.0',
                  applicationLegalese: '© 2026 — جميع الحقوق محفوظة',
                  children: [
                    const SizedBox(height: 12),
                    const Text(
                      'تطبيق لإدارة مبيعات ومدفوعات الصيدلية\n'
                      'مع مزامنة سحابية آمنة بين أجهزة العمل.\n\n'
                      'الميزات:\n'
                      '• المبيعات والمدفوعات بعملات متعددة\n'
                      '• فواتير المستودعات مع صرف تلقائي\n'
                      '• ديون الصيدليات بالأدوية\n'
                      '• تقارير يومية/أسبوعية/شهرية/سنوية\n'
                      '• نسخ احتياطي مشفر\n'
                      '• قفل التطبيق بـ PIN وبصمة',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('الإعدادات'),
              subtitle: const Text('الحساب، الأمان، المزامنة'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}