#!/usr/bin/env python3
"""Disassemble stub preamble, hunt size constants + control flow."""
from capstone import Cs, CS_ARCH_ARM, CS_MODE_ARM
import struct

blob = open('/tmp/h10e-test2/newpayload.bin', 'rb').read()[:0x6614]
md = Cs(CS_ARCH_ARM, CS_MODE_ARM)
md.detail = False
insns = list(md.disasm(blob, 0x0))
print('total insns in preamble:', len(insns))
# collect LDR-literal loaded constants (size/address candidates)
consts = {}
for i in insns:
    if i.mnemonic == 'ldr' and '[' in i.op_str and 'pc' in i.op_str:
        try:
            off = int(i.op_str.split('#')[-1].rstrip(']'), 0)
        except Exception:
            continue
        # literal pool entry = align(pc+4)+off... approx: addr = (i.address + 8) & ~3 + off
        la = ((i.address + 8) & ~3) + off
        if la + 4 <= len(blob):
            v = struct.unpack('<I', blob[la:la + 4])[0]
            consts.setdefault(v, []).append(hex(i.address))
print('--- literal constants referenced ---')
for v in sorted(consts):
    print('0x%08x (%10d) at %s' % (v, v, ','.join(consts[v][:4])))
# branch targets outside stub? infinite loops (b self)?
print('--- branches to self / suspicious ---')
for i in insns:
    if i.mnemonic == 'b' and i.op_str.strip() == hex(i.address):
        print('infinite loop at', hex(i.address))
