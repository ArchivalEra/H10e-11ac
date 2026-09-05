#!/bin/sh
# persistent boot logic - called once by initramfs trampoline. editable, no reflash needed.
[ -f /userconfig/NO_AGENT ] && exit 0
# quiet kernel log flood (persist printk level; vendor daemons handled by kills below)
echo 1 > /proc/sys/kernel/printk 2>/dev/null
# java kill waves (async): keep OSGi/Java down per mission policy
( for s in 2 5 10 20 30 60 120 180 300; do sleep $s; killall -9 java cpulimit 2>/dev/null; done ) &
# wait for vendor ready (br0 up, max 120s), then launch ordered autostart agent
( for i in $(seq 1 120); do [ -d /sys/class/net/br0 ] && break; sleep 1; done
  [ -x /userconfig/agent/agent.sh ] && setsid sh /userconfig/agent/agent.sh boot >/tmp/agent-boot2.log 2>&1 & ) &
