import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/test_profile.dart';
import '../../theme/app_theme.dart';
import '../../widgets/identity_dialog.dart';

class StandardsTab extends StatefulWidget {
  const StandardsTab({super.key});

  @override
  State<StandardsTab> createState() => _StandardsTabState();
}

class _StandardsTabState extends State<StandardsTab> {
  @override
  Widget build(BuildContext context) {
    final controller = BenchScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Normas & Diagnóstico'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            const _SectionHeader(
              title: 'Perfis de teste (pull-down em campo)',
              subtitle:
                  'Limites de aprovação, tempos máximos e travas anticongelamento adotadas no sistema.',
            ),
            const SizedBox(height: 10),
            ...TestProfile.defaultProfiles.map(
              (profile) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProfileNormCard(profile: profile),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionHeader(
              title: 'Como o Diagnóstico Identifica Falhas',
              subtitle:
                  'O algoritmo cruza a curva térmica T0→Meta com assinaturas conhecidas de defeitos frigoríficos.',
            ),
            const SizedBox(height: 10),
            const _FaultGuideCard(
              icon: Icons.bolt_rounded,
              color: AppColors.fault,
              title: 'Falha de Partida / Compressor (0–15 min)',
              description:
                  'Se nos primeiros 15 minutos após T0 a temperatura cair menos que o mínimo exigido (ex.: < 1,5°C), indica relé PTC, capacitor, protetor térmico aberto, termostato sem saída ou compressor sem compressão.',
            ),
            const SizedBox(height: 8),
            const _FaultGuideCard(
              icon: Icons.opacity_rounded,
              color: AppColors.warning,
              title: 'Baixa Eficiência / Carga de Gás',
              description:
                  'O equipamento resfria devagar e estabiliza longe da meta sem atingir o setpoint no tempo limite. Indica microvazamento de gás, capilar/filtro obstruído ou condensador sujo.',
            ),
            const SizedBox(height: 8),
            const _FaultGuideCard(
              icon: Icons.ac_unit_rounded,
              color: AppColors.indigo,
              title: 'Estagnação / Bloqueio ou Vedação',
              description:
                  'A temperatura inicia a queda bem mas para no meio e volta a subir (+1,5°C acima da mínima). Sinal clássico de evaporador bloqueado por gelo, ventilador parado, gaxeta com infiltração ou desarme térmico.',
            ),
            const SizedBox(height: 8),
            const _FaultGuideCard(
              icon: Icons.thermostat_rounded,
              color: AppColors.cryo,
              title: 'Falha de Corte (Congelamento)',
              description:
                  'Em expositores positivos Coca-Cola (< 0°C) ou cervejeiras (< -5°C), violar o limite mínimo indica relé do controlador colado ou sonda NTC descalibrada.',
            ),
            const SizedBox(height: 18),
            const _SectionHeader(
              title: 'Auditoria T0 & Resiliência do Sensor',
              subtitle:
                  'Segurança contra ensaios viciados e proteção de dados offline.',
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BulletInfo(
                      icon: Icons.verified_user_outlined,
                      title: 'Auditoria de Partida T0',
                      body:
                          'O cronômetro oficial só inicia quando você vincula o equipamento manualmente e confirma o botão Iniciar. Partidas abaixo da temperatura ambiente padrão ficam marcadas como pré-resfriadas no laudo.',
                    ),
                    const Divider(height: 22),
                    _BulletInfo(
                      icon: Icons.save_outlined,
                      title: 'Persistência Contínua + Memória Flash',
                      body:
                          'Todas as leituras da bancada são gravadas localmente em tempo real. Mesmo se o aplicativo fechar, você pode puxar o histórico da memória flash SCS do sensor MON1-001 e mesclar na sessão.',
                    ),
                    const Divider(height: 22),
                    _BulletInfo(
                      icon: Icons.screen_lock_portrait_outlined,
                      title: 'Comportamento iOS e Android',
                      body:
                          'O app mantém a tela acesa (Wakelock) enquanto houver ensaios ativos na bancada, garantindo que o iOS e o Android recebam anúncios BLE sem interrupção.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionHeader(
              title: 'Configurações do Sistema',
              subtitle:
                  'Simulador opcional de bancada.',
            ),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined,
                        color: AppColors.indigo),
                    title: const Text(
                      'Quem está testando',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    subtitle: Text(
                      controller.hasIdentity
                          ? controller.technicianLabel
                          : 'Não identificado',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: TextButton(
                      onPressed: () => showIdentityDialog(context, controller),
                      child: Text(controller.hasIdentity ? 'Trocar' : 'Informar'),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.science_rounded,
                        color: AppColors.amber),
                    title: const Text(
                      'Simulador de Bancada (Modo Demonstração)',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Gera 2 sensores virtuais (1 saudável e 1 com falha) marcados como SIMULAÇÃO para testes sem hardware.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: controller.demoModeEnabled,
                    onChanged: (v) => controller.toggleDemoMode(v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(subtitle,
            style: const TextStyle(color: AppColors.slate, fontSize: 12.5)),
      ],
    );
  }
}

class _ProfileNormCard extends StatelessWidget {
  final TestProfile profile;

  const _ProfileNormCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.indigoSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    profile.categoryTag,
                    style: const TextStyle(
                      color: AppColors.indigo,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              profile.standardName,
              style: const TextStyle(
                color: AppColors.cryo,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              profile.description,
              style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MiniTag(
                    'Faixa: ${profile.minTemperature.toStringAsFixed(1)} a ${profile.maxTemperature.toStringAsFixed(1)}°C'),
                _MiniTag('Prazo: ${profile.manualMaxAllowedMinutes ?? 180} min'),
                _MiniTag('T0 mín.: ≥ ${profile.minStartingAmbientTemp}°C'),
                if (profile.safetyMinTemperature != null)
                  _MiniTag('Corte mín.: ${profile.safetyMinTemperature}°C'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String text;
  const _MiniTag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FaultGuideCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _FaultGuideCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletInfo extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _BulletInfo({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.indigo, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(color: AppColors.slate, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
