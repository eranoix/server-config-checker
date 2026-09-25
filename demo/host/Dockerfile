# A throwaway "server" for the demo: sshd plus a fixture file system.
FROM alpine:3.20
RUN apk add --no-cache openssh-server \
 && adduser -D -s /bin/sh drift \
 && sed -i 's/^drift:!/drift:*/' /etc/shadow \
 && rm -f /etc/ssh/ssh_host_*
ARG HOST
COPY hosts/${HOST}/root/ /
COPY hosts/${HOST}/setup.sh /tmp/setup.sh
RUN sh /tmp/setup.sh && rm /tmp/setup.sh
COPY host/sshd_config /etc/ssh/sshd_config
COPY host/entrypoint.sh /entrypoint.sh
ENTRYPOINT ["sh", "/entrypoint.sh"]
