import 'package:flutter/material.dart';
import 'screens/panel_list_screen.dart';

void main() {
  runApp(const IInteractApp());
}

class IInteractApp extends StatelessWidget {
  const IInteractApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iInteract',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF42A5F5)),
        useMaterial3: true,
      ),
      home: const PanelListScreen(),
    );
  }
}
