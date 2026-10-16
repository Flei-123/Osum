# SPDX-License-Identifier: GPL-2.0-only
# Input builder + independent expectation for tools/wlan/scanfmt.fi.
#   scanfmt_ref.py <mitschnitt.txt> <in.txt> <expect.txt>
import struct, sys

def mgmt_beacon(ssid, chan, caps, extra_ies=b'', bssid=b'\x02\x00\x00\x00\x00\x01'):
    hdr = struct.pack('<HH6s6s6sH', 0x0080, 0, b'\xff' * 6, bssid, bssid, 0)
    fixed = struct.pack('<QHH', 0, 100, caps)
    ies = bytes([0, len(ssid)]) + ssid + bytes([1, 1, 0x82]) + bytes([3, 1, chan]) + extra_ies
    return hdr + fixed + ies

def rsn_wpa2():
    # RSN IE: ver 1, group CCMP, 1 pairwise CCMP, 1 AKM PSK, caps 0
    body = struct.pack('<H', 1) + b'\x00\x0f\xac\x04' + struct.pack('<H', 1) + b'\x00\x0f\xac\x04' + struct.pack('<H', 1) + b'\x00\x0f\xac\x02' + b'\x00\x00'
    return bytes([48, len(body)]) + body

def main():
    mit, inp, exp = sys.argv[1:4]
    real = [l.split()[1] for l in open(mit) if l.startswith('beacon ')]
    dbs = [int(l.split()[1]) for l in open(mit) if l.startswith('beacon_db ')]
    lines, expect = [], []
    for h, db in zip(real, dbs):
        lines.append('%d %s' % (-db, h))
    expect.append('Coherer ch=1 sec=wpa2 rssi=-%d' % min(dbs))
    # open network (caps ESS only), SSID with a forged newline + space -> sanitised
    lines.append('-61 ' + mgmt_beacon(b'Caf\nE x', 6, 0x0001).hex())
    expect.append('Caf?E?x ch=6 sec=open rssi=-61')
    # WEP (privacy bit)
    lines.append('-70 ' + mgmt_beacon(b'oldwep', 11, 0x0011, bssid=b'\x02\x00\x00\x00\x00\x02').hex())
    expect.append('oldwep ch=11 sec=wep rssi=-70')
    # hidden network (empty SSID) is not listed
    lines.append('-50 ' + mgmt_beacon(b'', 3, 0x0001, bssid=b'\x02\x00\x00\x00\x00\x03').hex())
    # stronger duplicate of the open network wins
    lines.append('-40 ' + mgmt_beacon(b'Caf\nE x', 6, 0x0001).hex())
    expect[1] = 'Caf?E?x ch=6 sec=open rssi=-40'
    # truncated frame: ignored
    lines.append('-30 ' + mgmt_beacon(b'cut', 1, 0x0001).hex()[:40])
    open(inp, 'w').write('\n'.join(lines) + '\n')
    open(exp, 'w').write('\n'.join(expect) + '\n')

main()
