# iOS Starter: Estrutura Completa para Compilar na Nuvem Sem Mac
## AoFrio Pull-Down Tester — Guia de Execução para Agente

> **Template Base:** `msonrm/no-mac-ios-starter`  
> **Stack:** SwiftUI puro + CoreBluetooth + CoreNFC + Charts nativo  
> **CI/CD:** GitHub Actions (`macos-latest` runner) → TestFlight  
> **Mac Físico:** Não necessário

---

## 1. Passo 1: Criar o Repositório a Partir do Template

```bash
# 1. Acesse: https://github.com/msonrm/no-mac-ios-starter
# 2. Clique em "Use this template" → "Create a new repository"
# 3. Nome do repositório: aofrio-pulldown-ios
# 4. Clone localmente (pode ser do Windows):

git clone https://github.com/SEU_USUARIO/aofrio-pulldown-ios.git
cd aofrio-pulldown-ios
```

---

## 2. Estrutura Final de Arquivos do Projeto

```
aofrio-pulldown-ios/
│
├── .github/
│   └── workflows/
│       ├── testflight.yml           ← Deploy automático (push em main)
│       └── pr-check.yml             ← Build de validação em Pull Requests
│
├── ExportOptions.plist              ← Configuração de assinatura para App Store
│
├── AoFrioTester/
│   ├── AoFrioTesterApp.swift        ← @main entry point SwiftUI
│   ├── ContentView.swift            ← Router de navegação principal
│   │
│   ├── Models/
│   │   ├── SensorReading.swift      ← {timestamp, temperature, doorOpen, compressorOn}
│   │   ├── TestProfile.swift        ← {setPoint, differential, maxTime calculado auto}
│   │   ├── TestResult.swift         ← Laudo final com veredito + métricas
│   │   └── AssetBinding.swift       ← Vínculo Sensor AoFrio ↔ Patrimônio Geladeira
│   │
│   ├── Engine/
│   │   ├── PullDownAnalyzer.swift   ← Algoritmo central de aprovação/reprovação
│   │   ├── ThermalCalculator.swift  ← Fórmula auto do tempo limite por salto térmico
│   │   └── RecoveryEngine.swift     ← Recálculo de rota após porta aberta (choque térmico)
│   │
│   ├── Services/
│   │   ├── Protocols/
│   │   │   └── BLEServiceProtocol.swift   ← Interface IBleService (para Mock e Real)
│   │   ├── BLEService.swift               ← CoreBluetooth: scan, connect, download flash AoFrio
│   │   ├── NFCService.swift               ← CoreNFC: lê ID do sensor por toque
│   │   ├── QRScannerService.swift         ← AVFoundation: lê QR Code do patrimônio
│   │   ├── MockBLEService.swift           ← Simulador: 3 cenários (Aprovada / Reprovada / Choque)
│   │   └── APIService.swift               ← URLSession: sync do laudo para o Portal Web
│   │
│   ├── ViewModels/
│   │   ├── BindingViewModel.swift    ← Fluxo NFC + QR Code de vinculação
│   │   ├── TestViewModel.swift       ← Orquestra o download BLE + análise
│   │   └── FleetViewModel.swift      ← Lista e status de múltiplos sensores
│   │
│   ├── Views/
│   │   ├── Onboarding/
│   │   │   └── BindingView.swift     ← Tela 0: Vincular sensor NFC + QR Code patrimônio
│   │   ├── Home/
│   │   │   ├── HomeView.swift        ← Tela principal com seleção de setpoint/diferencial
│   │   │   └── ProfilePickerView.swift  ← Seletor do tipo de equipamento
│   │   ├── Dial/
│   │   │   ├── DialView.swift        ← Mostrador circular Obsidian Dark (temp atual)
│   │   │   └── DialArcShape.swift    ← SwiftUI Shape customizado para o arco neon
│   │   ├── Fleet/
│   │   │   ├── FleetView.swift       ← Lista de múltiplos sensores detectados via BLE
│   │   │   └── SensorCardView.swift  ← Card individual: Aprovada/Resfriando/Reprovada
│   │   ├── Chart/
│   │   │   └── ChartView.swift       ← Gráfico de linha da curva térmica (Swift Charts)
│   │   ├── Report/
│   │   │   ├── ReportView.swift      ← Laudo final APROVADA / REPROVADA
│   │   │   └── ReportMetricCard.swift  ← Cards de métricas individuais
│   │   └── Components/
│   │       ├── ObsidianCard.swift    ← ViewModifier estilo dark neumorphic
│   │       ├── NeonButton.swift      ← Botão central flutuante com gradiente neon
│   │       └── StatusBadge.swift     ← Badge verde/vermelho de status
│   │
│   ├── Resources/
│   │   └── Assets.xcassets/
│   │       └── AppIcon.appiconset/   ← Ícone do app (❄️ estilo cryo/tech)
│   │
│   └── Info.plist                   ← Permissões obrigatórias (BLE, NFC, Câmera)
│
├── AoFrioTesterTests/
│   ├── PullDownAnalyzerTests.swift   ← Testa os 4 critérios do algoritmo
│   ├── ThermalCalculatorTests.swift  ← Testa o cálculo automático de tempo
│   └── RecoveryEngineTests.swift     ← Testa o recálculo após choque térmico
│
└── AoFrioTester.xcodeproj/
```

