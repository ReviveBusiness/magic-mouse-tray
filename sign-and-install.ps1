# Sign and install the patched AppleWirelessMouse driver for PID 0323
# Run as Administrator in PowerShell
# Requires: DSE-disabled boot (already done) OR test signing mode (this script enables it)
#
# Driver files must be in a 'driver' subfolder next to this script:
#   driver\AppleWirelessMouse.inf
#   driver\applewirelessmouse.cat
#   driver\AppleWirelessMouse.sys

$DRIVER_DIR = Join-Path $PSScriptRoot "driver"
$INF = Join-Path $DRIVER_DIR "AppleWirelessMouse.inf"
$CAT = Join-Path $DRIVER_DIR "applewirelessmouse.cat"

if (-not (Test-Path $INF)) {
    Write-Error "Driver files not found. Expected: $INF`nDownload from: https://github.com/tealtadpole/MagicMouse2DriversWin11x64"
    exit 1
}

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

# Step 7 - Remove any existing AppleWirelessMouse driver packages (dynamic — not hardcoded slot)
Write-Host "Step 7: Removing existing Apple driver packages..."
$pnpRaw = (pnputil /enum-drivers 2>$null) | Out-String
$existing = ($pnpRaw -split '(?=Published Name:)') |
    Where-Object { $_ -match 'applewirelessmouse' } |
    ForEach-Object { if ($_ -match 'Published Name:\s+(oem\d+\.inf)') { $Matches[1] } }
if ($existing) {
    $existing | ForEach-Object {
        Write-Host "  Removing $_..."
        pnputil /delete-driver $_ /force 2>$null | Out-Null
    }
} else {
    Write-Host "  No existing AppleWirelessMouse driver found — skipping"
}

# Step 8 - Install the now-signed package
Write-Host "Step 8: Installing signed driver package..."
pnputil /add-driver $INF /install /force

Write-Host ""
Write-Host "Done. Now:"
Write-Host "  1. Remove the Magic Mouse from Bluetooth Settings"
Write-Host "  2. Re-pair it"
Write-Host "  3. Test scroll"
Write-Host "  4. Reboot normally (test signing takes effect at next boot)"
Write-Host ""
Write-Host "After scroll is confirmed working post-reboot:"
Write-Host "  bcdedit /set testsigning off  (then reboot — watermark gone, driver stays)"
