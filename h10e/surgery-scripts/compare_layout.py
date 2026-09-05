import zlib

def rd(p, off=0, n=None):
    with open(p, 'rb') as f:
        f.seek(off)
        return f.read() if n is None else f.read(n)

ST = '/mnt/hdd/h10e-latest/surgery/uImage_data.bin'
P = '/tmp/newpayload.bin'
V = '/tmp/vmlinux.new.gz'
VM = '/tmp/surgery/vmlinux'

st = rd(ST)
pay = rd(P)
print('stock len:', len(st), 'new payload len:', len(pay))
print('preamble identical (first 26132B):', st[:26132] == pay[:26132])

def gunzips(blob, name):
    print(name, 'gzip magics at:', end=' ')
    offs = []
    i = 0
    while True:
        i = blob.find(b'\x1f\x8b', i)
        if i < 0:
            break
        offs.append(i)
        i += 1
    print(['0x%x' % o for o in offs][:6])
    return offs

so = gunzips(st, 'stock')
po = gunzips(pay, 'payload')
decS = zlib.decompress(st[so[0]:], 16 + zlib.MAX_WBITS)
decN = zlib.decompress(pay[po[0]:], 16 + zlib.MAX_WBITS)
print('stock outer dec len:', len(decS), 'new outer dec len:', len(decN))
vm = rd(VM)
print('host vmlinux len:', len(vm))
print('stock dec starts with host vmlinux:', decS[:len(vm)] == vm)
# first difference between decS and decN
n = min(len(decS), len(decN))
i = next((k for k in range(n) if decS[k] != decN[k]), n)
print('first decS/decN diff at: 0x%x (lens %d/%d)' % (i, len(decS), len(decN)))
# inner gzip inside each
for nm, d in (('stock', decS), ('new', decN)):
    j = d.find(b'\x1f\x8b', 1)
    print(nm, 'inner magic at dec offset 0x%x' % j)
# trailer after outer gzip stream end: use compress object to find stream end
for nm, blob, off in (('stock', st, so[0]), ('new', pay, po[0])):
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    d.decompress(blob[off:])
    end = off + len(blob[off:]) - len(d.unused_data)
    print(nm, 'outer stream 0x%x..0x%x, trailer bytes: %d' % (off, end, len(blob) - end))
print('stock trailer == new trailer:', st[len(st)-8281:] == pay[len(pay)-8281:] if len(st) >= 8281 else 'n/a')
