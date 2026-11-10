# MobAI ios-builder: CLI de Builds iOS para Windows/Linux
## Integração com GitHub Actions para o Projeto AoFrio

> **Repositório:** `MobAI-App/ios-builder`  
> **Site:** [mobai.run](https://mobai.run)  
> **Propósito:** Gerenciar builds iOS via linha de comando no Windows sem Mac

---

## O que é e por que é diferente

O `ios-builder` **não substitui** o GitHub Actions — ele é o **controle remoto CLI** que você usa no seu Windows para **disparar e gerenciar** os builds que rodam no macOS da nuvem.

A diferença crítica em relação a fazer `git push` manualmente:

| Situação | git push + GitHub Actions | ios-builder CLI |
|:---|:---:|:---:|
| Build da última versão commitada | ✅ | ✅ |
| Build de código local não commitado | ❌ | ✅ |
| Download automático do .ipa | ❌ (artifact manual) | ✅ (pasta ./dist/) |
| Visibilidade do status em tempo real | ❌ (só no painel web) | ✅ (terminal) |
| Integração com agentes de IA | ❌ | ✅ (nativa) |

---

## Instalação no Windows

```powershell
# Opção 1: Baixar o executável .exe do GitHub Releases
# Acesse: github.com/MobAI-App/ios-builder/releases
# Baixe o builder.exe e adicione ao PATH do Windows

# Verificar instalação:
builder --version
```

---

## Fluxo de Trabalho Diário com ios-builder

### Setup Único (Primeira Vez):
```powershell
# 1. Autenticar com GitHub (abre browser para OAuth)
builder auth github

# 2. Inicializar no projeto (cria .github/workflows/ automaticamente)
cd C:\Users\PEREIRA\Desktop\aofrio-pulldown-ios
builder init
# → Detecta tipo de projeto (SwiftUI nativo)
# → Cria .github/workflows/ios-builder.yml
# → Configura secrets necessários interativamente
```

### Ciclo Diário de Desenvolvimento:
```powershell
# Você está trabalhando no código SwiftUI no VS Code (Windows)
# Fez mudanças mas NÃO commitou ainda — quer testar!

builder ios build
# → Cria snapshot temporário do seu código atual
# → Faz push para ref oculto no GitHub (sem poluir histórico)
# → Dispara o macOS runner no GitHub Actions
# → Monitora o progresso em tempo real no terminal
# → Baixa o .ipa para ./dist/AoFrioTester.ipa automaticamente
# → Tempo médio: ~10 minutos

# Para instalar via QR Code no iPhone do técnico (TestFlight opcional):
builder ios install
# → Gera QR Code no terminal para instalação OTA

# Para enviar direto ao TestFlight após validar:
builder ios upload --testflight
```

---

## Integração com Fastlane (Stack Completa)

O `ios-builder` e o Fastlane não competem — eles se complementam:

```
ios-builder (CLI no Windows)
        │
        │ dispara build no GitHub Actions
        ▼
GitHub Actions macOS runner
        │
        │ executa
        ▼
Fastlane beta lane
  ├── match       (certificados)
  ├── gym         (compilação)
  └── pilot       (TestFlight)
        │
        │ retorna .ipa
        ▼
ios-builder baixa para ./dist/
```

---

## Workflow GitHub Actions gerado pelo `builder init`

```yaml
# .github/workflows/ios-builder.yml (gerado automaticamente)
name: ios-builder Cloud Compile

on:
  workflow_dispatch:         # Disparado pelo CLI ios-builder
    inputs:
      ref:
        description: 'Git ref or snapshot ref to build'
        required: true
      upload_target:
        description: 'none | testflight | appstore'
        default: 'none'

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.inputs.ref }}  # Ref do snapshot temporário

      - uses: MobAI-App/ios-builder-action@v2  # Action oficial do MobAI
        with:
          apple-team-id:     ${{ secrets.APPLE_TEAM_ID }}
          certificate-p12:   ${{ secrets.CERTIFICATES_P12 }}
          certificate-pass:  ${{ secrets.CERTIFICATES_P12_PASSWORD }}
          provisioning:      ${{ secrets.PROVISIONING_PROFILE }}
          upload-target:     ${{ github.event.inputs.upload_target }}
          asc-key-id:        ${{ secrets.APPSTORE_KEY_ID }}
          asc-issuer-id:     ${{ secrets.APPSTORE_ISSUER_ID }}
          asc-private-key:   ${{ secrets.APPSTORE_PRIVATE_KEY }}
```

---

## Checklist de Setup para o Agente

- [ ] Baixar `builder.exe` do GitHub Releases e adicionar ao PATH do Windows
- [ ] Rodar `builder auth github` para vincular conta
- [ ] Dentro de `aofrio-pulldown-ios`, rodar `builder init`
- [ ] Confirmar que `.github/workflows/ios-builder.yml` foi criado
- [ ] Testar com `builder ios build` (usa MockBLEService, não precisa do hardware)
- [ ] Validar que `./dist/AoFrioTester.ipa` foi criado após o build
- [ ] Quando pronto para TestFlight: `builder ios upload --testflight`
