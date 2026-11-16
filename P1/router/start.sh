#!/bin/bash
# Start watchfrr, which launches every daemon enabled in /etc/frr/daemons
/usr/lib/frr/frrinit.sh start

# Replace this script with an interactive shell so the GNS3 console is usable
exec /bin/bash
