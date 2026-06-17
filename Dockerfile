# Using kusari-cli for upload functionality (v2.4.0 — bundles mikebom 0.1.0-alpha.48,
# which provides the --root-purl-type / --no-root-purl scan flags)
FROM ghcr.io/kusaridev/kusari-cli@sha256:9e62cd85390140bde2cb6b97e1075ab4d9eab9d6b4734386ca6a3c8647a95825 AS kusari

# Use Chainguard wolfi-base as final base to provide shell environment
FROM cgr.dev/chainguard/wolfi-base@sha256:34977aa13765da89f60fee8fe5230e2bb1c55192df08e383c58221ee0d1277fb

# Copy kusari binary from the kusari-cli image
COPY --from=kusari /ko-app/kusari /usr/local/bin/kusari

# Copy entrypoint script with executable permissions
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
