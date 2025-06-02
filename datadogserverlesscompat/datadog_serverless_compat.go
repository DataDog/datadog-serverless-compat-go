package datadogserverlesscompat

import (
	"embed"
	"fmt"
	"log"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

//go:embed internal/artifact/*
var binFS embed.FS

// ddlog is the logger for the Datadog Serverless Compatibility Layer
var ddlog *log.Logger

// Version is the current version of the package
const Version = "v0.1.0"

// CloudEnvironment represents the different serverless environments supported
type CloudEnvironment string

const (
	GoogleCloudRunFunction1stGen CloudEnvironment = "Google Cloud Run Function 1st gen"
	Unknown                      CloudEnvironment = "Unknown"
)

// init initializes the Datadog Serverless Compatibility Layer on package import
func init() {
	initLogger()
}

func initLogger() {
	handler := slog.NewJSONHandler(os.Stdout, nil)
	levelStr := strings.ToLower(os.Getenv("DD_LOG_LEVEL"))
	switch levelStr {
	case "debug":
		ddlog = slog.NewLogLogger(handler, slog.LevelDebug)
	case "warn":
		ddlog = slog.NewLogLogger(handler, slog.LevelWarn)
	case "error":
		ddlog = slog.NewLogLogger(handler, slog.LevelError)
	default:
		ddlog = slog.NewLogLogger(handler, slog.LevelInfo)
	}
}

// GetEnvironment detects the current cloud environment based on environment variables
func GetEnvironment() CloudEnvironment {
	if os.Getenv("FUNCTION_NAME") != "" && os.Getenv("GCP_PROJECT") != "" {
		return GoogleCloudRunFunction1stGen
	} else if os.Getenv("K_SERVICE") != "" && os.Getenv("FUNCTION_TARGET") != "" {
		return GoogleCloudRunFunction1stGen
	}

	return Unknown
}

// GetBinaryPath returns the path to the datadog-serverless-compat binary
func GetBinaryPath() string {
	// Use user defined path if provided
	if userPath := os.Getenv("DD_SERVERLESS_COMPAT_PATH"); userPath != "" {
		return userPath
	}

	// Create a temporary directory for the binary
	tempDir, err := os.MkdirTemp("", "datadog-serverless-compat")
	if err != nil {
		ddlog.Fatalf("Failed to create temp directory: %v", err)
	}

	// Determine the appropriate binary path based on the Linux OS for GCP Cloud Functions
	binaryName := "linux-amd64/datadog-serverless-compat"

	// Extract the embedded binary to the temp directory
	binaryPath := filepath.Join(tempDir, filepath.Base(binaryName))
	binaryData, err := binFS.ReadFile(filepath.Join("internal", "artifact", binaryName))
	if err != nil {
		ddlog.Fatalf("Failed to read embedded binary: %v", err)
	}

	if err := os.WriteFile(binaryPath, binaryData, 0755); err != nil {
		ddlog.Fatalf("Failed to write binary to temp directory: %v", err)
	}

	return binaryPath
}

// setPackageVersion sets the package version in the environment
func setPackageVersion() {
	ddlog.Printf("Setting DD_SERVERLESS_COMPAT_VERSION to %s", Version)
	os.Setenv("DD_SERVERLESS_COMPAT_VERSION", Version)
}

// Start starts the Datadog Serverless Compatibility Layer
func Start() error {
	environment := GetEnvironment()
	ddlog.Printf("Environment detected: %s", environment)

	if environment == Unknown {
		return fmt.Errorf("%s environment detected, will not start the Datadog Serverless Compatibility Layer", environment)
	}

	ddlog.Printf("Platform detected: %s", runtime.GOOS)

	if runtime.GOOS != "linux" && runtime.GOOS != "windows" {
		return fmt.Errorf("Platform %s detected, the Datadog Serverless Compatibility Layer is only supported on Windows and Linux", runtime.GOOS)
	}

	binaryPath := GetBinaryPath()
	ddlog.Printf("Spawning process from binary at path %s", binaryPath)

	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		ddlog.Printf("Serverless Compatibility Layer did not start, could not find binary at path %s", binaryPath)
		return fmt.Errorf("Serverless Compatibility Layer did not start, could not find binary at path %s", binaryPath)
	}
	ddlog.Printf("Binary path found: %s", binaryPath)
	setPackageVersion()

	cmd := exec.Command(binaryPath)
	// Inherit standard input, output, and error from the parent
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stdout
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("An unexpected error occurred while spawning Serverless Compatibility Layer process: %v", err)
	}

	return nil
}
