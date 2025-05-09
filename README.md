# Datadog Serverless Compatibility Layer

A standalone binary for enabling tracing and custom metric submission from Azure Functions and Google Cloud Run Functions.

## Installation

### Pre-built Binaries

Download the latest release for your platform from the [releases page](https://github.com/DataDog/datadog-serverless-compat/releases).

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/DataDog/datadog-serverless-compat.git
cd datadog-serverless-compat
```

2. Build the binary:
```bash
make build
```

3. (Optional) Install the binary:
```bash
sudo make install
```

## Usage

### Basic Usage

Simply run the binary:
```bash
datadog-serverless-compat
```

### Command Line Options

- `-version`: Print version information
- `-debug`: Enable debug logging

Example with debug logging:
```bash
datadog-serverless-compat -debug
```

### Environment Variables

- `DD_SERVERLESS_COMPAT_PATH`: Custom path to the compatibility layer binary
- `DD_SERVERLESS_COMPAT_VERSION`: Version of the compatibility layer (automatically set)

## Configuration

Set the following Datadog environment variables:
- `DD_API_KEY`: Your Datadog API key
- `DD_SITE`: Datadog site (default: datadoghq.com)
- `DD_ENV`: Environment name
- `DD_SERVICE`: Service name
- `DD_VERSION`: Version of your application

## Supported Platforms

- Linux (amd64)
- Windows (amd64)

## Development

### Building for Multiple Platforms

```bash
make build-all
```

This will create binaries for both Linux and Windows.

### Running Tests

```bash
make test
```

### Debug Mode

```bash
make debug
```

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.
