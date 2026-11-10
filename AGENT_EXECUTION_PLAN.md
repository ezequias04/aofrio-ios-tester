# GUIA DE EXECUÇÃO PARA AGENTE DE IA (AGENT EXECUTION PLAN)

> **Instrução ao Agente:** Você é o engenheiro responsável por implementar, validar ou expandir o sistema **AoFrio Refrigeration Testing System**. Leia este documento na íntegra antes de realizar modificações no código.

---

## 🎯 Missão do Projeto
Construir uma solução completa e desacoplada em duas frentes:
1. **App Mobile Nativo (Flutter):** Ferramenta de bancada/campo usada por técnicos. Não depende de celular durante o teste da geladeira. Lê a memória interna gravada pelo sensor AoFrio Monitor via Bluetooth BLE, roda o algoritmo de aprovação de ensaio de pull-down offline e exibe o veredito instantâneo.
2. **Portal Web de Relatórios:** Aplicação web estritamente de consulta, filtros de auditoria, visualização gráfica da curva térmica e emissão de certificados de conformidade em PDF.

---

## 📋 Checklist de Execução por Fases

### Fase 1: Entendimento do Algoritmo e Regras de Negócio
- [ ] Ler [`specs/algorithm_specification.md`](specs/algorithm_specification.md).
- [ ] Entender os 3 critérios de veredito:
  1. **Tempo de Pull-Down ($t \le t_{\text{max}}$):** Tempo da $T_{\text{inicial}}$ até atingir $T_{\text{alvo}}$.
  2. **Taxa de Descida Inicial:** Verificar se após os primeiros 15 minutos o compressor realmente baixou a temperatura em ao menos $1.5^\circ\text{C}$ (detecção precoce de falha de relé/partida).
  3. **Validação de Integridade do Ensaio:** Checagem de aberturas de porta gravadas pelo acelerômetro/sensor magnético do AoFrio. Se a porta foi aberta durante o resfriamento, o teste deve ser sinalizado com advertência ou invalidado.

### Fase 2: Implementação e Testes do App Mobile (SwiftUI Nativo — iOS Only)
- [ ] Verificar a pasta [`mobile-app/`](mobile-app/).
- [ ] Analisar o modelo de dados [`lib/models/sensor_reading.dart`](mobile-app/lib/models/sensor_reading.dart) e [`lib/models/test_result.dart`](mobile-app/lib/models/test_result.dart).
- [ ] Analisar o motor do algoritmo em [`lib/engine/pull_down_analyzer.dart`](mobile-app/lib/engine/pull_down_analyzer.dart).
- [ ] **Modo Simulação (Mock):** Usar [`lib/services/mock_ble_service.dart`](mobile-app/lib/services/mock_ble_service.dart) para executar testes unitários dos 3 cenários:
  - *Cenário A:* Geladeira em perfeito estado (Aprovada em 55 min).
  - *Cenário B:* Geladeira com vazamento de fluido/compressor fraco (Reprovada por tempo estourado).
  - *Cenário C:* Geladeira aberta indevidamente durante o ensaio (Alerta de porta).
- [ ] **Integração Real Bluetooth (Hardware):** Quando o sensor físico estiver disponível:
  - Seguir as orientações de [`specs/aofrio_ble_specs.md`](specs/aofrio_ble_specs.md).
  - Inspecionar UUIDs com o app nRF Connect.
  - Plugar os UUIDs descobertos em [`lib/services/aofrio_ble_service.dart`](mobile-app/lib/services/aofrio_ble_service.dart).

### Fase 3: Backend API e Persistência
- [ ] Verificar a pasta [`backend-api/`](backend-api/).
- [ ] Instalar dependências: `cd backend-api && npm install`.
- [ ] Rodar o servidor: `npm start`.
- [ ] Testar os endpoints definidos em [`specs/api_endpoints.md`](specs/api_endpoints.md):
  - `POST /api/tests`: Recebe laudo completo enviado pelo App Móvel.
  - `GET /api/tests`: Lista todos os testes com filtros (`serialNumber`, `status`, `dataInicio`).
  - `GET /api/tests/:id`: Retorna detalhes e a série temporal para plotar o gráfico.

### Fase 4: Portal Web de Relatórios
- [ ] Abrir [`web-dashboard/index.html`](web-dashboard/index.html).
- [ ] Garantir que o painel consome a API do Backend quando disponível, ou use o modo demonstração embutido caso o backend esteja offline.
- [ ] Testar a exportação de PDF usando `window.print()` estilizado com `@media print`.

---

## 🛠 Comandos Úteis para o Agente

### Executar o Backend:
```bash
cd C:\Users\PEREIRA\Desktop\AoFrio-Refrigeration-Testing-System\backend-api
npm install
node src/server.js
```

### Rodar Testes de Algoritmo no Mobile:
```bash
cd C:\Users\PEREIRA\Desktop\AoFrio-Refrigeration-Testing-System\mobile-app
dart run lib/engine/pull_down_analyzer.dart
```

---

## ⚠️ Regras e Restrições Obrigatórias
1. **O App Mobile NÃO pode ser Web:** Ele deve ser um aplicativo nativo compilado (Android/iOS) para garantir acesso a APIs Bluetooth de baixo nível e operação 100% offline em locais sem sinal de internet (galpões industriais, docas, oficinas).
2. **O Portal Web NÃO executa o teste:** A página web serve unicamente para consulta gerencial, dashboards de auditoria e impressão de laudos por supervisores e clientes.
3. **Não alterar a fórmula do Pull-Down sem consentimento:** A taxa de queda e limites de tempo respeitam normas de qualificação de refrigeração comercial (padrão ISO/ASHRAE e boas práticas HACCP).
