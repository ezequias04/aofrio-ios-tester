@echo off
chcp 65001 >nul
title AoFrio iOS Dev — Instalador Automatico
color 0B

echo.
echo ============================================================
echo   AOFRIO iOS DEV — INSTALADOR AUTOMATICO
echo   Instala todas as ferramentas via winget e npm
echo   Execute como ADMINISTRADOR para melhores resultados
echo ============================================================
echo.
echo Pressione qualquer tecla para iniciar a instalacao...
pause >nul

echo.
echo [1/5] Instalando Ruby 3.2 com DevKit (Fastlane)...
echo       Aguarde, pode demorar alguns minutos...
winget install RubyInstallerTeam.RubyWithDevKit.3.2 --silent --accept-package-agreements --accept-source-agreements
if %ERRORLEVEL% == 0 (echo [OK] Ruby instalado com sucesso!) else (echo [AVISO] Ruby pode ja estar instalado ou ocorreu um erro.)

echo.
echo [2/5] Instalando VS Code...
winget install Microsoft.VisualStudioCode --silent --accept-package-agreements --accept-source-agreements
if %ERRORLEVEL% == 0 (echo [OK] VS Code instalado com sucesso!) else (echo [AVISO] VS Code pode ja estar instalado.)

echo.
echo [3/5] Instalando ios-builder via npm...
npm install -g @mobai/ios-builder
if %ERRORLEVEL% == 0 (echo [OK] ios-builder instalado!) else (echo [AVISO] Instale manualmente: https://github.com/MobAI-App/ios-builder/releases)

echo.
echo [4/5] Instalando Fastlane via gem...
echo       (Requer Ruby instalado - abra novo terminal se Ruby foi instalado agora)
call gem install fastlane 2>nul
if %ERRORLEVEL% == 0 (echo [OK] Fastlane instalado!) else (echo [AVISO] Reabra o terminal e rode: gem install fastlane)

echo.
echo [5/5] Instalando Bundler via gem...
call gem install bundler 2>nul
if %ERRORLEVEL% == 0 (echo [OK] Bundler instalado!) else (echo [AVISO] Reabra o terminal e rode: gem install bundler)

echo.
echo ============================================================
echo   INSTALACAO CONCLUIDA!
echo.
echo   PROXIMOS PASSOS:
echo   1. FECHE e REABRA o PowerShell/CMD (atualiza o PATH)
echo   2. Execute: verificar-ferramentas.bat
echo   3. Leia: SETUP-FERRAMENTAS.md para configurar o projeto
echo ============================================================
echo.
pause