---

## 3. Arquivo de Workflow Completo e Pronto

**Caminho:** `.github/workflows/testflight.yml`

```yaml
name: Build & Deploy to TestFlight

on:
  push:
    branches: [ main ]
  workflow_dispatch:

env:
  XCODE_VERSION: '15.4'
  SCHEME: 'AoFrioTester'
  CONFIGURATION: 'Release'

jobs:
  deploy:
    name: Build → Archive → TestFlight
    runs-on: macos-14
    timeout-minutes: 60

    steps:
      # 1. Checkout
      - name: Checkout Repository
        uses: actions/checkout@v4

      # 2. Versão do Xcode
      - name: Select Xcode ${{ env.XCODE_VERSION }}
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: ${{ env.XCODE_VERSION }}

      # 3. Keychain temporário na VM do GitHub
      - name: Create Temporary Keychain
        run: |
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          security create-keychain -p "" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "" "$KEYCHAIN_PATH"
          echo "KEYCHAIN_PATH=$KEYCHAIN_PATH" >> $GITHUB_ENV

      # 4. Importar Certificado Apple Distribution
      - name: Import Certificate
        env:
          CERTIFICATES_P12: ${{ secrets.CERTIFICATES_P12 }}
          CERTIFICATES_P12_PASSWORD: ${{ secrets.CERTIFICATES_P12_PASSWORD }}
        run: |
          CERT_PATH=$RUNNER_TEMP/build_cert.p12
          echo "$CERTIFICATES_P12" | base64 --decode > "$CERT_PATH"
          security import "$CERT_PATH" \
            -P "$CERTIFICATES_P12_PASSWORD" \
            -A -t cert -f pkcs12 \
            -k "$KEYCHAIN_PATH"
          security set-key-partition-list \
            -S apple-tool:,apple: -s -k "" "$KEYCHAIN_PATH"
          security list-keychain -d user -s "$KEYCHAIN_PATH"

      # 5. Instalar Provisioning Profile
      - name: Install Provisioning Profile
        env:
          PROVISIONING_PROFILE: ${{ secrets.PROVISIONING_PROFILE }}
        run: |
          PP_PATH=$RUNNER_TEMP/aofrio_distribution.mobileprovision
          echo "$PROVISIONING_PROFILE" | base64 --decode > "$PP_PATH"
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          cp "$PP_PATH" ~/Library/MobileDevice/Provisioning\ Profiles/

      # 6. Build e Archive via xcodebuild
      - name: Archive App
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          xcodebuild clean archive \
            -scheme "$SCHEME" \
            -sdk iphoneos \
            -configuration "$CONFIGURATION" \
            -archivePath "$RUNNER_TEMP/AoFrioTester.xcarchive" \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID"

      # 7. Export .ipa para App Store
      - name: Export IPA
        run: |
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/AoFrioTester.xcarchive" \
            -exportOptionsPlist ExportOptions.plist \
            -exportPath "$RUNNER_TEMP/export"

      # 8. Upload para TestFlight
      - name: Upload to TestFlight
        uses: apple-actions/upload-testflight-distribution@v1
        with:
          app-path: ${{ runner.temp }}/export/AoFrioTester.ipa
          issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
          api-key-id: ${{ secrets.APPSTORE_KEY_ID }}
          api-private-key: ${{ secrets.APPSTORE_PRIVATE_KEY }}

      # 9. Limpar credenciais da VM
      - name: Cleanup Keychain
        if: always()
        run: security delete-keychain "$KEYCHAIN_PATH" || true
```

