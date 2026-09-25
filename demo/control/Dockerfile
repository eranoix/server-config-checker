# Where the verifier runs in the demo: an ssh client and busybox, nothing else.
# Running it on busybox is deliberate: it keeps the scripts honest about POSIX.
FROM alpine:3.20
RUN apk add --no-cache openssh-client
COPY control/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["sh", "/entrypoint.sh"]
