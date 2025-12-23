# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli:v0.15.0@sha256:5a09486afc55d7c5d54187ba87daf47ec54c54338e9505c1bd7df2d95688de67 AS kusari

# Use Alpine as final base to provide shell environment
FROM alpine:latest

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
