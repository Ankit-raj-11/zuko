---
name: audit_no_mocks
description: Audit the codebase for hardcoded contract addresses, silent error fallbacks, host compiler bypasses, Docker hardware guards, and safety gates.
---

# Audit No-Mock & No-Bypass Compliance

Execute the following PowerShell commands sequentially and report the compliance status:

```powershell
# 1. Audit Hardcoded Contract Addresses (excluding ContractRegistry and ZeroAddress)
Write-Host "`n=== 1. HARDCODED ADDRESS AUDIT ===" -ForegroundColor Cyan
Get-ChildItem -Path packages/backend/src, packages/rule-engine -Recurse -Include *.ts, *.go | 
    Where-Object { $_.Name -notmatch "_test\.|\.test\." } | 
    Select-String -Pattern "0x[0-9a-fA-F]{40}" | 
    Where-Object { $_.Line -notmatch "0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019" -and $_.Line -notmatch "0x0000000000000000000000000000000000000000" } | 
    Tee-Object -FilePath audit_addresses.txt

# 2. Audit Silent Error Fallbacks in Backend Data Layer
Write-Host "`n=== 2. SILENT FALLBACK AUDIT ===" -ForegroundColor Cyan
Get-ChildItem -Path packages/backend/src -Recurse -Include *.ts | 
    Where-Object { $_.FullName -notmatch "node_modules" } | 
    Select-String -Pattern "catch.*return \[\]","catch.*return {}","catch.*return null","catch.*return 0","catch.*return false" | 
    Tee-Object -FilePath audit_fallbacks.txt

# 3. Audit Bypasses & Host Compilation Shortcuts in TEE Tests
Write-Host "`n=== 3. TEE HOST BYPASS AUDIT ===" -ForegroundColor Cyan
Get-ChildItem -Path packages/rule-engine -Recurse -Include *.go | 
    Select-String -Pattern 'exec\.Command\("go"' | 
    Tee-Object -FilePath audit_host_bypasses.txt

# 4. Check Docker Daemon Enforcement in TEE Verification Tests
Write-Host "`n=== 4. DOCKER DAEMON GUARD CHECK ===" -ForegroundColor Cyan
Get-ChildItem -Path packages/rule-engine -Recurse -Include *.go | 
    Select-String -Pattern 'exec\.Command\("docker", "info"\)' | 
    Tee-Object -FilePath audit_docker_guard.txt

# 5. Check Rule 3 Cold-Start Gate
Write-Host "`n=== 5. RULE 3 COLD-START GATE CHECK ===" -ForegroundColor Cyan
Get-ChildItem -Path packages/backend/src -Recurse -Include *.ts | 
    Select-String -Pattern "rule3Enabled"

# 6. Check 2-Block Micro-Reorg Confirmation Lag
Write-Host "`n=== 6. CONFIRMATION LAG CHECK ===" -ForegroundColor Cyan
Get-ChildItem -Path packages/backend/src -Recurse -Include *.ts | 
    Select-String -Pattern "CONFIRMATION_LAG"
```
