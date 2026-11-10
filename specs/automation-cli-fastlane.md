# Ferramentas de Automação Avançada e CLI para iOS (Sem Mac)
## AoFrio Pull-Down Tester — Camada de Automação e DevOps

---

## 1. Stack de Automação Recomendado para o Projeto

```
┌─────────────────────────────────────────────────────────────────────┐
│  FASTLANE  (Orquestrador CLI — a engine de tudo)                    │
│  - Roda DENTRO do macOS runner do GitHub Actions                    │
│  - Você escreve as lanes em Ruby (Fastfile)                         │
│  - Cada comando Fastlane automatiza uma tarefa do ciclo iOS         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ usa
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       ┌─────────────┐  ┌───────────┐  ┌──────────────┐
       │  match      │  │  gym      │  │  pilot       │
       │ Certificados│  │  Build    │  │  TestFlight  │
       │  e Profiles │  │  do App   │  │  Upload      │
       └─────────────┘  └───────────┘  └──────────────┘
```

---

## 2. As 7 Ferramentas CLI do Ecossistema Fastlane

| Ferramenta | Função | Comando |
|:---|:---|:---|
| **`match`** | Gerencia certificados e provisioning profiles de forma centralizada e encriptada | `fastlane match appstore` |
| **`gym`** | Compila, arquiva e exporta o `.ipa` do projeto Xcode | `fastlane gym` |
| **`pilot`** | Upload e gerência de builds no TestFlight | `fastlane pilot upload` |
| **`scan`** | Roda testes unitários e de UI automaticamente | `fastlane scan` |
| **`cert`** | Cria e renova certificados de distribuição | `fastlane cert` |
| **`sigh`** | Gerencia provisioning profiles | `fastlane sigh` |
| **`deliver`** | Publica versões na App Store pública | `fastlane deliver` |

---

## 3. Comparativo das 3 Ferramentas de Automação

| | Fastlane + GitHub Actions | Xcode Cloud (Apple) | Codemagic |
|:---|:---:|:---:|:---:|
| **Mac local necessário?** | ❌ Não | ⚠️ Sim (1x para setup) | ❌ Não |
| **Controle via CLI** | ✅ Máximo | ❌ Mínimo (GUI) | ✅ Alto (YAML) |
| **Code Signing automático** | 🔧 Manual (`match`) | ✅ Total (Apple gerencia) | ✅ Automático |
| **Custo mensal** | 🆓 Grátis (2000 min/mês) | 🆓 25h grátis incluso | 🆓 500 min grátis |
| **Suporte ao Projeto AoFrio** | ✅ Ideal | ✅ Excelente | ✅ Bom |
| **Complexidade de setup** | 🔴 Alta | 🟢 Baixa | 🟡 Média |
| **Flexibilidade de scripts** | ✅ Ilimitada | ❌ Restrita | ✅ Alta |

**🏆 Escolha para o AoFrio:** Fastlane + GitHub Actions (máximo controle) ou Xcode Cloud (plug-and-play).

---

## 4. Estrutura Completa do Fastlane no Projeto

```
aofrio-pulldown-ios/
└── fastlane/
    ├── Fastfile          ← Lanes de automação (beta, release, test)
    ├── Appfile           ← Bundle ID e Apple ID/Team
    ├── Matchfile         ← Config do match (certs/profiles centralizados)
    └── Gymfile           ← Config do build (scheme, configuration)
```

---

## 5. Fastfile Completo e Comentado

