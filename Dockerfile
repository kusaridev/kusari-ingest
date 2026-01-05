# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli@sha256:0d82fe16c3bd965279d5c2ff6cdc27a0d9047a5bcd34b7d705a922f574c4f917 AS kusari

# Use Alpine as final base to provide shell environment
FROM alpine:latest

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
