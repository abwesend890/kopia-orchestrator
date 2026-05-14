FROM kopia/kopia:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl docker.io inotify-tools && \
    curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY setup.sh /setup.sh
COPY restore.sh /restore.sh
RUN chmod +x /entrypoint.sh /setup.sh /restore.sh

ENTRYPOINT ["/entrypoint.sh"]
