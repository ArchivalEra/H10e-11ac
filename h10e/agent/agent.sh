#!/bin/sh
# light boot agent (H10E-11AC): ordered starter + watchdog.
# contract: /userconfig/agent/services/SNN* executable = enabled, sorted start.
#   service args: start | stop | check   (check: exit 0 = healthy)
# global kill-switch: /userconfig/NO_AGENT (checked at start + every round)
# usage: agent.sh boot | stop | status
A=/userconfig/agent; S=$A/services; L=/tmp/agent-logs
[ -f /userconfig/NO_AGENT ] && exit 0
mkdir -p "$L"
log() { echo "[agent $(date '+%H:%M:%S')] $*" >>"$L/agent.log"; }
case "$1" in
  stop)
    for s in $(ls -r $S/S* 2>/dev/null); do
      [ -x "$s" ] && { log "stop $s"; "$s" stop >>"$L/$(basename $s).log" 2>&1; }
    done
    log "stopped"; exit 0 ;;
  status)
    for s in $(ls $S/S* 2>/dev/null); do
      if [ -x "$s" ]; then
        "$s" check >/dev/null 2>&1 && echo "UP   $s" || echo "DOWN $s"
      else
        echo "OFF  $s"
      fi
    done
    exit 0 ;;
esac
log "boot: starting enabled services"
killall -9 java cpulimit 2>/dev/null; log "boot: early sweep (java/cpulimit, protect provision RAM)"
for s in $(ls $S/S* 2>/dev/null); do
  [ -x "$s" ] || continue
  log "start $s"; "$s" start >>"$L/$(basename $s).log" 2>&1 &
done
wait
log "all started; watchdog armed (60s)"
# delayed pc+osgid kill: pc must live through LAN build (~mins), then die
# (else: reboot escalation + supervision). orphans keep running; nothing respawns.
( sleep 300; killall -9 pc osgid 2>/dev/null && log "delayed sweep: pc/osgid down" ) &
while :; do sleep 60
  [ -f /userconfig/NO_AGENT ] && { log "killed by NO_AGENT"; exit 0; }
  killall -9 pc 2>/dev/null && log "watchdog: pc suppressed"
  for s in $(ls $S/S* 2>/dev/null); do
    [ -x "$s" ] || continue
    "$s" check >/dev/null 2>&1 || { log "RESPAWN $s"; "$s" start >>"$L/$(basename $s).log" 2>&1 & }
  done
done
