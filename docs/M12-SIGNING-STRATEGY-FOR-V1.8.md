# M12 Signing Strategy for v1.8

## 1. BLUF

M12 v1 ships as a self-signed driver with a cert-trust install script (same pattern as `MagicMouseFix` / Rain9333). User runs admin install once; cert lands in Trusted Root + Trusted Publisher; driver loads on production Windows; no testsigning, no watermark, no EV cert cost. v2 production path (Microsoft attestation signing) remains a future option for broad distribution.

## 2. Empirical Evidence

Verified on dev machine 2026-04-28:

```
Subject: CN=MagicMouseFix
Issuer:  CN=MagicMouseFix (self-signed)
NotAfter: 2036-04-21 15:50:32
Stores: LocalMachine\Root + LocalMachine\TrustedPublisher
Result: Driver loads cleanly on production Windows without testsigning mode
        No "Test Mode" watermark visible
```

Reference: PRB observation 2026-04-28 — MagicMouseFix driver (`applewirelessmouse.sys`) loads without requiring testsigning or EV certificate.

## 3. M12 v1 Signing Pipeline

### 3a. Cert generation (one-time, by Lesley/Revive Business Solutions)

PowerShell to generate the M12 code-signing cert:

```powershell
$cert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject "CN=M12-Driver, O=Revive Business Solutions" `
  -KeyAlgorithm RSA `
  -KeyLength 2048 `
  -KeyUsage DigitalSignature `
  -KeyUsageProperty Sign `
  -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(10) `
  -CertStoreLocation Cert:\CurrentUser\My

# Export public cert (.cer) for distribution
Export-Certificate -Cert $cert -FilePath "M12-Driver.cer"

# Export private key (.pfx) — keep OFFLINE in secure storage, NEVER commit
$pwd = ConvertTo-SecureString -String "<strong-password>" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "M12-Driver.pfx" -Password $pwd
```

Output:
- `M12-Driver.cer` — public, ships with installer
- `M12-Driver.pfx` — private, kept offline (NOT in git, NOT in any repo)

### 3b. Driver signing (build harness)

```powershell
# Sign M12.sys
signtool sign /v /f M12-Driver.pfx /p <password> /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 M12.sys

# Sign M12.cat (catalog)
inf2cat /driver:M12-pkg /os:10_x64,11_x64
signtool sign /v /f M12-Driver.pfx /p <password> /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 M12.cat
```

`/tr` adds timestamp so signature stays valid past cert expiration.

### 3c. End-user install script (`scripts/install-m12-trust.ps1`)

```powershell
# Run as admin one-time before driver install
[CmdletBinding()]param([string]$CertFile = "M12-Driver.cer")
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $CertFile)) { throw "Cert file not found: $CertFile" }

Import-Certificate -FilePath $CertFile -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Import-Certificate -FilePath $CertFile -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null

Write-Host "M12 code-signing cert trusted. Now run install-m12.ps1 to install the driver." -ForegroundColor Green
```

### 3d. End-user driver install (after cert trusted)

```powershell
# Standard pnputil install — driver now loads without testsigning
pnputil /add-driver M12.inf /install
```

## 4. Security Considerations

| Risk | Mitigation |
|---|---|
| Private key (.pfx) leak — attackers could sign malicious drivers as M12 | Keep .pfx offline (encrypted USB or hardware token). Never commit to git. Use strong password. |
| Cert in Trusted Root = anything signed by M12 cert is trusted | Acceptable for personal use; document explicitly so users understand. |
| User runs install-m12-trust.ps1 without verifying cert thumbprint | Document expected thumbprint in INSTALL.md so user can verify before trusting. |
| Cert renewal at 10-year mark | Document renewal procedure; ship new cert as a re-install. |

## 5. Comparison: Signing Options for M12

| Option | Cost | UX | When to use |
|---|---|---|---|
| **Self-signed + cert-trust install** (THIS PLAN for v1) | $0 | Clean — no watermark, install once via admin script | v1: open-source distribution, personal use, small audience |
| Test-signing only (testsigning mode) | $0 | "Test Mode" watermark visible, requires BCD edit + reboot | Dev/testing only |
| Microsoft attestation signing | ~$300-500/yr EV cert | Cleanest — production trust, no user trust step | v2: broad public distribution |
| Full WHQL submission | $300-500/yr cert + HLK + weeks | Best — Windows Update distribution | v3+: only if needed |

## 6. Decisions for v1.8 Design + PRD

In design spec: ADD section "Signing Strategy" referencing this brief. The previous v1.4-v1.6 references to "test-signed for v1" must be UPDATED to "self-signed + cert-trust install for v1, test-signing as fallback if user prefers."

In MOP:
- Pre-install step: run `install-m12-trust.ps1` (one-time, admin) to trust M12 cert
- Document expected cert thumbprint for user verification
- Remove the "verify testsigning enabled" pre-flight (no longer required)
- KEEP testsigning verification as a FALLBACK option for users who prefer not to trust certs

In PRD: Add decisions D-S12-59 / D-S12-60 / D-S12-61:
- D-S12-59: M12 v1 distribution = self-signed cert (CN=M12-Driver) + admin trust-install script — APPROVED
- D-S12-60: Cert .pfx kept offline in secure storage, never committed — APPROVED
- D-S12-61: Test-signing remains a documented fallback for users who decline to trust M12 cert — APPROVED

## 7. References

- PRB observation 2026-04-28: MagicMouseFix cert in Trusted Root + TrustedPublisher
- Microsoft Learn: PowerShell `New-SelfSignedCertificate -Type CodeSigningCert`
- Microsoft Learn: signtool documentation
- Rain9333 / MagicMouseFix model — empirically validated on dev machine 2026-04-28