```ruby
# fastlane/Fastfile

# Importa a API Key do App Store Connect (substitui Apple ID + 2FA)
# Permite rodar em CI/CD sem interação humana
default_platform(:ios)

before_all do
  app_store_connect_api_key(
    key_id:        ENV["ASC_KEY_ID"],       # GitHub Secret: APPSTORE_KEY_ID
    issuer_id:     ENV["ASC_ISSUER_ID"],    # GitHub Secret: APPSTORE_ISSUER_ID
    key_content:   ENV["ASC_KEY_CONTENT"],  # GitHub Secret: APPSTORE_PRIVATE_KEY
    is_app_store_connect_api_key: true
  )
end

platform :ios do

  # ─────────────────────────────────────────────────────────────────
  # LANE: test
  # Roda todos os testes unitários do algoritmo pull-down
  # Trigger: Pull Requests e pushes em develop
  # ─────────────────────────────────────────────────────────────────
  lane :test do
    scan(
      scheme:        "AoFrioTester",
      device:        "iPhone 15 Pro",
      code_coverage: true,
      output_files:  "test_results.xml"
    )
  end

  # ─────────────────────────────────────────────────────────────────
  # LANE: beta
  # Compila, incrementa build number e envia para TestFlight
  # Trigger: git push origin main
  # ─────────────────────────────────────────────────────────────────
  lane :beta do
    # 1. Busca e instala certificados/profiles encriptados do repo privado
    match(
      type:     "appstore",
      readonly: is_ci?   # Em CI: apenas lê; nunca gera novo cert sem autorização
    )

    # 2. Auto-incrementa o build number baseado no último build do TestFlight
    increment_build_number(
      build_number: latest_testflight_build_number + 1,
      xcodeproj:    "AoFrioTester.xcodeproj"
    )

    # 3. Compila e gera o .ipa via gym (wrapper de xcodebuild)
    build_app(
      scheme:         "AoFrioTester",
      configuration:  "Release",
      export_method:  "app-store",
      output_name:    "AoFrioTester.ipa"
    )

    # 4. Faz upload para TestFlight (não aguarda processamento da Apple)
    upload_to_testflight(
      skip_waiting_for_build_processing: true,
      changelog: "Build #{lane_context[SharedValues::BUILD_NUMBER]}: #{changelog_from_git_commits(commits_count: 5)}"
    )

    # 5. Notificação de sucesso (opcional: Slack, Teams, etc.)
    puts "✅ Build #{lane_context[SharedValues::BUILD_NUMBER]} enviado para TestFlight com sucesso!"
  end

  # ─────────────────────────────────────────────────────────────────
  # LANE: release
  # Envia versão final para revisão da App Store pública
  # Trigger: manual (workflow_dispatch) ou tag v*
  # ─────────────────────────────────────────────────────────────────
  lane :release do
    match(type: "appstore", readonly: true)

    increment_version_number(
      version_number: ENV["RELEASE_VERSION"] # Ex: "1.2.0"
    )

    build_app(scheme: "AoFrioTester", configuration: "Release")

    deliver(
      submit_for_review: true,
      automatic_release: false, # Aguarda aprovação manual para publicar
      force:             true,
      metadata_path:     "./metadata"
    )
  end

  # ─────────────────────────────────────────────────────────────────
  # LANE: setup_certs (rodar UMA VEZ no Mac alugado)
  # Inicializa o repositório privado de certificados com match
  # ─────────────────────────────────────────────────────────────────
  lane :setup_certs do
    match(
      type:         "appstore",
      app_identifier: "com.suaempresa.aofrio-tester",
      git_url:      ENV["MATCH_GIT_URL"],  # URL do repo privado de certs
      readonly:     false                   # Cria novos certs se necessário
    )
  end

end
```

---

## 6. Appfile

```ruby
# fastlane/Appfile

app_identifier("com.suaempresa.aofrio-tester")
apple_id(ENV["APPLE_ID"])
team_id(ENV["APPLE_TEAM_ID"])
itc_team_id(ENV["ITC_TEAM_ID"]) # App Store Connect Team ID
```

---

## 7. Matchfile (Gerenciamento Centralizado de Certificados)

```ruby
# fastlane/Matchfile

# Repositório Git privado onde o match guarda os certificados encriptados
git_url(ENV["MATCH_GIT_URL"])     # Ex: "https://github.com/suaempresa/ios-certs-private"

# Tipo padrão de certificado (appstore = TestFlight + App Store)
type("appstore")

app_identifier(["com.suaempresa.aofrio-tester"])
username(ENV["APPLE_ID"])

# Senha de encriptação dos certs (GitHub Secret: MATCH_PASSWORD)
# Nunca hardcodar aqui!
```

---

## 8. Gymfile (Configuração do Build)

```ruby
# fastlane/Gymfile

scheme("AoFrioTester")
sdk("iphoneos")
configuration("Release")
export_method("app-store")
output_directory("./build")
clean(true)
```

---

## 9. GitHub Actions Workflow com Fastlane

