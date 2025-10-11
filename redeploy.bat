@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

REM ============================================================================
REM            Flutter App One-Click Deployment Script (Final Version)
REM ============================================================================
REM
REM  此脚本会自动执行以下操作:
REM  1. 检查 gh-cli 是否已登录。
REM  2. 检查签名密钥文件是否存在。
REM  3. 使用 PowerShell 生成纯净的 Base64 编码。
REM  4. 更新 GitHub Secrets。
REM  5. 提示输入版本号和更新日志。
REM  6. 触发 'release.yml' 工作流来构建和发布应用。
REM
REM ============================================================================

REM --- 配置变量 ---
SET KEYSTORE_FILE=keystore.jks
SET WORKFLOW_FILE=release.yml
SET TARGET_BRANCH=main

REM --- 1. 检查 gh-cli 登录状态 ---
echo 正在检查 GitHub CLI 登录状态...
gh auth status > nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [91m错误: 您尚未登录 GitHub CLI。 [0m
    echo 请先运行 'gh auth login' 命令进行登录，然后再重新运行此脚本。
    goto :end
)
echo 登录状态正常。
echo.

REM --- 2. 检查文件是否存在 ---
if not exist "%KEYSTORE_FILE%" (
    echo  [91m错误: 签名密钥文件 '%KEYSTORE_FILE%' 不存在。 [0m
    echo 请确保签名密钥文件与此脚本位于同一目录。
    goto :end
)
echo 必要的本地文件已找到。
echo.

REM --- 3. 更新机密信息 ---
echo  [96m--- 准备更新 GitHub Secrets --- [0m
echo.

echo 正在使用 PowerShell 对 '%KEYSTORE_FILE%' 进行纯净的 Base64 编码...
powershell -Command "[convert]::ToBase64String([IO.File]::ReadAllBytes('%KEYSTORE_FILE%'))" > keystore.b64
echo 编码完成。
echo.

echo 正在更新 KEYSTORE_BASE64...
gh secret set KEYSTORE_BASE64 < keystore.b64
if %errorlevel% neq 0 (
    echo  [91m错误: 更新 KEYSTORE_BASE64 失败。 [0m
    del keystore.b64
    goto :end
)
del keystore.b64
echo 机密更新成功。
echo.

set /p KEY_ALIAS="请输入密钥别名 (Key Alias): "
gh secret set KEY_ALIAS --body "%KEY_ALIAS%"
if %errorlevel% neq 0 (
    echo  [91m错误: 更新 KEY_ALIAS 失败。 [0m
    goto :end
)
echo.

set /p KEY_PASSWORD="请输入密钥密码 (Key Password): "
gh secret set KEY_PASSWORD --body "%KEY_PASSWORD%"
if %errorlevel% neq 0 (
    echo  [91m错误: 更新 KEY_PASSWORD 失败。 [0m
    goto :end
)
echo.

set /p STORE_PASSWORD="请输入密钥库密码 (Store Password): "
gh secret set STORE_PASSWORD --body "%STORE_PASSWORD%"
if %errorlevel% neq 0 (
    echo  [91m错误: 更新 STORE_PASSWORD 失败。 [0m
    goto :end
)
echo.
echo  [92m所有机密信息均已成功更新！ [0m
echo.

REM --- 4. 触发工作流 ---
echo  [96m--- 准备触发部署工作流 --- [0m
echo.
set /p VERSION="请输入版本号 (例如: 1.0.1): "
set /p CHANGELOG="请输入此版本的更新日志: "
echo.

echo 正在从 '%TARGET_BRANCH%' 分支触发 '%WORKFLOW_FILE%'...
gh workflow run %WORKFLOW_FILE% --ref %TARGET_BRANCH% -f version=%VERSION% -f changelog="%CHANGELOG%"
if %errorlevel% neq 0 (
    echo  [91m错误: 触发工作流失败。 [0m
    goto :end
)
echo.
echo  [92m成功触发部署！ [0m
echo 请访问您的 GitHub Actions 页面查看构建和发布进度。
echo.

:end
pause