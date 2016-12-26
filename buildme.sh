#!/bin/sh

set -e
nim c --cpu:arm --os:linux -d:useuClibc heating_monitor.nim
scp heating_monitor heating:/opt/heating/
ssh heating chmod 0755 /opt/heating/heating_monitor
