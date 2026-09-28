#!/bin/sh
set -eu
chmod 0644 /etc/app/worker.conf /etc/systemd/system/worker.service /etc/systemd/system/cleanup.timer
chown root:drift /etc/app/worker.env
chmod 0640 /etc/app/worker.env
mkdir -p /etc/systemd/system/multi-user.target.wants /etc/systemd/system/timers.target.wants
ln -s /etc/systemd/system/worker.service /etc/systemd/system/multi-user.target.wants/worker.service
ln -s /etc/systemd/system/cleanup.timer /etc/systemd/system/timers.target.wants/cleanup.timer
