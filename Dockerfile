# Using kusari-cli for upload functionality
FROM ghcr.io/kusaridev/kusari-cli:sha-e41fbcafdde40ee0c5435f738ccc2fc8eb1075b5

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
