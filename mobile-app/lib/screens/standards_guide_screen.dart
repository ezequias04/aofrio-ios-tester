import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StandardsGuideScreen extends StatelessWidget {
  const StandardsGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guia de Normas & Ensaios'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Banner de Introdução
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.ocean.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.ocean.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_outlined, color: AppColors.ocean, size: 28),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Metodologia de Qualificação ISO Test',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.ink,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Este sistema automatiza os ensaios térmicos de pull-down para refrigeradores comerciais, integrando os requisitos da ABNT NBR ISO 23953 e as especificações mundiais de engarrafadores (The Coca-Cola Company e Ambev).',
                                style: TextStyle(fontSize: 13, color: AppColors.slate, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Seção 1: Início do Teste (T0) e Auditoria
                  _GuideCard(
                    title: '1. O Ponto Exato de Início (T0) e Auditoria',
                    icon: Icons.timer_outlined,
                    badgeText: 'Auditabilidade',
                    badgeColor: AppColors.ocean,
                    content: '''
O ensaio de pull-down avalia a capacidade do refrigerador de sair do repouso térmico e alcançar a temperatura de conservação. Para evitar fraudes ou ensaios inválidos, o ponto de início (T0) é auditado por 3 condições simultâneas:

• Baseline Térmico (Gabinete Quente): O ensaio só tem validade oficial se partir de temperatura ambiente (mínimo de 24°C para bebidas positivas, 22°C para cervejeiras e 20°C para freezers). Se o refrigerador estiver pré-resfriado, o app emite alerta de não-conformidade.
• Intertravamento de Porta: O sensor AoFrio (MON1-001) audita que a porta foi devidamente fechada no início.
• Inflexão Frigorífica (dT/dt): O ponto T0 é cravado no segundo exato em que o compressor entra em operação e a temperatura inicia queda contínua (mínimo de -0,15°C/min por 3 minutos consecutivos).
• Hash Criptográfico (SHA-256): Todas as séries temporais recebem assinatura digital para comprovar a integridade dos dados perante auditorias de qualidade.
''',
                  ),
                  const SizedBox(height: 16),

                  // Seção 2: Padrão Coca-Cola (KORE / Bottler Spec)
                  _GuideCard(
                    title: '2. Padrão Coca-Cola (KORE / Bottler Spec)',
                    icon: Icons.local_drink_outlined,
                    badgeText: 'Bebidas Positivas',
                    badgeColor: const Color(0xFFE11D48),
                    content: '''
Norma de engenharia adotada pelos engarrafadores da Coca-Cola (FEMSA, Andina, Solar, Simões):

• Faixa Alvo de Conservação: +2,0°C a +4,0°C (Setpoint ideal: +3,0°C / 38°F).
• Tempo Limite de Pull-Down:
  - Expositores 1 Porta (300L a 450L): até 180 minutos (3 horas).
  - Expositores 2 Portas (800L a 1000L): até 240 minutos (4 horas).
• Regra Mandatória de Segurança: É estritamente proibido que a temperatura caia abaixo de 0°C. O congelamento pode estourar latas e garrafas de vidro, gerando perda de lote e acidentes.
• Posicionamento do Sensor: O sensor AoFrio deve ser posicionado na prateleira central, no terço médio do gabinete, sem tocar na saída de ar direto do evaporador.
''',
                  ),
                  const SizedBox(height: 16),

                  // Seção 3: Padrão Cervejeira Sub-Zero
                  _GuideCard(
                    title: '3. Padrão Cervejeira Sub-Zero (Ambev / Heineken)',
                    icon: Icons.sports_bar_outlined,
                    badgeText: 'Sub-Zero',
                    badgeColor: const Color(0xFFD97706),
                    content: '''
Especificação para expositores cervejeiros de alta performance:

• Ponto de Congelamento da Cerveja: Devido ao teor alcoólico (4,5% a 6%), a cerveja congela entre -2,3°C e -2,8°C.
• Faixa Alvo de Consumo: -2,0°C a -4,0°C (ponto "canela de pedreiro").
• Tempo Limite de Pull-Down: até 240 minutos (4 horas) partindo de 25°C.
• Proteção de Ar Insuflado: O ar de retorno e insuflamento não pode atingir menos de -5,0°C por períodos prolongados para evitar o congelamento do líquido dentro das garrafas.
''',
                  ),
                  const SizedBox(height: 16),

                  // Seção 4: Padrão Freezer Negativo / Sorvetes
                  _GuideCard(
                    title: '4. Freezer Negativo / Sorvetes (ISO L1/L2)',
                    icon: Icons.ac_unit_outlined,
                    badgeText: 'Congelados',
                    badgeColor: const Color(0xFF0284C7),
                    content: '''
Para conservadores de gelo, polpas, carnes e sorvetes:

• Faixa Alvo: -18,0°C a -22,0°C (Classe ISO L1 / L2).
• Tempo Limite de Pull-Down: até 360 minutos (6 horas) em ambiente de 25°C.
• Critério de Estabilização: Manutenção de temperatura abaixo de -15°C por pelo menos 30 minutos ininterruptos de ciclagem.
''',
                  ),
                  const SizedBox(height: 16),

                  // Seção 5: Resiliência Offline e Hardware AoFrio
                  _GuideCard(
                    title: '5. Funcionamento Offline e Proteção de Dados',
                    icon: Icons.offline_bolt_outlined,
                    badgeText: 'Offline-First',
                    badgeColor: AppColors.success,
                    content: '''
Como o sistema se comporta diante de falhas operacionais:

• Sensor Datalogger Autônomo: O sensor Wellington AoFrio (MON1-001) possui bateria própria e memória flash não-volátil. Ele continua medindo e gravando as leituras mesmo se o celular descarregar, fechar o app ou perder o Bluetooth.
• Reconstituição de Histórico: Ao reabrir o app, o sistema faz o download de toda a memória flash do sensor, preenchendo os pontos térmicos sem lacunas.
• Sem Dependência de Internet: Todos os ensaios, gráficos e laudos em PDF são processados 100% offline no celular. A sincronização com a nuvem ocorre em segundo plano quando houver conexão Wi-Fi.
''',
                  ),
                  const SizedBox(height: 32),

                  // Botão de retorno
                  Center(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      ),
                      child: const Text('Voltar à Bancada de Testes'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String badgeText;
  final Color badgeColor;
  final String content;

  const _GuideCard({
    required this.title,
    required this.icon,
    required this.badgeText,
    required this.badgeColor,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: badgeColor.withValues(alpha: 0.12),
                  child: Icon(icon, color: badgeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.ink),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              content.trim(),
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}
