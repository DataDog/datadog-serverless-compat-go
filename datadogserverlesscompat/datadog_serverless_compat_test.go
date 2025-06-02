package datadogserverlesscompat

import (
	"os"
	"testing"
)


func TestMain(m *testing.M) {
	code := m.Run()
	os.Exit(code)
}

func TestVersion(t *testing.T) {
	if Version == "" {
		t.Error("Version should not be empty")
	}
}

func TestGetEnvironment(t *testing.T) {
	// Test Google Cloud Run Function environment
	os.Unsetenv("FUNCTIONS_EXTENSION_VERSION")
	os.Unsetenv("FUNCTIONS_WORKER_RUNTIME")
	os.Setenv("FUNCTION_NAME", "test-function")
	os.Setenv("GCP_PROJECT", "test-project")
	env := GetEnvironment()
	if env != GoogleCloudRunFunction1stGen {
		t.Errorf("Expected GoogleCloudRunFunction1stGen environment, got %v", env)
	}

	// Test Unknown environment
	os.Unsetenv("FUNCTION_NAME")
	os.Unsetenv("GCP_PROJECT")
	env = GetEnvironment()
	if env != Unknown {
		t.Errorf("Expected Unknown environment, got %v", env)
	}
}


func TestGetBinaryPath(t *testing.T) {
	path := GetBinaryPath()

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
