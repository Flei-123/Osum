#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re, sys

SOURCE = 'kernel/user/codec/h264tab.fi'

def felder(path):
    s = open(path, encoding='utf-8').read()
    out = {}
    for m in re.finditer(r'static mut (\w+): \[u64; (\d+)\] = \[(.*?)\]',
                         s, re.S):
        name, n, body = m.group(1), int(m.group(2)), m.group(3)
        values = [int(x) for x in re.findall(r'-?\d+', body)]
        if len(values) != n:
            print("  %s: %d Werte, %d erwartet" % (name, len(values), n))
            return None
        out[name] = values
    return out

def check(name, lens, bits):
    codes = [(l, b) for l, b in zip(lens, bits) if l > 0]
    bad = 0
    for i in range(len(codes)):
        for j in range(i + 1, len(codes)):
            l1, b1 = codes[i]
            l2, b2 = codes[j]
            if l1 <= l2:
                if (b2 >> (l2 - l1)) == b1: bad += 1
            else:
                if (b1 >> (l1 - l2)) == b2: bad += 1
    kraft = sum(2.0 ** -l for l, _ in codes)
    return len(codes), bad, kraft

def main():
    F = felder(SOURCE)
    if F is None:
        return 1
    tafeln = []
    for k in range(4):
        tafeln.append(("coeff_token nC-Klasse %d" % k,
                       F['CT_LEN'][k*68:(k+1)*68],
                       F['CT_BITS'][k*68:(k+1)*68]))
    tafeln.append(("chroma_dc_coeff_token", F['CDC_LEN'], F['CDC_BITS']))
    for i in range(15):
        tafeln.append(("total_zeros tz=%d" % (i+1),
                       F['TZ_LEN'][i*16:(i+1)*16],
                       F['TZ_BITS'][i*16:(i+1)*16]))
    for i in range(3):
        tafeln.append(("chromadc_total_zeros %d" % (i+1),
                       F['TZC_LEN'][i*4:(i+1)*4],
                       F['TZC_BITS'][i*4:(i+1)*4]))
    for i in range(7):
        tafeln.append(("run_before zl=%d" % (i+1),
                       F['RUN_LEN'][i*16:(i+1)*16],
                       F['RUN_BITS'][i*16:(i+1)*16]))
    error = 0
    ncodes = 0
    for name, lens, bits in tafeln:
        n, bad, kraft = check(name, lens, bits)
        ncodes += n
        if bad or kraft > 1.0000001:
            error += 1
            print("  MEHRDEUTIG %-28s %3d Codes, %d Kollisionen, Kraft %.6f"
                  % (name, n, bad, kraft))
    if error:
        print("%d of %d tables are ambiguous" % (error, len(tafeln)))
        return 1
    print("%d tables, %d codes, 0 prefix collisions, all Kraft sums <= 1"
          % (len(tafeln), ncodes))
    return 0

if __name__ == '__main__':
    sys.exit(main())
