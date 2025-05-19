package ddserverlesscompat

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
	// Test Azure Function environment
	os.Setenv("FUNCTIONS_EXTENSION_VERSION", "1.0")
	os.Setenv("FUNCTIONS_WORKER_RUNTIME", "node")
	env := GetEnvironment()
	if env != AzureFunction {
		t.Errorf("Expected AzureFunction environment, got %v", env)
	}

	// Test Google Cloud Run Function environment
	os.Unsetenv("FUNCTIONS_EXTENSION_VERSION")
	os.Unsetenv("FUNCTIONS_WORKER_RUNTIME")
	os.Setenv("FUNCTION_NAME", "test-function")
	os.Setenv("GCP_PROJECT", "test-project")
	env = GetEnvironment()
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
	// Test custom path
	customPath := "/custom/path/binary"
	os.Setenv("DD_SERVERLESS_COMPAT_PATH", customPath)
	path := GetBinaryPath()
	if path != customPath {
		t.Errorf("Expected custom path %s, got %s", customPath, path)
	}

	// Test default path
	os.Unsetenv("DD_SERVERLESS_COMPAT_PATH")
	path = GetBinaryPath()
	if path == "" {
		t.Error("Default binary path should not be empty")
	}
}

func TestRunServerlessCompat(t *testing.T) {
	// This is a difficult test to write as it depends on the actual binary
	// We can test the error cases though
	os.Unsetenv("FUNCTIONS_EXTENSION_VERSION")
	os.Unsetenv("FUNCTIONS_WORKER_RUNTIME")
	os.Unsetenv("FUNCTION_NAME")
	os.Unsetenv("GCP_PROJECT")

	err := StartServerlessCompat()
	if err == nil {
		t.Error("Expected error for unknown environment, got nil")
	}
}
