import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state/bench_controller.dart';
import '../theme/app_theme.dart';

/// Pede nome e matrícula de quem está realizando os testes. Com [required]
/// o diálogo não fecha sem preencher (primeiro uso do aparelho).
/// Devolve true se a identificação foi salva.
Future<bool> showIdentityDialog(
  BuildContext context,
  BenchController controller, {
  bool required = false,
}) async {
  final nameCtrl = TextEditingController(text: controller.lastTechnicianName);
  final badgeCtrl = TextEditingController(text: controller.technicianBadge);
  final pinCtrl = TextEditingController();
  final pin2Ctrl = TextEditingController();
  String? error;

  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: !required,
    builder: (dialogContext) => PopScope(
      canPop: !required,
      child: StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Quem está testando?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Seu nome e matrícula ficam gravados em todos os ensaios e laudos feitos neste aparelho.',
                style: TextStyle(fontSize: 13, color: AppColors.slate),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome completo',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: badgeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Matrícula',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              _PinField(controller: pinCtrl, label: 'Crie um PIN (4 a 6 números)'),
              const SizedBox(height: 10),
              _PinField(controller: pin2Ctrl, label: 'Repita o PIN'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: AppColors.fault, fontSize: 12.5),
                  ),
                ),
            ],
          ),
          actions: [
            if (!required)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().length < 3 || badgeCtrl.text.trim().isEmpty) {
                  setDialogState(() => error = 'Informe o nome completo e a matrícula.');
                  return;
                }
                if (!RegExp(r'^\d{4,6}$').hasMatch(pinCtrl.text.trim())) {
                  setDialogState(() => error = 'O PIN precisa ter de 4 a 6 números.');
                  return;
                }
                if (pinCtrl.text.trim() != pin2Ctrl.text.trim()) {
                  setDialogState(() => error = 'Os dois PINs não são iguais.');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    ),
  );

  if (saved == true) {
    await controller.saveIdentity(name: nameCtrl.text, badge: badgeCtrl.text, pin: pinCtrl.text);
    return true;
  }
  return false;
}

/// Pede o PIN de quem está identificado antes de iniciar ensaio ou gerar laudo:
/// ninguém assina com o nome de outro técnico. Devolve true se o PIN confere.
Future<bool> confirmTechnicianPin(BuildContext context, BenchController controller) async {
  final pinCtrl = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Confirme com seu PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              controller.technicianLabel,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink),
            ),
            const SizedBox(height: 12),
            _PinField(controller: pinCtrl, label: 'PIN', autofocus: true),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: AppColors.fault, fontSize: 13)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!controller.checkPin(pinCtrl.text)) {
                setDialogState(() => error = 'PIN incorreto. Se não é você, troque o técnico em Normas.');
                return;
              }
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  const _PinField({required this.controller, required this.label, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
      ),
    );
  }
}
