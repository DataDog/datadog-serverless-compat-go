FROM golang:1.23

WORKDIR /app

COPY . .
RUN cd datadogserverlesscompat && go mod download

# Set environment variables for testing
ENV FUNCTION_NAME=test-function
ENV GCP_PROJECT=test-project

WORKDIR /app/datadogserverlesscompat
CMD ["go", "test", "-v", "."]
