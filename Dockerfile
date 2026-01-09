# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli@sha256:2c8d66e8f861d95908aa2a657564b7125bdc641764eb7dc7bc77fc0d409b9756 AS kusari

# Use Chainguard wolfi-base as final base to provide shell environment
FROM cgr.dev/chainguard/wolfi-base:latest

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
