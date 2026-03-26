@echo off
echo Monitoring Firebase current data for fall detection...
echo Press Ctrl+C to stop
:loop
powershell -Command "Invoke-WebRequest -Uri 'https://mental-healthmonitor-default-rtdb.firebaseio.com/devices/MXCHIP_001/current.json' -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json | Select-Object fall_detected, fall_confidence, @{Name='last_fall_detected';Expression={$_.last_fall.detected}}, @{Name='last_fall_confidence';Expression={$_.last_fall.confidence}}, @{Name='timestamp';Expression={$_.timestamp}}" 2>nul
timeout /t 2 /nobreak > nul
goto loop