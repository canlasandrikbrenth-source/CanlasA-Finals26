#!/bin/bash
# The fix that stops the disk-full fault recurring: size-limited rotation, checked every minute.
set -euo pipefail
dnf install -y logrotate
cat >/etc/logrotate.d/asktala <<'CONF'
/var/log/asktala/*.log {
    size 200M
    rotate 2
    compress
    missingok
    notifempty
    copytruncate
}
CONF
cat >/etc/systemd/system/asktala-logrotate.service <<'UNIT'
[Unit]
Description=Rotate Ask Tala logs
[Service]
Type=oneshot
ExecStart=/usr/sbin/logrotate /etc/logrotate.d/asktala
UNIT
cat >/etc/systemd/system/asktala-logrotate.timer <<'UNIT'
[Unit]
Description=Rotate Ask Tala logs every minute
[Timer]
OnCalendar=minutely
AccuracySec=5s
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now asktala-logrotate.timer
systemctl list-timers asktala-logrotate.timer --no-pager
