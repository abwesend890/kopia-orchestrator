FROM kopia/kopia:latest

RUN apk add --no-cache bash curl yq

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
