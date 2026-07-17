FROM dart:stable AS build

WORKDIR /app

# Copy all files in the workspace
COPY . .

# Resolve dependencies for the workspace
RUN dart pub get

# Compile the backend AOT executable
WORKDIR /app/backend
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2: Runtime
FROM debian:bookworm-slim

# Install runtime sqlite3 libraries and CA certs
RUN apt-get update && apt-get install -y sqlite3 libsqlite3-dev ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the compiled binary from the build stage
COPY --from=build /app/backend/bin/server /app/bin/server

# Expose the default port
EXPOSE 8080

# Run the compiled binary
CMD ["/app/bin/server"]
