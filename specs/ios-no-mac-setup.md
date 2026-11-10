# iOS App sem Mac: SwiftUI + GitHub Actions + TestFlight
## Guia Completo de Implementação para o AoFrio Pull-Down Tester

> [!IMPORTANT]
> Este documento é o guia mestre para construir o aplicativo iOS nativo em **SwiftUI puro**, sem precisar de um Mac fisicamente. O build é feito em **runners macOS na nuvem do GitHub Actions** e enviado automaticamente ao **TestFlight** a cada push na branch `main`.

---

## 1. Visão Geral da Estratégia

```
┌─────────────────────────────────────────────────────────────────────┐
│  SEU COMPUTADOR (Windows / Linux / qualquer OS)                     │
│  - Você escreve o código SwiftUI no VS Code ou qualquer editor      │
│  - Você faz git push para o GitHub                                  │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │ git push origin main
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  GITHUB ACTIONS (Runner macOS na Nuvem do GitHub)                   │
│  - Spins up uma VM macOS com Xcode pré-instalado                    │
│  - Injeta seus certificados e provisioning profiles dos Secrets     │
│  - Roda: xcodebuild → archive → export .ipa                         │
│  - Faz upload do .ipa para App Store Connect via API Key            │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │ upload automático
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│  TESTFLIGHT (Apple)                                                 │
│  - App disponível em minutos para instalar no iPhone do técnico     │
│  - Sem passar pela revisão da App Store (ideal para testes internos)│
└─────────────────────────────────────────────────────────────────────┘
```

