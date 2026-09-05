#!/usr/bin/env python3
"""Surgical rcS patch: replace stock comment block (lines 98-101, 111B) with
agent trampoline of EXACT same length. Total archive length unchanged.
Usage: SURGICAL_WRITE=1 python3 surgical.py  # emit newinit2.cpio for rebuild.sh;
       default (unset) only analyzes, per analysis-record convention."""
import gzip
import os
import sys

W = '/tmp/h10e-test2'
dec = gzip.decompress(open('/tmp/h10e-test2/stock-cpio.gz', 'rb').read())
print('stock archive len:', len(dec))

# locate etc/init.d/rcS entry by walking newc entries (avoids false hits in data)
name = b'etc/init.d/rcS'
pos, ni = 0, -1
while True:
    hstart = dec.find(b'070701', pos)
    assert hstart >= 0, 'header not found'
    namesize = int(dec[hstart + 94:hstart + 102], 16)
    filesize = int(dec[hstart + 54:hstart + 62], 16)
    nstart = hstart + 110
    nend = nstart + namesize
    if dec[nstart:nend] == name + b'\x00':
        ni = nstart
        break
    dataoff = nend + ((4 - nend % 4) % 4)
    pos = dataoff + filesize + ((4 - (dataoff + filesize) % 4) % 4)
print('rcS filesize in archive:', filesize)
dataoff = ni + namesize + ((4 - (ni + namesize) % 4) % 4)
rcs = dec[dataoff:dataoff + filesize]
assert len(rcs) == 17842, len(rcs)

REGION = b'#\n# Resume default configuration file\n# 0 - Default, 1 - Russia, 2 - Lithuania, 3 - Romania, 4 - Singapore\n#\n'
RLEN = len(REGION)
print('region len:', RLEN)
ri = rcs.find(REGION)
assert ri > 0, 'region not found'
print('region at rcS offset:', ri)

code = b'[ -x /userconfig/agent-boot.sh ] && setsid sh /userconfig/agent-boot.sh >/tmp/agent-boot.log 2>&1 &'
assert len(code) < RLEN - 3, len(code)
line1 = code + b' ' * (RLEN - 3 - len(code)) + b'\n'  # code + space pad + newline
repl = line1 + b'#\n'                                 # + trailing comment line
assert len(repl) == RLEN, len(repl)
print('replacement:')
print(repl.decode())

newrcs = rcs[:ri] + repl + rcs[ri + RLEN:]
assert len(newrcs) == 17842
newdec = dec[:dataoff] + newrcs + dec[dataoff + filesize:]
assert len(newdec) == len(dec)
if os.environ.get('SURGICAL_WRITE'):
    open(W + '/newinit2.cpio', 'wb').write(newdec)
    print('wrote', W + '/newinit2.cpio')
print('spliced archive len:', len(newdec), '(unchanged)')
