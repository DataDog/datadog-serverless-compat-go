package datadogserverlesscompat

import (
	"embed"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

//go:embed internal/bin/*
var binFS embed.FS

// ddlog is the logger for the Datadog Serverless Compatibility Layer
var ddlog *slog.Logger

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
	levelStr := strings.ToLower(os.Getenv("DD_LOG_LEVEL"))
	var level slog.Level
	switch levelStr {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}
	handler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})
	ddlog = slog.New(handler)
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

	tempDir, err := os.MkdirTemp("", "datadog-serverless-compat")
	if err != nil {
		ddlog.Error("Failed to create temp directory", "error", err)
		os.Exit(1)
	}

	// Determine the appropriate binary path based on the Linux OS for GCP Cloud Functions
	binaryName := "linux-amd64/datadog-serverless-compat"

	// Extract the embedded binary to the temp directory
	binaryPath := filepath.Join(tempDir, filepath.Base(binaryName))
	binaryData, err := binFS.ReadFile(filepath.Join("internal", "bin", binaryName))
	if err != nil {
		ddlog.Error("Failed to read embedded binary", "error", err)
		os.Exit(1)
	}

	if err := os.WriteFile(binaryPath, binaryData, 0755); err != nil {
		ddlog.Error("Failed to write binary to temp directory", "error", err)
		os.Exit(1)
	}

	return binaryPath
}

// setPackageVersion sets the package version in the environment
func setPackageVersion() {
	ddlog.Info("Setting package version", "version", Version)
	os.Setenv("DD_SERVERLESS_COMPAT_VERSION", Version)
}

// Start starts the Datadog Serverless Compatibility Layer
func Start() error {
	environment := GetEnvironment()
	ddlog.Info("Environment detected", "environment", environment)

	if environment == Unknown {
		return fmt.Errorf("%s environment detected, will not start the Datadog Serverless Compatibility Layer", environment)
	}

	ddlog.Info("Platform detected", "platform", runtime.GOOS)

	if runtime.GOOS != "linux" {
		return fmt.Errorf("Platform %s detected, the Datadog Serverless Compatibility Layer is only supported on Linux", runtime.GOOS)
	}

	binaryPath := GetBinaryPath()
	ddlog.Info("Spawning process", "binary_path", binaryPath)

	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		ddlog.Error("Serverless Compatibility Layer did not start", "error", "binary not found", "path", binaryPath)
		return fmt.Errorf("Serverless Compatibility Layer did not start, could not find binary at path %s", binaryPath)
	}
	ddlog.Info("Binary found", "path", binaryPath)
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
