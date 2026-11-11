import 'package:flutter/material.dart';
import 'services/mock_ble_service.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

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
      title: 'AoFrio Test',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: HomeScreen(initialBleService: bleService),
    );
  }
}
