---
name: test_tee_docker
description: Run strict containerized Docker build and binary hash verification for the Go TEE enclave.
---

# Verify TEE Docker Reproducible Build

Execute the containerized TEE reproducible build test suite:

```powershell
# 1. Assert Docker Daemon Status
docker info
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ FATAL: Docker Desktop is offline. Aborting TEE verification." -ForegroundColor Red
    exit 1
}

# 2. Run Reproducible Docker Build Test
Set-Location packages/rule-engine
& "C:\Program Files\Go\bin\go.exe" test -v ./test/reproducible_build_test.go
Set-Location ../..
```
