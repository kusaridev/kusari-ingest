# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli@sha256:2323d84cb0d01db00c159335d2fad437fe0ee793382667353c9019268d84038e AS kusari

# Use Chainguard wolfi-base as final base to provide shell environment
FROM cgr.dev/chainguard/wolfi-base@sha256:5743937d521cbeb9e8c73bf1bd7ba2589c178940eb03d7b148efecc962be8587

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
