# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2025-present Datadog, Inc.

FROM golang:1.23

WORKDIR /app

COPY . .
RUN cd datadogserverlesscompat && go mod download

# Set environment variables for testing
ENV FUNCTION_NAME=test-function
ENV GCP_PROJECT=test-project

WORKDIR /app/datadogserverlesscompat
CMD ["go", "test", "-v", "."]
