Write-Host "Monitoring Firebase for fall detection updates..." -ForegroundColor Green
while ($true) {
    try {
        $response = Invoke-WebRequest -Uri "https://mental-healthmonitor-default-rtdb.firebaseio.com/devices/MXCHIP_001/current.json" -UseBasicParsing -TimeoutSec 5
        $data = $response.Content | ConvertFrom-Json
        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] fall_detected: $($data.fall_detected), confidence: $($data.fall_confidence), last_fall: $($data.last_fall.detected), ts: $($data.timestamp)" -ForegroundColor Yellow
    } catch {
        Write-Host "Error fetching data: $($_.Exception.Message)" -ForegroundColor Red
    }
    Start-Sleep -Seconds 1
}