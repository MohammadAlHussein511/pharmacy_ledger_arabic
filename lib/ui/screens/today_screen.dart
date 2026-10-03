import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../day_clock.dart';
import 'day_view.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final today = context.watch<DayClock>().today;
    return Scaffold(
      // [تم التعديل] - ترجمة عنوان الشاشة
      appBar: AppBar(title: const Text('اليوم')),
      body: SafeArea(child: DayView(day: today)),
    );
  }
}