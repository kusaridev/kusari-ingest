# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli@sha256:4a3af56d8eadfd1444f7f8295d978902c8f13b5382dbe2a978e41d8b4069fe40 AS kusari

# Use Chainguard wolfi-base as final base to provide shell environment
FROM cgr.dev/chainguard/wolfi-base@sha256:31da6565f35af6401031c1d7aa91dc84ac76c5c48edd17fb90f0ed9e3173c7a9

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
