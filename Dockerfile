FROM golang:1.23

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Set environment variables for testing
ENV FUNCTION_NAME=test-function
ENV GCP_PROJECT=test-project
ENV DD_SERVERLESS_COMPAT_PATH=/internal/artifact/linux-amd64/datadog-serverless-compat


CMD ["go", "test", "-v", "./..."]
