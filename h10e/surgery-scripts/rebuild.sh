#!/bin/sh
# rebuild router kernel1 test image from /tmp/iram (+edited rcS). faithful to prior recipe.
set -e
W=/tmp/h10e-test2
if [ -z "$SKIP12" ]; then rm -rf $W; fi
mkdir -p $W
echo "[1] pack cpio"
if [ -z "$SKIP12" ]; then
(cd /tmp/iram && find . -mindepth 1 -print | LC_ALL=C sort | sed 's|^\./||' | cpio -o --format=newc > $W/newinit.cpio)
echo "[2] gzip initramfs"
gzip -9n -c $W/newinit.cpio > $W/newinit.cpio.gz
else
echo "(stages 1-2 skipped, using prebuilt $W/newinit.cpio.gz)"
fi
echo "[3] splice + outer gzip + payload + uimg + vendor header"
python3 - "$W" <<'PYEOF'
import zlib, struct, subprocess, sys
W = sys.argv[1]
def rd(p, off=0, n=None):
    with open(p, 'rb') as f:
        f.seek(off)
        return f.read() if n is None else f.read(n)
def wr(p, b):
    with open(p, 'wb') as f:
        f.write(b)
ST = '/mnt/hdd/h10e-latest/surgery/uImage_data.bin'
KST = '/mnt/hdd/h10e-latest/surgery/kernel1.bin'
OFF = 0x7bd448; L_STOCK = 0x19ff65f; PRE = 0x6614
st = rd(ST)
so = st.find(b'\x1f\x8b')
import zlib
decS = zlib.decompress(st[so:], 16 + zlib.MAX_WBITS)
cg = rd(W + '/newinit.cpio.gz')
newdec = decS[:OFF] + cg + decS[OFF + L_STOCK:]
import os as _os
need = len(decS) - len(newdec)
print('len adjust needed:', need)
if need > 0:
    # pad with zeros (never shrink: our cg already fits region, need>=0 expected)
    newdec = newdec + b'\x00' * need
assert len(newdec) == len(decS), (len(newdec), len(decS))
with open(W + '/newdec.bin', 'wb') as f:
    f.write(newdec)
ob = _os.environ.get('OUTER_BIN')
if ob:
    print('using prebuilt outer:', ob)
    import shutil as _sh
    _sh.copy(ob, W + '/outer.gz')
else:
    subprocess.run('gzip -9n -c %s/newdec.bin > %s/outer.gz' % (W, W), shell=True, check=True)
outer = rd(W + '/outer.gz')
assert outer[:2] == b'\x1f\x8b' and outer[2] == 0x08, outer[:10].hex()
# trailer: stock last 8281 bytes (verified identical region)
trailer = st[-8281:]
payload = st[:PRE] + outer + trailer
wr(W + '/newpayload.bin', payload)
subprocess.run(['mkimage', '-A', 'arm', '-O', 'linux', '-T', 'kernel', '-C', 'none',
                '-a', '0x40008000', '-e', '0x40008000', '-n', 'Linux Kernel Image',
                '-d', W + '/newpayload.bin', W + '/newuimg.bin'], check=True)
uimg = rd(W + '/newuimg.bin')
hdr = bytearray(rd(KST, 0, 0x1E0))
print('stock @0x60 was: 0x%x' % struct.unpack('<I', hdr[0x60:0x64])[0])
import zlib as _z
struct.pack_into('<I', hdr, 0x58, len(uimg))
struct.pack_into('<I', hdr, 0x60, _z.crc32(uimg) & 0xffffffff)
wr(W + '/kernel1-test2.bin', bytes(hdr) + uimg)
print('final size:', 0x1E0 + len(uimg), 'limit 33554432, fits:', 0x1E0 + len(uimg) < 33554432)
PYEOF
echo "[4] verify"
dumpimage -l $W/newuimg.bin
python3 - "$W" <<'PYEOF'
import zlib, sys
W = sys.argv[1]
def rd(p, off=0, n=None):
    with open(p, 'rb') as f:
        f.seek(off)
        return f.read() if n is None else f.read(n)
kb = rd(W + '/kernel1-test2.bin', 0, 0x1E0)
import struct
total = struct.unpack('<I', kb[0x58:0x5C])[0]
uimg = rd(W + '/newuimg.bin')
print('vendor total ok:', total == len(uimg))
pay = rd(W + '/newpayload.bin')
po = pay.find(b'\x1f\x8b')
dec = zlib.decompress(pay[po:], 16 + zlib.MAX_WBITS)
cg = rd(W + '/newinit.cpio.gz')
print('splice ok:', dec[0x7bd448:0x7bd448 + len(cg)] == cg)
PYEOF
echo "[5] hook check"
zcat $W/newinit.cpio.gz | grep -a -c "agent-boot.sh"
echo BUILD_DONE