---

## 4. ExportOptions.plist (Raiz do Projeto)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>teamID</key>
  <string>SEU_TEAM_ID_10_CHARS</string>
  <key>uploadBitcode</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
  <key>signingStyle</key>
  <string>manual</string>
</dict>
</plist>
```

---

## 5. Info.plist: Permissões do App AoFrio

```xml
<!-- Bluetooth BLE (Sensor AoFrio Monitor) -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Usado para conectar ao sensor AoFrio e baixar os dados de temperatura gravados na memória do aparelho para análise do ensaio pull-down.</string>

<!-- NFC (Vinculação por toque no sensor) -->
<key>NFCReaderUsageDescription</key>
<string>Usado para identificar o sensor AoFrio por aproximação antes de iniciar o ensaio térmico.</string>

<!-- Câmera (QR Code do patrimônio da geladeira) -->
<key>NSCameraUsageDescription</key>
<string>Usado para ler o QR Code de identificação do patrimônio da geladeira e vincular ao sensor do ensaio.</string>

<!-- Capacidade NFC no .entitlements -->
<!-- com.apple.developer.nfc.readersession.formats → TAG -->
```

---

## 6. GitHub Secrets Necessários (Settings → Secrets → Actions)

| Secret | Como Obter |
|:---|:---|
| `CERTIFICATES_P12` | Exportar certificate.p12 do Keychain e converter em Base64 |
| `CERTIFICATES_P12_PASSWORD` | Senha definida ao exportar o .p12 |
| `PROVISIONING_PROFILE` | Download do .mobileprovision no Developer Portal → Base64 |
| `APPLE_TEAM_ID` | developer.apple.com → Account → Team ID (10 chars) |
| `APPSTORE_KEY_ID` | App Store Connect → Users → Keys → Key ID |
| `APPSTORE_ISSUER_ID` | App Store Connect → Users → Keys → Issuer ID |
| `APPSTORE_PRIVATE_KEY` | Conteúdo completo do arquivo .p8 baixado |

**Converter para Base64 no Windows (PowerShell):**
```powershell
# Para o .p12:
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\certificate.p12")) | Set-Clipboard
# Para o .mobileprovision:
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\AoFrio_Dist.mobileprovision")) | Set-Clipboard
```

---

## 7. Alternativa Mais Simples: Xcode Cloud (Apple Nativo)

Se a configuração do YAML parecer complexa, a **Xcode Cloud** é a alternativa plug-and-play:
- Acesse **App Store Connect → Xcode Cloud → Create Workflow**
- Conecte ao repositório GitHub `aofrio-pulldown-ios`
- **Apple gerencia automaticamente:** runners macOS, certificados, provisioning profiles e upload para TestFlight
- **Custo:** 25 horas de compute por mês grátis na conta Apple Developer

---

## 8. Checklist Final de Execução (Para o Agente)

- [ ] Criar repositório a partir de `msonrm/no-mac-ios-starter`
- [ ] Renomear scheme e bundle ID para `com.suaempresa.aofrio-tester`
- [ ] Criar toda a estrutura de pastas conforme Seção 2
- [ ] Implementar `PullDownAnalyzer.swift` usando fórmulas de `specs/algorithm_specification.md`
- [ ] Implementar `ThermalCalculator.swift` (cálculo automático do tempo por salto térmico)
- [ ] Implementar `RecoveryEngine.swift` (recálculo de rota após choque térmico por porta)
- [ ] Implementar `BLEService.swift` com CoreBluetooth para o AoFrio Monitor
- [ ] Implementar `NFCService.swift` + `QRScannerService.swift` para vinculação
- [ ] Criar todas as Views SwiftUI com design Obsidian Dark (arco neon circular)
- [ ] Configurar os 7 GitHub Secrets no repositório
- [ ] Adicionar `.github/workflows/testflight.yml` e `ExportOptions.plist`
- [ ] Fazer `git push origin main` e acompanhar o build nos Actions
- [ ] Instalar via TestFlight no iPhone do técnico
