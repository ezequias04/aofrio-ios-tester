import 'package:flutter/material.dart';
import 'screens/app_shell.dart';
import 'state/bench_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IsoTestApp());
}

/// Provê o [BenchController] para toda a árvore de telas.
class BenchScope extends InheritedNotifier<BenchController> {
  const BenchScope({
    super.key,
    required BenchController controller,
    required super.child,
  }) : super(notifier: controller);

  static BenchController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BenchScope>();
    assert(scope != null, 'BenchScope não encontrado na árvore de widgets.');
    return scope!.notifier!;
  }
}

class IsoTestApp extends StatefulWidget {
  const IsoTestApp({super.key});

  @override
  State<IsoTestApp> createState() => _IsoTestAppState();
}

class _IsoTestAppState extends State<IsoTestApp> {
  final BenchController _controller = BenchController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BenchScope(
      controller: _controller,
      child: MaterialApp(
        title: 'ISO Test',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        themeMode: ThemeMode.light,
        home: const AppShell(),
      ),
    );
  }
}
