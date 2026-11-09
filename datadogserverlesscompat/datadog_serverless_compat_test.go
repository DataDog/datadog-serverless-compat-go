// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2025-present Datadog, Inc.

package datadogserverlesscompat

import (
	"os"
	"os/exec"
	"runtime"
	"strings"
	"testing"
)

func TestMain(m *testing.M) {
	code := m.Run()
	os.Exit(code)
}

func TestChildVersionEnvironment(t *testing.T) {
	t.Setenv("DD_SERVERLESS_COMPAT_VERSION", "stale")
	t.Setenv("GO_VERSION", "stale")
	t.Setenv("DD_SERVERLESS_COMPAT_RUNTIME", "stale")
	t.Setenv("DD_SERVICE", "keep-me")
	child := exec.Command("/custom/compat")
	setPackageVersion(child)
	for _, expected := range []string{
		"DD_SERVERLESS_COMPAT_VERSION=" + Version,
		"DD_SERVERLESS_COMPAT_RUNTIME=" + runtime.Version(),
		"GO_VERSION=stale",
		"DD_SERVICE=keep-me",
	} {
		if !strings.Contains("\n"+strings.Join(child.Environ(), "\n")+"\n", "\n"+expected+"\n") {
			t.Errorf("child environment missing %q", expected)
		}
	}
	for _, key := range []string{"DD_SERVERLESS_COMPAT_VERSION", "DD_SERVERLESS_COMPAT_RUNTIME", "GO_VERSION"} {
		if got := os.Getenv(key); got != "stale" {
			t.Errorf("parent %s changed to %q", key, got)
		}
	}
}

func TestGetEnvironment(t *testing.T) {
	// Test Google Cloud Run Function environment
	os.Unsetenv("FUNCTIONS_EXTENSION_VERSION")
	os.Unsetenv("FUNCTIONS_WORKER_RUNTIME")
	os.Setenv("FUNCTION_NAME", "test-function")
	os.Setenv("GCP_PROJECT", "test-project")
	env := getEnvironment()
	if env != GoogleCloudRunFunction1stGen {
		t.Errorf("Expected GoogleCloudRunFunction1stGen environment, got %v", env)
	}

	// Test Unknown environment
	os.Unsetenv("FUNCTION_NAME")
	os.Unsetenv("GCP_PROJECT")
	env = getEnvironment()
	if env != Unknown {
		t.Errorf("Expected Unknown environment, got %v", env)
	}
}

func TestGetBinaryPath(t *testing.T) {
	path := getBinaryPath()

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("Failed to stat binaryPath: %v", err)
	}

	if info.IsDir() {
		t.Fatalf("Expected binary, got directory: %s", path)
	}

	if info.Mode()&0111 == 0 {
		t.Fatalf("Binary is not executable: %s", path)
	}

	t.Logf("✅ binaryPath OK: %s", path)
}

func TestRunServerlessCompat(t *testing.T) {
	// This is a difficult test to write as it depends on the actual binary
	// We can test the error cases though
	os.Unsetenv("FUNCTIONS_EXTENSION_VERSION")
	os.Unsetenv("FUNCTIONS_WORKER_RUNTIME")
	os.Unsetenv("FUNCTION_NAME")
	os.Unsetenv("GCP_PROJECT")

	err := Start()
	if err == nil {
		t.Error("Expected error for unknown environment, got nil")
	}
}
