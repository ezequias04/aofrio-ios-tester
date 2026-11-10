# 🛠️ SETUP COMPLETO — Ferramentas para Desenvolver o App AoFrio iOS no Windows
## Leia este arquivo antes de qualquer coisa

> Este guia instala e configura **todas as ferramentas necessárias** para desenvolver,
> compilar e publicar o app AoFrio Pull-Down Tester (iOS/SwiftUI) a partir do Windows,
> sem precisar de um Mac físico.

---

## ✅ Status das Ferramentas (Verificado em 09/11/2026)

| Ferramenta | Versão | Status | Para que serve |
|:---|:---|:---:|:---|
| Git | 2.55 | ✅ Instalado | Versionamento e push para GitHub |
| Node.js | 26.12 | ✅ Instalado | Scripts auxiliares e ferramentas JS |
| npm | 12.2 | ✅ Instalado | Gerenciador de pacotes Node |
| Python | 3.14 | ✅ Instalado | Scripts de automação |
| GitHub CLI (gh) | 2.97 | ✅ Instalado | Autenticação e gerência do GitHub via terminal |
| Ruby 3.2 + DevKit | 3.2.11 | 🔄 Instalar (ver Passo 1) | Executar Fastlane (automação CI/CD) |
| VS Code | 1.143 | 🔄 Instalar (ver Passo 2) | Editor de código SwiftUI |
| Fastlane | latest | 🔄 Instalar (ver Passo 3) | Automação de certificados, builds e TestFlight |
| ios-builder CLI | latest | 🔄 Instalar (ver Passo 4) | Compilar iOS direto do Windows via CLI |

---

## PASSO 1: Instalar Ruby 3.2 com DevKit

Ruby é **obrigatório** para o Fastlane funcionar.

```powershell
# Abra o PowerShell como ADMINISTRADOR e execute:
winget install RubyInstallerTeam.RubyWithDevKit.3.2 --silent --accept-package-agreements

# Após instalar, FECHE e REABRA o PowerShell e verifique:
ruby --version
# Esperado: ruby 3.2.x (...)

gem --version
# Esperado: 3.x.x
```

> ⚠️ **IMPORTANTE:** Após a instalação do Ruby, o instalador pode pedir para executar
> `ridk install` para configurar o MSYS2 (compilador nativo). Se aparecer esse prompt,
> pressione ENTER e escolha a opção 3 (MSYS2 and MINGW development toolchain).

---

## PASSO 2: Instalar o VS Code (Editor de Código)

```powershell
winget install Microsoft.VisualStudioCode --silent --accept-package-agreements

# Após instalar, abra um novo terminal e instale as extensões essenciais:
code --install-extension Swiftlang.swift-syntax
code --install-extension swift-server.swift
code --install-extension hashicorp.terraform
code --install-extension GitHub.copilot
```

---

## PASSO 3: Instalar o Fastlane (Automação iOS)

```powershell
# Com Ruby instalado, instale o Bundler e Fastlane:
gem install bundler
gem install fastlane

# Verificar:
fastlane --version
# Esperado: fastlane (2.x.x)
```

---

## PASSO 4: Instalar o ios-builder CLI (MobAI)

```powershell
# Opção A: Via npm (recomendado — mais simples)
npm install -g @mobai/ios-builder

# Verificar:
builder --version

# Opção B: Baixar o .exe direto do GitHub Releases
# Acesse: https://github.com/MobAI-App/ios-builder/releases
# Baixe: builder-windows-x64.exe
# Renomeie para: builder.exe
# Mova para: C:\Windows\System32\ (ou qualquer pasta no PATH)
```

---

## PASSO 5: Configurar o GitHub CLI (já instalado)

```powershell
# Autenticar com sua conta GitHub (abre navegador):
gh auth login
# Escolha: GitHub.com → HTTPS → Authenticate with browser

# Verificar:
gh auth status
# Esperado: Logged in to github.com as SEU_USUARIO
```

---

## PASSO 6: Clonar o Template do Projeto iOS

