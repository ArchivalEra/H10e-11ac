import zlib

def rd(p, off=0, n=None):
    with open(p, 'rb') as f:
        f.seek(off)
        return f.read() if n is None else f.read(n)

ST = '/mnt/hdd/h10e-latest/surgery/uImage_data.bin'
P = '/tmp/newpayload.bin'
C = '/tmp/newinit.cpio.gz'
KST = '/mnt/hdd/h10e-latest/surgery/kernel1.bin'
KNW = '/tmp/kernel1.new.bin'

st = rd(ST); pay = rd(P)
so = st.find(b'\x1f\x8b'); po = pay.find(b'\x1f\x8b')
decS = zlib.decompress(st[so:], 16 + zlib.MAX_WBITS)
decN = zlib.decompress(pay[po:], 16 + zlib.MAX_WBITS)
cg = rd(C)
OFF = 0x7bd448
L_NEW = len(cg)
L_STOCK = 0x19ff65f
print('V1a new region == newinit.cpio.gz:', decN[OFF:OFF + L_NEW] == cg)
print('V1b tails match:', decN[OFF + L_NEW:] == decS[OFF + L_STOCK:])
print('V1c heads match:', decN[:OFF] == decS[:OFF])
print('V2 gzip hdr stock:', st[so:so + 10].hex(), 'new:', pay[po:po + 10].hex())
hs = rd(KST, 0, 0x1E0); hn = rd(KNW, 0, 0x1E0)
diffs = [i for i in range(0x1E0) if hs[i] != hn[i]]
print('V3 vendor hdr diff bytes:', ['0x%x' % i for i in diffs])
print('V3 magic:', hn[:16])
