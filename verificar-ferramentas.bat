@echo off
chcp 65001 >nul
title AoFrio iOS Dev — Verificador de Ferramentas
color 0A

echo.
echo ============================================================
echo   AOFRIO iOS DEV — VERIFICADOR DE FERRAMENTAS
echo   Verifica todas as dependencias necessarias para o projeto
echo ============================================================
echo.

set ERROS=0

:: Git
git --version >nul 2>&1
if %ERRORLEVEL% == 0 (
    for /f "tokens=*" %%i in ('git --version') do echo [OK] Git: %%i
) else (
    echo [FALTA] Git — Instale em: https://git-scm.com
    set /a ERROS+=1
)

:: Node.js
node --version >nul 2>&1
if %ERRORLEVEL% == 0 (
    for /f "tokens=*" %%i in ('node --version') do echo [OK] Node.js: %%i
) else (
    echo [FALTA] Node.js — winget install OpenJS.NodeJS
    set /a ERROS+=1
)

:: Ruby
ruby --version >nul 2>&1
if %ERRORLEVEL% == 0 (
    for /f "tokens=*" %%i in ('ruby --version') do echo [OK] Ruby: %%i
) else (
    echo [FALTA] Ruby — winget install RubyInstallerTeam.RubyWithDevKit.3.2
    set /a ERROS+=1
)

:: Fastlane
fastlane --version >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo [OK] Fastlane: instalado
) else (
    echo [FALTA] Fastlane — gem install fastlane
    set /a ERROS+=1
)

:: GitHub CLI
gh --version >nul 2>&1
if %ERRORLEVEL% == 0 (
    for /f "tokens=1-3" %%i in ('gh --version') do echo [OK] GitHub CLI: %%i %%j %%k
) else (
    echo [FALTA] GitHub CLI — winget install GitHub.cli
    set /a ERROS+=1
)

:: ios-builder
builder --version >nul 2>&1
if %ERRORLEVEL% == 0 (
    for /f "tokens=*" %%i in ('builder --version') do echo [OK] ios-builder: %%i
) else (
    echo [FALTA] ios-builder — npm install -g @mobai/ios-builder
    set /a ERROS+=1
)

:: VS Code
code --version >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo [OK] VS Code: instalado
) else (
    echo [FALTA] VS Code — winget install Microsoft.VisualStudioCode
    set /a ERROS+=1
)

echo.
echo ============================================================
if %ERROS% == 0 (
    echo   TUDO PRONTO! Voce pode comecar a desenvolver.
    echo   Proximo passo: leia o arquivo SETUP-FERRAMENTAS.md
) else (
    echo   ATENCAO: %ERROS% ferramenta(s) faltando.
    echo   Siga os passos em SETUP-FERRAMENTAS.md para instalar.
)
echo ============================================================
echo.
pause
