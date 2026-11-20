#!/bin/sh
# Writes a tinyproxy config that allows CONNECT to $ALLOW_HOST:443 only, then runs it in the foreground.
set -eu
: "${ALLOW_HOST:?}"
host_re=$(printf '%s' "$ALLOW_HOST" | sed 's/\./\\./g')
printf '^%s$\n' "$host_re" > /tmp/allow
cat > /tmp/tinyproxy.conf <<CONF
Port 8888
Listen 0.0.0.0
Timeout 600
MaxClients 20
LogLevel Connect
Allow 0.0.0.0/0
ConnectPort 443
Filter "/tmp/allow"
FilterType ere
FilterDefaultDeny Yes
DisableViaHeader Yes
CONF
exec tinyproxy -d -c /tmp/tinyproxy.conf
