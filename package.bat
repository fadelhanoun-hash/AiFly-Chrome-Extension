@echo off
REM AiFly Chrome Extension Packaging Script
REM This script creates a properly formatted zip file for Chrome Web Store submission

echo AiFly Packaging Script
echo ==========================
echo.

REM Get the current directory
set "SCRIPT_DIR=%~dp0"
REM Remove trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "PROJECT_NAME=AiFly"
set "TEMP_DIR=%SCRIPT_DIR%\.temp_package"

REM Generate timestamp
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "DATETIME=%%I"
set "TIMESTAMP=%DATETIME:~0,8%_%DATETIME:~8,6%"
set "OUTPUT_FILE=%SCRIPT_DIR%\%PROJECT_NAME%_%TIMESTAMP%.zip"

echo Project directory: %SCRIPT_DIR%
echo Output file: %OUTPUT_FILE%
echo.

REM Clean up any previous temp directory
if exist "%TEMP_DIR%" (
    rmdir /s /q "%TEMP_DIR%"
)

REM Create temp directory
mkdir "%TEMP_DIR%"

echo Copying extension files...

REM Copy all necessary files
copy "%SCRIPT_DIR%\manifest.json"     "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\background.js"     "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\content.js"        "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\options.html"      "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\options.js"        "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\messenger.css"     "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\README.md"         "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\PRIVACY_POLICY.md" "%TEMP_DIR%\" >nul
copy "%SCRIPT_DIR%\STORE_LISTING.md"  "%TEMP_DIR%\" >nul

REM Copy icons folder
xcopy /e /i /q "%SCRIPT_DIR%\icons" "%TEMP_DIR%\icons\" >nul

echo Files copied successfully
echo.

REM Create the zip file using PowerShell (available on Windows 8+)
echo Creating zip archive...
powershell -NoProfile -Command "Compress-Archive -Path '%TEMP_DIR%\*' -DestinationPath '%OUTPUT_FILE%' -Force"

REM Check if zip was created successfully
if exist "%OUTPUT_FILE%" (
    echo Zip file created successfully!
    echo.
    echo Package Information:
    echo   Filename: %PROJECT_NAME%_%TIMESTAMP%.zip
    echo   Location: %OUTPUT_FILE%
    echo.
    echo Package Contents:
    echo   [OK] manifest.json
    echo   [OK] background.js
    echo   [OK] content.js
    echo   [OK] options.html
    echo   [OK] options.js
    echo   [OK] messenger.css
    echo   [OK] icons/ (icon-16.png, icon-48.png, icon-128.png)
    echo   [OK] README.md
    echo   [OK] PRIVACY_POLICY.md
    echo   [OK] STORE_LISTING.md
    echo.
    echo Ready for Chrome Web Store submission!
    echo.
    echo Next steps:
    echo 1. Go to https://chrome.google.com/webstore/devcenter
    echo 2. Sign in with your Google account
    echo 3. Click 'Create new item'
    echo 4. Upload the zip file: %OUTPUT_FILE%
    echo 5. Fill in the store listing details
    echo 6. Submit for review
) else (
    echo ERROR: Failed to create zip file
    rmdir /s /q "%TEMP_DIR%"
    exit /b 1
)

REM Cleanup temp directory
rmdir /s /q "%TEMP_DIR%"

exit /b 0
