---
name: test_all_phases
description: Run the master test suite covering smart contracts, backend TypeScript tests, and TEE Docker builds.
---

# Run Full Project Test Suite

Execute all phase test suites in sequential order:

```powershell
# 1. Run Foundry Smart Contract & Invariant Fuzz Suites
Write-Host "`n=== RUNNING FOUNDRY SUITE ===" -ForegroundColor Cyan
Set-Location packages/contracts
forge test -vvv
Set-Location ../..

# 2. Run Backend TypeScript Tests
Write-Host "`n=== RUNNING BACKEND SUITE ===" -ForegroundColor Cyan
Set-Location packages/backend
npx ts-node test/backend.test.ts
Set-Location ../..

# 3. Run Strict TEE Docker Verification
Write-Host "`n=== RUNNING TEE DOCKER SUITE ===" -ForegroundColor Cyan
Set-Location packages/rule-engine
& "C:\Program Files\Go\bin\go.exe" test -v ./test/reproducible_build_test.go
Set-Location ../..
```
