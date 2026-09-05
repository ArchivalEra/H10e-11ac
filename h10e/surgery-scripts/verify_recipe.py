import zlib, struct, sys

def rd(p, off=0, n=None):
    with open(p, 'rb') as f:
        f.seek(off)
        return f.read() if n is None else f.read(n)

K = '/tmp/kernel1.new.bin'
U = '/tmp/newuimg.bin'
V = '/tmp/vmlinux.new.gz'
VM = '/tmp/surgery/vmlinux'
C = '/tmp/newinit.cpio.gz'
P = '/tmp/newpayload.bin'

kb = rd(K, 0, 0x1E0)
total, crc = struct.unpack('<II', kb[0x58:0x60])
uimg = rd(U)
print('vendor total field:', total, 'actual uimg len:', len(uimg), 'match:', total == len(uimg))
print('vendor crc field:  %08x' % crc, 'crc32(uimg): %08x' % (zlib.crc32(uimg) & 0xffffffff),
      'match:', crc == (zlib.crc32(uimg) & 0xffffffff))
print('kernel1 len:', len(rd(K)), '== 0x1E0 + uimg:', len(rd(K)) == 0x1E0 + len(uimg))
print('uimg tail == kernel1 tail:', rd(U)[-16:] == rd(K)[-16:])

vg = rd(V)
dec = zlib.decompress(vg, 16 + zlib.MAX_WBITS)
vm = rd(VM)
print('outer gunzip len:', len(dec), 'vmlinux len:', len(vm), 'prefix match:', dec[:len(vm)] == vm)
inner_off = dec.find(b'\x1f\x8b', 1)
print('inner gzip magic at decompressed offset: 0x%x' % inner_off)
cg = rd(C)
print('suffix == newinit.cpio.gz:', dec[inner_off:] == cg if inner_off > 0 else False)

pay = rd(P)
print('payload len:', len(pay), 'vmlinux.new.gz len:', len(vg), 'delta:', len(pay) - len(vg))
print('payload start == vmlinux.new.gz start:', pay[:64] == vg[:64])
print('payload end == vmlinux.new.gz end:', pay[-64:] == vg[-64:])
# find where vg sits inside payload
i = pay.find(vg[:32])
print('vg header found in payload at:', i)
