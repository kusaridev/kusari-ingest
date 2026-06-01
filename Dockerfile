# Using kusari-cli for upload and generate functionality (v2.2.1 / latest as of 2026-06-01)
FROM ghcr.io/kusaridev/kusari-cli@sha256:6dd2467a73298fc27cf84c3fa382c79e998f428580325fccaef4866545b22d91 AS kusari

# Use Chainguard wolfi-base as final base to provide shell environment (latest as of 2026-06-01)
FROM cgr.dev/chainguard/wolfi-base@sha256:441d6709305552a3411e585ad98aacb9dadda00c80f3267483c38ac6f86f49d4

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
