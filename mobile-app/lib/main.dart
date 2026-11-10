import 'package:flutter/material.dart';
import 'services/mock_ble_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicia com o MockBleService por padrão
  // O usuário pode alternar em tempo real no app para WellingtonBleService
  final bleService = MockBleService();

  runApp(AoFrioTestingApp(bleService: bleService));
}

class AoFrioTestingApp extends StatelessWidget {
  final MockBleService bleService;

  const AoFrioTestingApp({super.key, required this.bleService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AoFrio Pull-Down Tester',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF06B6D4),
          surface: Color(0xFF181622),
        ),
      ),
      home: HomeScreen(initialBleService: bleService),
    );
  }
}
