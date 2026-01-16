# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli@sha256:5585140d433df5d5664f82ae9fad0f738aa35d7d8b28394a76201fb027a993fc AS kusari

# Use Chainguard wolfi-base as final base to provide shell environment
FROM cgr.dev/chainguard/wolfi-base@sha256:0d8efc73b806c780206b69d62e1b8cb10e9e2eefa0e4452db81b9fa00b1a5175

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
