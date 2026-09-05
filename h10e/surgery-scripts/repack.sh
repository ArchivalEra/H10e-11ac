#!/bin/sh
# repack initramfs from /tmp/iram in STOCK order + restore dev nodes (fakeroot).
set -e
W=/tmp/h10e-test2
cpio -tv -F /tmp/initramfs.orig.cpio 2>/dev/null | awk '$1 ~ /^[bc]/ {print $1, $5 $6, $NF}' | sed 's/,/ /' > $W/nodes.txt
cpio -tv -F /tmp/initramfs.orig.cpio 2>/dev/null | awk '$1 ~ /^[ps]/' | head -n 5
wc -l $W/nodes.txt
cpio -t -F /tmp/initramfs.orig.cpio 2>/dev/null > $W/order.txt
wc -l $W/order.txt
python3 - "$W" <<'PYEOF'
import sys
W = sys.argv[1]
cmds = []
for line in open(W + '/nodes.txt'):
    mode, maj, mn, name = line.split()
    typ = 'c' if mode[0] == 'c' else 'b'
    cmds.append('mknod %s %s %s %s 2>/dev/null || true' % (name, typ, maj, mn))
open(W + '/mknod.sh', 'w').write('#!/bin/sh\ncd /tmp/iram\n' + '\n'.join(cmds) + '\n')
print('mknod cmds:', len(cmds))
PYEOF
cd /tmp/iram
fakeroot sh -c 'chown -Rh 0:0 /tmp/iram && sh /tmp/h10e-test2/mknod.sh && cd /tmp/iram && cpio -o --format=newc < /tmp/h10e-test2/order.txt > /tmp/h10e-test2/newinit.cpio'
ls -la $W/newinit.cpio
cpio -t -F $W/newinit.cpio 2>/dev/null | wc -l
gzip -9n -c $W/newinit.cpio > $W/newinit.cpio.gz
ls -la $W/newinit.cpio.gz
python3 -c "print('cpio.gz size:', __import__('os').path.getsize('$W/newinit.cpio.gz'), 'limit 26873439, fits:', __import__('os').path.getsize('$W/newinit.cpio.gz') <= 26873439)"