```powershell
# 1. Acesse: https://github.com/msonrm/no-mac-ios-starter
# 2. Clique em "Use this template" → "Create a new repository"
# 3. Nome: aofrio-pulldown-ios | Visibilidade: Private
# 4. Clone localmente:

cd C:\Users\PEREIRA\Desktop
gh repo clone SEU_USUARIO/aofrio-pulldown-ios
cd aofrio-pulldown-ios

# 5. Instalar dependências do Fastlane (via Bundler):
bundle install
```

---

## PASSO 7: Inicializar o ios-builder no Projeto

```powershell
cd C:\Users\PEREIRA\Desktop\aofrio-pulldown-ios

# Autenticar o ios-builder com GitHub:
builder auth github

# Inicializar (detecta o projeto e cria .github/workflows/ automaticamente):
builder init
# → Responda as perguntas:
#   Scheme: AoFrioTester
#   Bundle ID: com.suaempresa.aofrio-tester
#   Team ID: (seu Apple Team ID de 10 caracteres)
```

---

## PASSO 8: Configurar os Secrets do GitHub

```powershell
# Com o GitHub CLI, adicione os secrets necessários:
gh secret set APPLE_TEAM_ID --body "SEU_TEAM_ID"
gh secret set APPSTORE_KEY_ID --body "SEU_KEY_ID"
gh secret set APPSTORE_ISSUER_ID --body "SEU_ISSUER_ID"

# Para secrets com arquivos (certificados):
# Converter .p12 para Base64 no PowerShell:
$p12Base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes(".\certificate.p12"))
gh secret set CERTIFICATES_P12 --body $p12Base64
gh secret set CERTIFICATES_P12_PASSWORD --body "SENHA_DO_P12"

# Para o provisioning profile:
$ppBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes(".\AoFrio.mobileprovision"))
gh secret set PROVISIONING_PROFILE --body $ppBase64
```

---

## PASSO 9: Primeiro Build de Teste

```powershell
cd C:\Users\PEREIRA\Desktop\aofrio-pulldown-ios

# Compilar na nuvem com código atual (mesmo sem commitar):
builder ios build

# Acompanhar logs em tempo real no terminal.
# Quando concluir, o .ipa estará em:
# ./dist/AoFrioTester.ipa
```

---

## 🔄 Fluxo de Trabalho Diário

```
1. Abrir VS Code:
   code C:\Users\PEREIRA\Desktop\aofrio-pulldown-ios

2. Editar código SwiftUI normalmente...

3. Testar build rápido (sem commitar):
   builder ios build

4. Quando estiver pronto, commitar e publicar no TestFlight:
   git add . && git commit -m "feat: nova tela de ensaio"
   git push origin main
   # → GitHub Actions roda Fastlane automaticamente → TestFlight
```

---

## 📂 Arquivos de Referência nesta Pasta

| Arquivo | Conteúdo |
|:---|:---|
| `specs/algorithm_specification.md` | Fórmulas matemáticas do ensaio pull-down |
| `specs/aofrio_ble_specs.md` | Protocolo Bluetooth do sensor AoFrio |
| `specs/ios-no-mac-setup.md` | Setup iOS sem Mac (guia completo) |
| `specs/ios-starter-cloud-build.md` | Template e estrutura do projeto iOS |
| `specs/automation-cli-fastlane.md` | Fastlane: Fastfile, Matchfile, Gymfile |
| `specs/mobai-ios-builder-cli.md` | ios-builder CLI: comandos e integração |
| `AGENT_EXECUTION_PLAN.md` | Guia mestre para qualquer agente continuar |

---

## ❓ Problemas Comuns e Soluções

### Ruby não reconhecido após instalação:
```powershell
# Feche e reabra o PowerShell completamente
# Se ainda não funcionar, adicione ao PATH manualmente:
$env:PATH += ";C:\Ruby32-x64\bin"
```

### Fastlane: erro de certificado SSL:
```powershell
gem update --system
gem install fastlane
```

### builder: comando não encontrado:
```powershell
# Verificar se o npm global está no PATH:
npm config get prefix
# Adicionar ao PATH se necessário
```

### GitHub Actions falhando com erro de assinatura:
```
→ Verificar se todos os 7 secrets estão configurados corretamente
→ Checar se o provisioning profile não expirou
→ Ver logs detalhados: gh run view --log
```
