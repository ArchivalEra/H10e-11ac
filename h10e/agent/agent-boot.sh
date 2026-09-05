#!/bin/sh
# persistent boot logic - called once by initramfs trampoline. editable, no reflash needed.
[ -f /userconfig/NO_AGENT ] && exit 0
# quiet kernel log flood (persist printk level; vendor daemons handled by kills below)
echo 1 > /proc/sys/kernel/printk 2>/dev/null
# kill waves (async): java waves protect provision RAM; the big sweep runs later.
# NOTE: pc must stay alive through LAN build (agent kills it delayed); voice/mgmt
# daemons are swept post-LAN by the delayed sweep below (proven safe, they stay dead).
( for s in 2 5 10 20 30 60 120 180 300; do sleep $s; killall -9 java cpulimit 2>/dev/null; done ) &
# wait for vendor ready: br0 CARRIER up (members+link, not just exists), max 180s,
# then launch agent. (pc must stay alive through LAN build; agent kills it later.)
( for i in $(seq 1 180); do [ "$(cat /sys/class/net/br0/carrier 2>/dev/null)" = 1 ] && break; sleep 1; done
  [ -x /userconfig/agent/agent.sh ] && setsid sh /userconfig/agent/agent.sh boot >/tmp/agent-boot2.log 2>&1 & ) &
# delayed big sweep (post-LAN, ~6min): converge to minimal pid table.
# proven safe: LAN/LuCI/telnet/dnsmasq all survive; nothing respawns (init has no
# respawn entries; pc already dead via agent sweep). cspd LAST (config plane).
( sleep 360
  killall -9 osgid java phoneapp vodsl eaServer ctsgw_proxyd dmplatform starnet simulation nethack vsftpd smbd nmbd udpsvd openl2tpd starter charon portmap cpulimit cspd 2>/dev/null
  echo "[agent-boot $(date '+%H:%M:%S')] delayed sweep done" >> /tmp/agent-logs/agent-boot-sweep.log
) &
