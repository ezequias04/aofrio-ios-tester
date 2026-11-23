import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import 'commissioning_wizard_screen.dart';
import 'tabs/bench_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/sensors_tab.dart';
import 'tabs/standards_tab.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;

  void _openWizard({String? preselectedSensorId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CommissioningWizardScreen(preselectedSensorId: preselectedSensorId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = BenchScope.of(context);
    final activeCount = controller.activeSessions.length;
    final sensorCount = controller.discoveredSensors.length;
    final reportCount = controller.savedReports.length;

    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: [
          BenchTab(
            onStartNewDiagnostic: () => _openWizard(),
            onGoToSensors: () => setState(() => _tabIndex = 1),
          ),
          SensorsTab(
            onBindSensor: (sensorId) =>
                _openWizard(preselectedSensorId: sensorId),
            onOpenBench: () => setState(() => _tabIndex = 0),
          ),
          const ReportsTab(),
          const StandardsTab(),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openWizard(),
              backgroundColor: AppColors.indigo,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text(
                'Novo Diagnóstico',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _tabIndex,
          onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
          destinations: [
            NavigationDestination(
              icon: _CountBadge(
                count: activeCount,
                color: AppColors.indigo,
                child: const Icon(Icons.dashboard_outlined),
              ),
              selectedIcon: _CountBadge(
                count: activeCount,
                color: AppColors.indigo,
                child: const Icon(Icons.dashboard_rounded),
              ),
              label: 'Bancada',
            ),
            NavigationDestination(
              icon: _CountBadge(
                count: sensorCount,
                color: AppColors.cryo,
                child: const Icon(Icons.sensors_outlined),
              ),
              selectedIcon: _CountBadge(
                count: sensorCount,
                color: AppColors.cryo,
                child: const Icon(Icons.sensors_rounded),
              ),
              label: 'Sensores',
            ),
            NavigationDestination(
              icon: _CountBadge(
                count: reportCount,
                color: AppColors.approved,
                child: const Icon(Icons.assignment_outlined),
              ),
              selectedIcon: _CountBadge(
                count: reportCount,
                color: AppColors.approved,
                child: const Icon(Icons.assignment_rounded),
              ),
              label: 'Laudos',
            ),
            const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'Normas',
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final Widget child;

  const _CountBadge({
    required this.count,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Badge(
      backgroundColor: color,
      label: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
      child: child,
    );
  }
}
