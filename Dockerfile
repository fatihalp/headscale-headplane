FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Copy the installer script
COPY install.sh /install.sh
RUN chmod +x /install.sh

# Run the script in non-interactive / no-SSL mode for testing
CMD ["/bin/bash", "/install.sh", "--domain", "headscale.visiosoft.com.tr", "--ui-domain", "head.visiosoft.com.tr", "--admin-pass", "testpass123", "--headscale-version", "0.28.0", "--headplane-tag", "v0.6.2", "--no-ssl"]
