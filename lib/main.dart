import 'package:flutter/material.dart';
import 'screens/accounts_list_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HZZO Saldo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005BAA)),
        useMaterial3: true,
      ),
      home: const AccountsListScreen(),
    );
  }
}
