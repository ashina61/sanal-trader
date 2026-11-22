@echo off
cd /d "%~dp0.."
flutter create --platforms=android --org com.example --project-name sanal_trader .
if errorlevel 1 exit /b 1
flutter pub get
if errorlevel 1 exit /b 1
flutter run
