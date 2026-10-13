import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services.dart';
import 'invoices_screen.dart';
import 'pharmacy_debts_screen.dart';

/// شاشة الحسابات: تبويبان (الفواتير / ديون الصيدليات) مع ملخص سريع.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الحسابات'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(
                icon: Icon(Icons.receipt_long_outlined),
                text: 'فواتير المستودعات'),
            Tab(icon: Icon(Icons.local_pharmacy_outlined), text: 'ديون الصيدليات'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          InvoicesScreen(),
          PharmacyDebtsScreen(),
        ],
      ),
    );
  }
}