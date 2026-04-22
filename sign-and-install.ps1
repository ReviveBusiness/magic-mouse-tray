# Sign and install the patched AppleWirelessMouse driver for PID 0323
# Run as Administrator in PowerShell
# Requires: DSE-disabled boot (already done) OR test signing mode (this script enables it)

$INF = "D:\Users\Lesley\Downloads\MagicMouse2DriversWin11x64-master\AppleWirelessMouse\AppleWirelessMouse.inf"
$DRIVER_DIR = "D:\Users\Lesley\Downloads\MagicMouse2DriversWin11x64-master\AppleWirelessMouse"
$CAT = "$DRIVER_DIR\applewirelessmouse.cat"

# Step 1 - Create a self-signed code signing cert
Write-Host "Step 1: Creating self-signed certificate..."
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=MagicMouseFix" `
    -CertStoreLocation Cert:\LocalMachine\My `
    -KeyUsage DigitalSignature `
    -NotAfter (Get-Date).AddYears(10)

New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
$certPath = "C:\Temp\MagicMouseFix.cer"
Export-Certificate -Cert $cert -FilePath $certPath -Force | Out-Null
Write-Host "  Certificate created: $($cert.Thumbprint)"

# Step 2 - Trust the cert (required for Windows to accept test-signed drivers)
Write-Host "Step 2: Trusting certificate..."
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

# Step 3 - Re-enable CatalogFile line in INF (we commented it out earlier)
Write-Host "Step 3: Restoring CatalogFile line in INF..."
$content = Get-Content $INF -Raw
$content = $content -replace '; CatalogFile=applewirelessmouse.cat', 'CatalogFile=applewirelessmouse.cat'
[System.IO.File]::WriteAllText($INF, $content)

# Step 4 - Generate catalog from driver directory
Write-Host "Step 4: Generating file catalog..."
if (Test-Path $CAT) { Remove-Item $CAT -Force }
New-FileCatalog -Path $DRIVER_DIR -CatalogFilePath $CAT -CatalogVersion 2 | Out-Null
Write-Host "  Catalog created: $CAT"

# Step 5 - Sign the catalog
Write-Host "Step 5: Signing catalog..."
$sig = Set-AuthenticodeSignature -FilePath $CAT -Certificate $cert
Write-Host "  Signature status: $($sig.Status)"

# Step 6 - Enable test signing (allows test-signed drivers to be selected and loaded)
Write-Host "Step 6: Enabling test signing mode..."
bcdedit /set testsigning on | Out-Null
Write-Host "  Test signing enabled (small watermark will appear after reboot - removable later)"

# Step 7 - Remove old unsigned oem53
Write-Host "Step 7: Removing old unsigned driver package..."
pnputil /delete-driver oem53.inf /force 2>$null | Out-Null

# Step 8 - Install the now-signed package
Write-Host "Step 8: Installing signed driver package..."
pnputil /add-driver $INF /install /force

# Step 9 - Register startup repair task (runs startup-repair.ps1 at every boot)
Write-Host "Step 9: Registering startup repair task..."
$repairScript = Join-Path $PSScriptRoot "startup-repair.ps1"
if (Test-Path $repairScript) {
    $taskName = "MagicMouseTray-StartupRepair"
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($taskExists) {
        Write-Host "  Task '$taskName' already registered — skipping"
    } else {
        $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$repairScript`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $trigger.Delay = "PT30S"   # 30-second delay to let BT stack initialise
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

        Register-ScheduledTask -TaskName $taskName -Action $action `
            -Trigger $trigger -Settings $settings -Principal $principal `
            -Description "Repairs Magic Mouse COL02 battery HID collection at startup" `
            -Force | Out-Null
        Write-Host "  Task '$taskName' registered (runs at startup with 30s delay, as SYSTEM)"
    }
} else {
    Write-Host "  WARNING: startup-repair.ps1 not found at $repairScript — skipping task registration"
    Write-Host "  For persistent battery reading across reboots, run Register-ScheduledTask manually."
}

Write-Host ""
Write-Host "Done. Now:"
Write-Host "  1. Remove the Magic Mouse from Bluetooth Settings"
Write-Host "  2. Re-pair it"
Write-Host "  3. Test scroll"
Write-Host "  4. Reboot normally (test signing takes effect at next boot)"
Write-Host "     Battery reading will be auto-repaired by the startup task."
Write-Host ""
Write-Host "After scroll is confirmed working post-reboot:"
Write-Host "  bcdedit /set testsigning off  (then reboot — watermark gone, driver stays)"
