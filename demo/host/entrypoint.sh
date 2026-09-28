#!/bin/sh
set -eu
install -m 600 /keys/host_ed25519 /etc/ssh/ssh_host_ed25519_key
install -d -m 700 -o drift -g drift /home/drift/.ssh
printf 'restrict %s\n' "$(cat /keys/client.pub)" >/home/drift/.ssh/authorized_keys
chown drift:drift /home/drift/.ssh/authorized_keys
chmod 600 /home/drift/.ssh/authorized_keys
exec /usr/sbin/sshd -D -e
