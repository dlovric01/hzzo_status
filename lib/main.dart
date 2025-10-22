import 'package:flutter/material.dart';
import 'package:hzzo_saldo/hzzo_status_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HZZO Status',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005BAA)),
        useMaterial3: true,
      ),
      home: const HzzoStatusScreen(),
    );
  }
}
