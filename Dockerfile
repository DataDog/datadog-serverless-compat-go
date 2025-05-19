FROM golang:1.23

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Set environment variables for testing
ENV DD_SERVERLESS_COMPAT_AUTO_INIT=false
ENV FUNCTION_NAME=test-function
ENV GCP_PROJECT=test-project
ENV DD_SERVERLESS_COMPAT_PATH=/app/bin/linux-amd64/datadog-serverless-compat

# Copy the required binary into the image
COPY bin/linux-amd64/datadog-serverless-compat /app/bin/linux-amd64/datadog-serverless-compat

CMD ["go", "test", "-v", "./..."]