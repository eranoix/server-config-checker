#!/bin/sh
set -eu
chmod 0644 /etc/nginx/http.d/site.conf /etc/systemd/system/web.service
chown root:drift /etc/app/web.env
chmod 0640 /etc/app/web.env
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -s /etc/systemd/system/web.service /etc/systemd/system/multi-user.target.wants/web.service
