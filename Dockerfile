# Multi-stage build for pg_tileserv
FROM golang:1.23-alpine AS builder

# Install git and build dependencies
RUN apk add --no-cache git

WORKDIR /app

# Clone the official pg_tileserv repository
RUN git clone https://github.com/Caliper-Corporation/pg_tileserv.git .

# Build the binary
RUN go build -o pg_tileserv

# Final stage
FROM alpine:latest

# Install ca-certificates for HTTPS connections
RUN apk add --no-cache ca-certificates

# Copy the binary from builder
COPY --from=builder /app/pg_tileserv /usr/local/bin/pg_tileserv

# Create directory for assets if needed
WORKDIR /app

# Expose the default port
EXPOSE 7800

# Run the service
CMD ["pg_tileserv"]
