import 'package:flutter/material.dart';
import '../models/test_profile.dart';
import '../models/test_result.dart';
import '../engine/pull_down_analyzer.dart';
import '../services/ble_service_interface.dart';
import '../services/mock_ble_service.dart';
import '../services/wellington_ble_service.dart';
import 'test_report_screen.dart';

class HomeScreen extends StatefulWidget {
  final IBleService initialBleService;

  const HomeScreen({super.key, required this.initialBleService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _serialController = TextEditingController(text: 'GEL-BR-2026-904');
  final _modelController = TextEditingController(text: 'Expositor Vertical 400L');
  final _technicianController = TextEditingController(text: 'Carlos Inspetor');
  
  TestProfile _selectedProfile = TestProfile.defaultProfiles.first;
  bool _isLoading = false;
  String _statusText = 'Pronto para leitura';

  late IBleService _currentBleService;
  bool _useRealBle = false;

  @override
  void initState() {
    super.initState();
    _currentBleService = widget.initialBleService;
  }

  void _toggleBleMode(bool isReal) {
    setState(() {
      _useRealBle = isReal;
      _currentBleService = isReal ? WellingtonBleService() : MockBleService();
    });
  }

  void _runOfflineAudit() async {
    setState(() {
      _isLoading = true;
      _statusText = _useRealBle 
          ? 'Buscando sensor Wellington/AoFrio via Bluetooth...' 
          : 'Conectando ao simulador AoFrio...';
    });

    try {
      if (_useRealBle) {
        // Modo Real BLE: escaneia e conecta ao primeiro Wellington Monitor encontrado
        final devicesStream = _currentBleService.scanForDevices();
        final devices = await devicesStream.first.timeout(
          const Duration(seconds: 8),
          onTimeout: () => [],
        );

        if (devices.isEmpty) {
          throw Exception('Nenhum sensor Wellington/AoFrio encontrado próximo. Certifique-se de que o Bluetooth do iPhone está ativo e o sensor ligado.');
        }

        final targetDevice = devices.first;
        setState(() {
          _statusText = 'Conectado a ${targetDevice.name}. Baixando histórico SCS...';
        });

        await _currentBleService.connect(targetDevice.id);
      } else {
        // Modo Simulação
        await _currentBleService.connect('MOCK-DEVICE');
      }

      setState(() {
        _statusText = 'Baixando histórico da memória interna...';
      });

      // Baixa as leituras armazenadas na memória do sensor
      final readings = await _currentBleService.downloadStoredHistory();

      setState(() {
        _statusText = 'Processando curva térmica e calculando pull-down...';
      });

      // Executa o algoritmo de aprovação adaptativo
      final result = PullDownAnalyzer.analyze(
        serialNumber: _serialController.text.trim(),
        modelName: _modelController.text.trim(),
        technicianName: _technicianController.text.trim(),
        profile: _selectedProfile,
        readings: readings,
      );

      await _currentBleService.disconnect();

      if (!mounted) return;

      // Abre a tela com o laudo completo
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TestReportScreen(result: result),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aviso do ensaio: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = 'Pronto para leitura';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMock = !_useRealBle && _currentBleService is MockBleService;
    final mockService = isMock ? _currentBleService as MockBleService : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ensaio de Geladeiras'),
        elevation: 2,
        backgroundColor: const Color(0xFF141220),
        foregroundColor: Colors.white,
        actions: [
          // Switch de Modo Simulação vs Real BLE
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(
                  _useRealBle ? Icons.bluetooth_audio : Icons.science,
                  size: 18,
                  color: _useRealBle ? Colors.cyanAccent : Colors.purpleAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  _useRealBle ? 'BLE Real' : 'Simulador',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Switch(
                  value: _useRealBle,
                  activeColor: Colors.cyanAccent,
                  onChanged: _isLoading ? null : _toggleBleMode,
                ),
              ],
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner de Status da Conexão
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _useRealBle ? Colors.cyan.shade900.withOpacity(0.2) : Colors.purple.shade900.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _useRealBle ? Colors.cyan.shade700 : Colors.purple.shade700,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _useRealBle ? Icons.bluetooth : Icons.devices,
                    color: _useRealBle ? Colors.cyanAccent : Colors.purpleAccent,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _useRealBle 
                              ? 'Sensor Wellington/AoFrio BLE Ativo' 
                              : 'Modo Simulação Ativo (Sem Hardware)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _useRealBle 
                              ? 'O app escutará o rádio Bluetooth e descarregará a memória flash SCS.'
                              : 'Permite testar o fluxo de aprovação e relatórios sem o sensor físico.',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Identificação do Ativo
            const Text('Identificação do Equipamento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            TextField(
              controller: _serialController,
              decoration: const InputDecoration(
                labelText: 'Patrimônio / Nº de Série',
                prefixIcon: Icon(Icons.qr_code_scanner),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Modelo da Geladeira',
                prefixIcon: Icon(Icons.kitchen),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _technicianController,
              decoration: const InputDecoration(
                labelText: 'Técnico / Inspetor',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Perfil de Teste (Set-Point e Diferencial)
            const Text('Parâmetros do Ensaio Térmico', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            DropdownButtonFormField<TestProfile>(
              value: _selectedProfile,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: TestProfile.defaultProfiles.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text('${p.name} • Set: ${p.targetTemperature}°C'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedProfile = val);
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tempo de teste: Calculado automaticamente pelas normas ISO/ASHRAE para gabinete vazio.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade300),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Botão Principal de Download e Avaliação
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _runOfflineAudit,
              icon: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.bolt, size: 26),
              label: Text(
                _isLoading ? _statusText : 'BAIXAR HISTÓRICO E GERAR LAUDO',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: _useRealBle ? Colors.teal.shade700 : Colors.deepPurple.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            if (isMock) ...[
              const SizedBox(height: 28),
              const Divider(),
              const Text('Cenários para Validação (Simulador)', 
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Aprovada (55 min)'),
                    selected: mockService!.currentScenario == MockScenario.refrigeratorPass,
                    onSelected: (_) => setState(() => mockService.currentScenario = MockScenario.refrigeratorPass),
                  ),
                  ChoiceChip(
                    label: const Text('Reprovada (Sem Gás)'),
                    selected: mockService.currentScenario == MockScenario.refrigeratorFailGas,
                    onSelected: (_) => setState(() => mockService.currentScenario = MockScenario.refrigeratorFailGas),
                  ),
                  ChoiceChip(
                    label: const Text('Choque Térmico (Porta Aberta)'),
                    selected: mockService.currentScenario == MockScenario.doorViolation,
                    onSelected: (_) => setState(() => mockService.currentScenario = MockScenario.doorViolation),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}
