package ddserverlesscompat

import (
	"fmt"
	"log"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// go:embed bin
var bin []byte

// ddlog is the logger for the Datadog Serverless Compatibility Layer
var ddlog *log.Logger

// Version is the current version of the package
const Version = "0.1.0"

// CloudEnvironment represents the different serverless environments supported
type CloudEnvironment string

const (
	GoogleCloudRunFunction1stGen CloudEnvironment = "Google Cloud Run Function 1st gen"
	Unknown                      CloudEnvironment = "Unknown"
)

// init initializes the Datadog Serverless Compatibility Layer on package import
func init() {
	initLogger()
	ddlog.Println("Initializing Datadog Serverless Compatibility Layer")
	err := Start()
	if err != nil {
		ddlog.Fatalf("Failed to run Serverless Compatibility Layer: %v", err)
	}
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
		ddlog = slog.NewLogLogger(handler, slog.LevelDebug)
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
	currentDir, err := os.Getwd()
	if err != nil {
		ddlog.Fatalf("Failed to get current directory: %v", err)
	}
	// Determine the appropriate binary path based on the OS
	var binaryPath string
	if runtime.GOOS == "windows" {
		binaryPath = filepath.Join(currentDir, "serverless_function_source_code", "bin", "windows-amd64", "datadog-serverless-compat.exe")
	} else {
		binaryPath = filepath.Join(currentDir, "serverless_function_source_code", "bin", "linux-amd64", "datadog-serverless-compat")
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

	if runtime.GOOS != "linux" {
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

	ddlog.Printf("Successfully started the Serverless Compatibility Layer process")
	return nil
}
