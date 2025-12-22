# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli@sha256:685a1a080bbf092de153b5e914807a7f01b56507afd7e6a50a97f544c49bab3f

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
