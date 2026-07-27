package test

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func prepareEnv() []string {
	env := os.Environ()
	dockerBin := `C:\Program Files\Docker\Docker\resources\bin`
	pathKey := "PATH"
	for i, e := range env {
		if strings.HasPrefix(strings.ToUpper(e), "PATH=") {
			parts := strings.SplitN(e, "=", 2)
			pathKey = parts[0]
			env[i] = pathKey + "=" + dockerBin + string(filepath.ListSeparator) + parts[1]
			return env
		}
	}
	return append(env, "PATH="+dockerBin)
}

func getDockerCmd() string {
	if path, err := exec.LookPath("docker"); err == nil {
		return path
	}
	return `C:\Program Files\Docker\Docker\resources\bin\docker.exe`
}

func extractBinaryHash(dockerExe string, env []string, imageName string, tempName string) (string, error) {
	containerName := fmt.Sprintf("temp-%s", tempName)
	tempFile := fmt.Sprintf("./temp_binary_%s", tempName)
	defer os.Remove(tempFile)

	// 1. Create temporary container
	cmdCreate := exec.Command(dockerExe, "create", "--name", containerName, imageName)
	cmdCreate.Env = env
	if out, err := cmdCreate.CombinedOutput(); err != nil {
		return "", fmt.Errorf("docker create failed: %v, output: %s", err, string(out))
	}
	defer func() {
		cmdRm := exec.Command(dockerExe, "rm", "-f", containerName)
		cmdRm.Env = env
		_ = cmdRm.Run()
	}()

	// 2. Copy binary from scratch container to host
	cmdCp := exec.Command(dockerExe, "cp", fmt.Sprintf("%s:/zuko-rule-engine", containerName), tempFile)
	cmdCp.Env = env
	if out, err := cmdCp.CombinedOutput(); err != nil {
		return "", fmt.Errorf("docker cp failed: %v, output: %s", err, string(out))
	}

	// 3. Compute SHA-256 hash of extracted binary
	f, err := os.Open(tempFile)
	if err != nil {
		return "", fmt.Errorf("open binary failed: %v", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("hashing binary failed: %v", err)
	}

	return hex.EncodeToString(h.Sum(nil)), nil
}

func TestReproducibleDockerBuildStrict(t *testing.T) {
	dockerExe := getDockerCmd()
	env := prepareEnv()

	// ------------------------------------------------------------------
	// HARD GUARD: Verify Docker Daemon is Active
	// ------------------------------------------------------------------
	cmdCheck := exec.Command(dockerExe, "info")
	cmdCheck.Env = env
	if err := cmdCheck.Run(); err != nil {
		t.Fatalf("\n\n" +
			"=======================================================================\n" +
			"❌ FATAL ERROR: STRICT NO-MOCK POLICY VIOLATION\n" +
			"=======================================================================\n" +
			"Docker daemon is NOT running on your system!\n" +
			"Project Zuko strict policy forbids running host-native `go.exe` fallbacks.\n" +
			"Please start Docker Desktop and run this test again.\n" +
			"=======================================================================\n\n")
	}

	// ------------------------------------------------------------------
	// BUILD CONTAINER 1
	// ------------------------------------------------------------------
	t.Log("🐳 Building Container Image #1 (SOURCE_DATE_EPOCH=0)...")
	cmd1 := exec.Command(dockerExe, "build", "--no-cache", "-t", "zuko-enclave:build1", "-f", "../Dockerfile", "..")
	cmd1.Env = env
	if out, err := cmd1.CombinedOutput(); err != nil {
		t.Fatalf("Container 1 build failed: %v\nOutput:\n%s", err, string(out))
	}

	hash1, err := extractBinaryHash(dockerExe, env, "zuko-enclave:build1", "build1")
	if err != nil {
		t.Fatalf("Failed to extract hash for build 1: %v", err)
	}
	t.Logf("📦 Container Image #1 SHA-256: %s", hash1)

	// ------------------------------------------------------------------
	// BUILD CONTAINER 2
	// ------------------------------------------------------------------
	t.Log("🐳 Building Container Image #2 (Clean Rebuild)...")
	cmd2 := exec.Command(dockerExe, "build", "--no-cache", "-t", "zuko-enclave:build2", "-f", "../Dockerfile", "..")
	cmd2.Env = env
	if out, err := cmd2.CombinedOutput(); err != nil {
		t.Fatalf("Container 2 build failed: %v\nOutput:\n%s", err, string(out))
	}

	hash2, err := extractBinaryHash(dockerExe, env, "zuko-enclave:build2", "build2")
	if err != nil {
		t.Fatalf("Failed to extract hash for build 2: %v", err)
	}
	t.Logf("📦 Container Image #2 SHA-256: %s", hash2)

	// ------------------------------------------------------------------
	// ASSERT STRICT BIT-FOR-BIT EQUALITY
	// ------------------------------------------------------------------
	if hash1 != hash2 {
		t.Fatalf("❌ REPRODUCIBLE BUILD FAILED!\nHash 1: %s\nHash 2: %s", hash1, hash2)
	}

	t.Logf("✅ STRICT REPRODUCIBLE DOCKER BUILD VERIFIED: %s", hash1)
}