```yaml
# .github/workflows/testflight.yml
name: Beta Deploy → TestFlight via Fastlane

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: macos-14
    timeout-minutes: 60

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Necessário para changelog_from_git_commits

      - name: Select Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: 'latest-stable'

      # Setup Ruby + Bundler (versão fixa via Gemfile.lock = builds reproduzíveis)
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true  # Cache das gems entre builds (economiza ~2 min)

      # Instala Fastlane via Bundler (versão pinada no Gemfile)
      - name: Install Fastlane
        run: bundle install

      # Configura SSH para o match acessar o repo privado de certificados
      - name: Setup SSH for Match
        env:
          MATCH_DEPLOY_KEY: ${{ secrets.MATCH_DEPLOY_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$MATCH_DEPLOY_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan github.com >> ~/.ssh/known_hosts

      # Roda a lane beta do Fastfile
      - name: Run Fastlane Beta Lane
        env:
          ASC_KEY_ID:        ${{ secrets.APPSTORE_KEY_ID }}
          ASC_ISSUER_ID:     ${{ secrets.APPSTORE_ISSUER_ID }}
          ASC_KEY_CONTENT:   ${{ secrets.APPSTORE_PRIVATE_KEY }}
          MATCH_GIT_URL:     ${{ secrets.MATCH_GIT_URL }}
          MATCH_PASSWORD:    ${{ secrets.MATCH_PASSWORD }}
          APPLE_TEAM_ID:     ${{ secrets.APPLE_TEAM_ID }}
          ITC_TEAM_ID:       ${{ secrets.ITC_TEAM_ID }}
        run: bundle exec fastlane beta
```

---

## 10. Gemfile (Versões Fixas das Dependências)

```ruby
# Gemfile
source "https://rubygems.org"

gem "fastlane", "~> 2.220"      # Versão pinada para builds reproduzíveis
gem "cocoapods",  "~> 1.15"     # Se usar CocoaPods (opcional)
```

---

## 11. GitHub Secrets Necessários (com Fastlane)

| Secret | Descrição |
|:---|:---|
| `APPSTORE_KEY_ID` | ID da API Key do App Store Connect |
| `APPSTORE_ISSUER_ID` | Issuer UUID da API Key |
| `APPSTORE_PRIVATE_KEY` | Conteúdo completo do arquivo `.p8` |
| `APPLE_TEAM_ID` | Team ID de 10 caracteres |
| `ITC_TEAM_ID` | Team ID do App Store Connect (pode ser diferente) |
| `MATCH_GIT_URL` | URL do repositório privado de certificados |
| `MATCH_PASSWORD` | Senha de encriptação do match |
| `MATCH_DEPLOY_KEY` | Chave SSH privada para acessar o repo de certs |

---

## 12. Fluxo Completo de Git Branches

```
feature/pull-down-analyzer
        │ PR (roda: fastlane test)
        ▼
   develop  ──────────────────────────────► (testes automáticos)
        │
        │ merge + push
        ▼
     main  ────────────────────────────────► fastlane beta
        │                                    └── TestFlight
        │ tag v1.0.0
        ▼
    release ──────────────────────────────► fastlane release
                                             └── App Store
```

---

## 13. Checklist de Setup para o Agente (Ordem de Execução)

### Pré-Setup (Único Mac de Aluguel — 30 minutos):
- [ ] Criar repositório privado de certificados: `ios-certs-private`
- [ ] Instalar Fastlane: `gem install fastlane`
- [ ] Rodar `fastlane match init` e apontar para o repo privado
- [ ] Rodar `fastlane setup_certs` para gerar e armazenar certificados
- [ ] Gerar chave SSH de deploy e adicionar ao repo privado de certs
- [ ] Adicionar todos os 8 secrets no repositório `aofrio-pulldown-ios`

### Desenvolvimento (100% sem Mac — seu Windows):
- [ ] Criar estrutura de pastas `fastlane/` com Fastfile, Appfile, Matchfile, Gymfile
- [ ] Criar `Gemfile` com versões pinadas
- [ ] Adicionar `.github/workflows/testflight.yml`
- [ ] Implementar o código SwiftUI normalmente
- [ ] `git push origin main` → Fastlane cuida do resto automaticamente
