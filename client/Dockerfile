FROM kopia/kopia:latest

RUN apk add --no-cache bash curl yq docker-cli inotify-tools

COPY entrypoint.sh /entrypoint.sh
COPY setup.sh /setup.sh
COPY restore.sh /restore.sh
RUN chmod +x /entrypoint.sh /setup.sh /restore.sh

ENTRYPOINT ["/entrypoint.sh"]
