# AoFrio Refrigeration Testing System (Sistema de Ensaio Pull-Down)

Sistema automatizado de qualificação térmica e ensaios de refrigeração industrial para equipamentos comerciais (geladeiras, cervejeiras, freezers e câmaras frias) utilizando o datalogger **AoFrio Monitor (Bluetooth BLE)**.

---

## 🎯 Objetivo Principal

Permitir que técnicos e inspetores de qualidade testem refrigeradores **sem depender de celular conectado durante o ensaio**:
1. O técnico coloca o sensor AoFrio dentro da geladeira desligada ou em temperatura ambiente.
2. Fecha a porta e liga a geladeira.
3. O sensor registra de forma 100% autônoma a temperatura minuto a minuto, vibração do compressor e aberturas de porta.
4. Horas depois (ou no dia seguinte), o técnico abre o **App Móvel Nativo**, aproxima-se do equipamento e clica em **"Baixar Dados"**.
5. Em 5 a 10 segundos, o app baixa a memória interna do sensor, executa o **Algoritmo de Auditoria Pull-Down** e exibe imediatamente o laudo: **APROVADA** ou **REPROVADA**.
6. O laudo é sincronizado com o **Portal Web**, onde gerentes e clientes acessam relatórios gerenciais, gráficos completos e certificados em PDF.

---

## 🏗 Arquitetura do Sistema

```
┌─────────────────────────────────────────────────────────────┐
│ 1. HARDWARE: AoFrio Monitor                                 │
│    - Datalogger autônomo com memória flash para 2 meses.    │
│    - Grava Temperatura, Vibração do Compressor e Porta.     │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Download via Bluetooth BLE)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. APP MOBILE NATIVO (Flutter - Android / iOS)              │
│    - Uso exclusivo de técnicos de campo e bancada.          │
│    - Executa o Algoritmo de Pull-Down OFFLINE no celular.   │
│    - Mostra veredito (APROVADA / REPROVADA) na hora.        │
│    - Possui MOCK BLE para testes antes do sensor chegar.    │
└──────────────────────────────┬──────────────────────────────┘
                               │ (Sync via REST API / JSON)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. BACKEND API (Node.js / Express / SQLite)                 │
│    - Recebe laudos e séries temporais do App Mobile.        │
│    - Armazena histórico centralizado de todos os ensaios.   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. PORTAL WEB DE RELATÓRIOS (HTML5 / Tailwind / Chart.js)   │
│    - Acesso de qualquer navegador PC/Tablet.                │
│    - Apenas consulta e visualização de resultados.          │
│    - Busca por Nº de Série, Modelo e Data.                  │
│    - Gráficos de auditoria térmica e emissão de PDF.        │
└─────────────────────────────────────────────────────────────┘
```

---

## 📂 Estrutura de Pastas

* [`specs/`](specs/): Especificações técnicas do algoritmo, engenharia reversa do AoFrio BLE e esquemas de API.
  * [`algorithm_specification.md`](specs/algorithm_specification.md): Fórmulas matemáticas do ensaio pull-down.
  * [`aofrio_ble_specs.md`](specs/aofrio_ble_specs.md): Mapeamento de serviços GATT e protocolo BLE da AoFrio.
  * [`api_schema.json`](specs/api_schema.json): Estrutura de dados dos laudos.
* [`mobile-app/`](mobile-app/): Código-fonte completo do Aplicativo Móvel Flutter.
  * Inclui `MockBleService` com cenários pré-programados (Aprovado, Falha de Gás, Porta Aberta).
  * Inclui `AoFrioBleService` pronto para conexão com o hardware real.
* [`backend-api/`](backend-api/): API REST Node.js para receber e servir os laudos.
* [`web-dashboard/`](web-dashboard/): Painel Web de relatórios pronto para uso, visualização de gráficos e exportação de PDF.
* [`AGENT_EXECUTION_PLAN.md`](AGENT_EXECUTION_PLAN.md): **Guia mestre passo a passo para qualquer outro agente de IA ou desenvolvedor dar continuidade e executar o projeto.**

---

## 🚀 Como Testar Imediatamente (Mesmo sem o Sensor Físico)

### 1. Testar o Painel Web de Relatórios:
Abra o arquivo [`web-dashboard/index.html`](web-dashboard/index.html) diretamente no seu navegador Google Chrome ou Edge. Ele já vem com dados simulados interativos, filtros e gerador de PDF.

### 2. Testar o Backend API:
```bash
cd backend-api
npm install
npm start
```
A API iniciará em `http://localhost:3000`.

### 3. Rodar o App Mobile (Flutter):
```bash
cd mobile-app
flutter pub get
flutter run
```
No app móvel, utilize o botão **"Alternar Modo Simulação"** para testar os 3 cenários de teste enquanto aguarda o hardware físico AoFrio chegar.