**Baseado no template:** [`msonrm/no-mac-ios-starter`](https://github.com/msonrm/no-mac-ios-starter)

---

## 2. Pré-Requisitos (O que você precisa ter antes de começar)

### 2.1 Conta Apple Developer ($99/ano)
- Acesse [developer.apple.com](https://developer.apple.com) e cadastre sua empresa ou conta pessoal.
- Sem isso, não é possível assinar o app e distribuir pelo TestFlight.

### 2.2 Credenciais que você precisa gerar (uma única vez)

Acesse o portal da Apple e gere/colete:

| Credencial | Onde gerar | Para que serve |
| :--- | :--- | :--- |
| **App Store Connect API Key** | App Store Connect → Users → Keys | Autentica o upload do `.ipa` para o TestFlight |
| **Certificate `.p12`** | Apple Developer → Certificates | Assina criptograficamente o binário do app |
| **Provisioning Profile `.mobileprovision`** | Apple Developer → Profiles | Diz quais dispositivos/recursos o app pode usar |
| **Apple Team ID** | developer.apple.com → Account | Identifica sua conta de desenvolvedor |

> [!TIP]
> Se você não tem acesso a um Mac, pode usar um **Mac de aluguel por hora** no serviço [MacStadium](https://macstadium.com) ou [MacinCloud](https://www.macincloud.com) apenas para gerar as credenciais uma única vez. Após isso, nunca mais precisará de um Mac físico.

---

## 3. Passo a Passo Completo

### Passo 1: Usar o Template no GitHub

1. Acesse: `https://github.com/msonrm/no-mac-ios-starter`
2. Clique em **"Use this template"** → **"Create a new repository"**
3. Nomeie o repositório: `aofrio-pulldown-ios`
4. Clone na sua máquina:
   ```bash
   git clone https://github.com/SEU_USUARIO/aofrio-pulldown-ios.git
   cd aofrio-pulldown-ios
   ```

---

### Passo 2: Configurar os Secrets no GitHub

No seu repositório GitHub: **Settings → Secrets and variables → Actions → New repository secret**

Crie estes secrets exatamente com esses nomes:

```
APPSTORE_KEY_ID           → ID da sua API Key (ex: D3T4K3Y123)
APPSTORE_ISSUER_ID        → Issuer UUID da API Key
APPSTORE_PRIVATE_KEY      → Conteúdo completo do arquivo .p8 (texto)
CERTIFICATE_P12_BASE64    → Certificado .p12 convertido em Base64
CERTIFICATE_P12_PASSWORD  → Senha do .p12
PROVISIONING_PROFILE_BASE64 → Provisioning profile .mobileprovision em Base64
APPLE_TEAM_ID             → Team ID de 10 caracteres (ex: ABC1234DEF)
BUNDLE_ID                 → ex: com.suaempresa.aofrio-tester
```

**Para converter os arquivos para Base64 no Windows (PowerShell):**
```powershell
# Para o certificado .p12:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.p12")) | Set-Clipboard

# Para o provisioning profile:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("aofrio_tester.mobileprovision")) | Set-Clipboard
```

---

### Passo 3: Estrutura do Projeto SwiftUI

```
aofrio-pulldown-ios/
├── .github/
│   └── workflows/
│       └── deploy-testflight.yml    ← Pipeline do GitHub Actions
├── AoFrioTester/
│   ├── AoFrioTesterApp.swift        ← Entry point SwiftUI
│   ├── ContentView.swift
│   │
│   ├── Models/
│   │   ├── SensorReading.swift      ← Struct de leitura do AoFrio
│   │   ├── TestProfile.swift        ← Perfis de setpoint/diferencial
│   │   └── TestResult.swift         ← Laudo final calculado
│   │
│   ├── Engine/
│   │   └── PullDownAnalyzer.swift   ← Algoritmo de aprovação/reprovação
│   │
│   ├── Services/
│   │   ├── BLEService.swift         ← Conexão Bluetooth com AoFrio
│   │   ├── NFCService.swift         ← Leitura NFC do sensor
│   │   ├── QRScannerService.swift   ← Leitura QR Code do patrimônio
│   │   ├── MockBLEService.swift     ← Simulador para testes sem hardware
│   │   └── APIService.swift         ← Sync para o Portal Web
│   │
│   ├── Views/
│   │   ├── HomeView.swift           ← Tela inicial (NFC + QR Code)
│   │   ├── DialView.swift           ← Mostrador circular de temperatura
│   │   ├── FleetView.swift          ← Lista de múltiplos sensores
│   │   ├── ChartView.swift          ← Gráfico histórico da curva
│   │   ├── ReportView.swift         ← Laudo final APROVADA/REPROVADA
│   │   └── SettingsView.swift       ← Configuração de setpoint/diferencial
│   │
│   └── Info.plist                   ← NSBluetoothAlwaysUsageDescription, NFC, Camera
│
├── AoFrioTester.xcodeproj/
└── README.md
```

---

### Passo 4: GitHub Actions Workflow (`.github/workflows/deploy-testflight.yml`)

```yaml
name: Build & Deploy to TestFlight

on:
  push:
    branches: [ main ]           # Roda automaticamente a cada push na main
  workflow_dispatch:             # Permite rodar manualmente no painel do GitHub

jobs:
  deploy:
    runs-on: macos-14            # macOS Sonoma com Xcode 15 pré-instalado
    timeout-minutes: 60

    steps:
      # 1. Checkout do código
      - name: Checkout
        uses: actions/checkout@v4

      # 2. Selecionar versão exata do Xcode
      - name: Set Xcode Version
        run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer

      # 3. Configurar Keychain temporário para o build
      - name: Setup Keychain
        run: |
          security create-keychain -p "build_password" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "build_password" build.keychain
          security set-keychain-settings -t 3600 -u build.keychain

      # 4. Importar certificado de distribuição
      - name: Import Certificate
        env:
          CERTIFICATE_P12_BASE64: ${{ secrets.CERTIFICATE_P12_BASE64 }}
          CERTIFICATE_P12_PASSWORD: ${{ secrets.CERTIFICATE_P12_PASSWORD }}
        run: |
          echo "$CERTIFICATE_P12_BASE64" | base64 --decode > certificate.p12
          security import certificate.p12 \
            -k build.keychain \
            -P "$CERTIFICATE_P12_PASSWORD" \
            -T /usr/bin/codesign
          security set-key-partition-list \
            -S apple-tool:,apple: \
            -s -k "build_password" build.keychain

      # 5. Instalar Provisioning Profile
      - name: Install Provisioning Profile
        env:
          PROVISIONING_PROFILE_BASE64: ${{ secrets.PROVISIONING_PROFILE_BASE64 }}
        run: |
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          echo "$PROVISIONING_PROFILE_BASE64" | base64 --decode \
            > ~/Library/MobileDevice/Provisioning\ Profiles/aofrio_distribution.mobileprovision

      # 6. Build e Archive do app SwiftUI
      - name: Build & Archive
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          BUNDLE_ID: ${{ secrets.BUNDLE_ID }}
        run: |
          xcodebuild archive \
            -scheme "AoFrioTester" \
            -sdk iphoneos \
            -configuration Release \
            -archivePath "$PWD/build/AoFrioTester.xcarchive" \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
            PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"

      # 7. Export .ipa para distribuição AppStore
      - name: Export IPA
        run: |
          cat << EOF > ExportOptions.plist
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>method</key>
            <string>app-store</string>
            <key>teamID</key>
            <string>${{ secrets.APPLE_TEAM_ID }}</string>
            <key>uploadBitcode</key>
            <false/>
            <key>compileBitcode</key>
            <false/>
          </dict>
          </plist>
          EOF

          xcodebuild -exportArchive \
            -archivePath "$PWD/build/AoFrioTester.xcarchive" \
            -exportOptionsPlist ExportOptions.plist \
            -exportPath "$PWD/build/export"

      # 8. Upload para TestFlight via API Key da App Store Connect
      - name: Upload to TestFlight
        env:
          APPSTORE_KEY_ID: ${{ secrets.APPSTORE_KEY_ID }}
          APPSTORE_ISSUER_ID: ${{ secrets.APPSTORE_ISSUER_ID }}
          APPSTORE_PRIVATE_KEY: ${{ secrets.APPSTORE_PRIVATE_KEY }}
        run: |
          echo "$APPSTORE_PRIVATE_KEY" > AuthKey.p8
          
          xcrun altool --upload-app \
            --type ios \
            --file "$PWD/build/export/AoFrioTester.ipa" \
            --apiKey "$APPSTORE_KEY_ID" \
            --apiIssuer "$APPSTORE_ISSUER_ID"

      # 9. Limpar Keychain e credenciais (segurança)
      - name: Cleanup
        if: always()
        run: |
          security delete-keychain build.keychain || true
          rm -f certificate.p12 AuthKey.p8
```

---

## 4. Permissões Especiais no Info.plist

O app AoFrio precisa de acesso a hardware sensível. Adicione estas chaves no `Info.plist`:

```xml
<!-- Bluetooth BLE (AoFrio Monitor) -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Usado para conectar ao sensor AoFrio e baixar os dados de temperatura gravados na memória do aparelho.</string>

<!-- NFC (Leitura da etiqueta do sensor para vinculação) -->
<key>NFCReaderUsageDescription</key>
<string>Usado para identificar o sensor AoFrio por aproximação antes de iniciar o ensaio térmico.</string>

<!-- Câmera (QR Code do patrimônio da geladeira) -->
<key>NSCameraUsageDescription</key>
<string>Usado para ler o QR Code de patrimônio da geladeira e vincular ao sensor AoFrio do ensaio.</string>

<!-- Capacidades NFC no Entitlements -->
<!-- com.apple.developer.nfc.readersession.formats → TAG (NFC Data Exchange Format) -->
```

---

## 5. Dependências Swift (Swift Package Manager)

No Xcode ou `Package.swift`, adicione estas dependências:

```swift
dependencies: [
    // Bluetooth BLE (substitui flutter_blue_plus no SwiftUI nativo)
    .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.53.0"),
    
    // Charts nativos (iOS 16+) - já incluso no SwiftUI!
    // import Charts → Nativo, sem dependência externa necessária
    
    // QR Code Scanner
    .package(url: "https://github.com/twostraws/CodeScanner", from: "2.3.0"),
    
    // Network Layer (Sync para o Portal Web)
    // URLSession nativo do iOS → Sem dependência externa necessária
]
```

> [!NOTE]
> O **Charts** e o **CoreBluetooth** (Bluetooth BLE) e o **CoreNFC** são frameworks nativos do iOS, incluídos automaticamente sem precisar instalar nenhuma biblioteca externa. Isso torna o app extremamente leve!

---

## 6. Fluxo de Branches Git Recomendado

```
main          → Dispara build automático + deploy TestFlight
develop       → Branch de desenvolvimento (sem trigger de deploy)
feature/*     → Branches de funcionalidades novas
hotfix/*      → Correções urgentes (merge direto na main)
```

**Workflow diário do desenvolvedor:**
```bash
# Desenvolver uma nova feature
git checkout -b feature/pull-down-analyzer

# Fazer commits
git add . && git commit -m "feat: add thermal shock recovery algorithm"

# Enviar para revisão
git push origin feature/pull-down-analyzer

# Após aprovação, merge na main → GitHub Actions faz o deploy automático!
git checkout main && git merge feature/pull-down-analyzer && git push
```

---

## 7. Custo de Operação

| Serviço | Custo | Observação |
| :--- | :--- | :--- |
| **GitHub Actions (macOS runner)** | ~2.000 minutos grátis/mês | Conta Free. Build leva ~8-12 min por push |
| **Apple Developer Program** | $99/ano | Obrigatório para TestFlight |
| **TestFlight** | Gratuito | Incluso na conta Apple Developer |
| **Mac físico** | $0 | Não necessário! |

---

## 8. Checklist Final para o Agente Executar

- [ ] Usar o template `msonrm/no-mac-ios-starter` como base
- [ ] Criar repositório `aofrio-pulldown-ios` no GitHub
- [ ] Configurar os 8 secrets no GitHub (ver Passo 2)
- [ ] Implementar as `Views/` em SwiftUI com o design Obsidian Dark
- [ ] Implementar o `PullDownAnalyzer.swift` com as fórmulas de `specs/algorithm_specification.md`
- [ ] Implementar o `BLEService.swift` com CoreBluetooth para o sensor AoFrio
- [ ] Implementar o `NFCService.swift` com CoreNFC (vinculação do sensor)
- [ ] Implementar o `QRScannerService.swift` para ler patrimônio da geladeira
- [ ] Adicionar `.github/workflows/deploy-testflight.yml` ao projeto
- [ ] Fazer primeiro `git push origin main` e acompanhar o build no painel Actions
- [ ] Instalar o app no iPhone via TestFlight
