#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'usbredir'))
from ax179model import Ax179Model
from rtl8153model import Rtl8153Model, PLA, USB

MAC = bytes([0x02, 0x11, 0x22, 0x33, 0x44, 0x55])


def ax_reference(log, link='up', usb='ss', skip=()):
    m = Ax179Model(MAC, log, link, usb)
    bulkin = [bytes([7, 0x4F, 0, 0x12, 0xFF]), bytes([7, 0x20, 3, 0x16, 0xFF]),
              bytes([7, 0xAE, 7, 0x18, 0xFF]), bytes([7, 0xCC, 0x4C, 0x18, 8])]

    def mw(reg, size, val):
        m.control(0x40, 1, reg, size, int(val).to_bytes(size, 'little'), size)

    def mr(reg, size):
        return m.control(0xC0, 1, reg, size, b'', size)

    def phy_r(reg):
        return struct.unpack('<H', m.control(0xC0, 2, 3, reg, b'', 2))[0]

    def phy_w(reg, val):
        m.control(0x40, 2, 3, reg, struct.pack('<H', val), 2)

    mw(0x26, 2, 0)
    mw(0x26, 2, 0x20)
    if 'clk' not in skip:
        mw(0x33, 1, 0x02 | 0x01)
    mac = mr(0x10, 6)
    mw(0x10, 6, int.from_bytes(mac, 'little'))
    m.control(0x40, 1, 0x2E, 5, bulkin[0], 5)
    mw(0x55, 1, 0x34)
    mw(0x54, 1, 0x52)
    mw(0x34, 1, 0x01 | 0x02 | 0x04 | 0x20 | 0x40)
    mw(0x35, 1, 0x01 | 0x02 | 0x04 | 0x20 | 0x40)
    if 'rxctl' not in skip:
        mw(0x0B, 2, 0x0100 | 0x0200 | 0x0080 | 0x0020 | 0x0002 | 0x0008)
    mw(0x24, 1, 0x40 | 0x20 | 0x04)
    if 'medium' not in skip:
        mw(0x22, 2, 0x0100 | 0x20 | 0x10 | 0x02 | 0x01)
    bmcr = phy_r(0)
    if bmcr & 0x1000 and 'anrestart' not in skip:
        phy_w(0, bmcr | 0x0200)
    physr = phy_r(0x11)
    if physr & 0x0400:
        link_sts = mr(0x02, 1)[0]
        mode = 0x0100 | 0x20 | 0x10
        speed = physr & 0xC000
        if speed == 0x8000:
            mode |= 0x01 | 0x08
            row = bulkin[0] if link_sts & 4 else bulkin[1] if link_sts & 2 else bulkin[3]
        elif speed == 0x4000:
            mode |= 0x0200
            row = bulkin[2] if link_sts & 6 else bulkin[3]
        else:
            row = bulkin[3]
        m.control(0x40, 1, 0x2E, 5, row, 5)
        if physr & 0x2000:
            mode |= 0x02
        mw(0x22, 2, mode)
    return m


def rtl_reference(log, family='8153a', link='up', usb_speed=3, skip=()):
    m = Rtl8153Model(MAC, log, family, link)

    def rd(ty, idx):
        return struct.unpack('<I', m.control(0xC0, 5, idx & 0xFFFC, ty, b'', 4))[0]

    def wr(ty, idx, byen, val):
        m.control(0x40, 5, idx, ty | byen | (byen << 4), struct.pack('<I', val), 4)

    def rdw(ty, idx):
        return (rd(ty, idx & ~3) >> ((idx & 2) * 8)) & 0xFFFF

    def rdb(ty, idx):
        return (rd(ty, idx & ~3) >> ((idx & 3) * 8)) & 0xFF

    def wrw(ty, idx, v):
        sh = idx & 2
        wr(ty, idx & ~3, 0x3 << sh, (v & 0xFFFF) << (sh * 8))

    def wrb(ty, idx, v):
        sh = idx & 3
        wr(ty, idx & ~3, 0x1 << sh, (v & 0xFF) << (sh * 8))

    def wrd(ty, idx, v):
        wr(ty, idx, 0xF, v)

    def setw(ty, idx, bits):
        wrw(ty, idx, rdw(ty, idx) | bits)

    def clrw(ty, idx, bits):
        wrw(ty, idx, rdw(ty, idx) & ~bits)

    def setb(ty, idx, bits):
        wrb(ty, idx, rdb(ty, idx) | bits)

    def clrb(ty, idx, bits):
        wrb(ty, idx, rdb(ty, idx) & ~bits)

    def clrd(ty, idx, bits):
        wrd(ty, idx, rd(ty, idx) & ~bits)

    def ocp_reg_r(addr):
        wrw(PLA, 0xE86C, addr & 0xF000)
        return rdw(PLA, (addr & 0x0FFF) | 0xB000)

    def ocp_reg_w(addr, v):
        wrw(PLA, 0xE86C, addr & 0xF000)
        wrw(PLA, (addr & 0x0FFF) | 0xB000, v)

    def mdio_r(reg):
        return ocp_reg_r(0xA400 + reg * 2)

    def mdio_w(reg, v):
        ocp_reg_w(0xA400 + reg * 2, v)

    def wait_ll():
        for _ in range(1000):
            if rdb(PLA, 0xE84F) & 0x02:
                return

    def nic_reset():
        wrb(PLA, 0xE813, 0x10)
        for _ in range(1000):
            if not rdb(PLA, 0xE813) & 0x10:
                break

    def teredo_off(fam):
        if fam == '8153b':
            wrb(PLA, 0xC0BC, 0xFF)
        else:
            clrw(PLA, 0xC0BC, 0x8000 | 0x00FE | 0x0001)
        wrw(PLA, 0xE428, 0x0010)
        wrw(PLA, 0xD2E8, 0)
        wrd(PLA, 0xD2CC, 0)

    def oob_exit():
        clrb(PLA, 0xE84F, 0x80)
        clrw(PLA, 0xE8DE, 0x4000)
        wait_ll()
        setw(PLA, 0xE8DE, 0x8000)
        wait_ll()

    version = (rd(PLA, 0xE610) >> 16) & 0x7CF0
    fam = {0x4C00: '8152', 0x4C10: '8152', 0x5C00: '8153a', 0x5C10: '8153a', 0x5C20: '8153a', 0x5C30: '8153a',
           0x6000: '8153b', 0x6010: '8153b'}[version]
    for _ in range(100):
        if rdw(PLA, 0xE004) & 0x0002 or 'autoload' in skip:
            break
    bmcr = mdio_r(0)
    if bmcr & 0x0800 and 'pdown' not in skip:
        mdio_w(0, bmcr & ~0x0800)
    clrw(USB, 0xD406, 0x0010 | 0x0080)
    lo = rd(PLA, 0xC000)
    hi = rd(PLA, 0xC004)
    if fam == '8152':
        clrd(PLA, 0xC010, 0xF)
        setw(PLA, 0xE85A, 0x0008)
        teredo_off('8152')
        wrb(PLA, 0xE81C, 0)
        wrb(PLA, 0xE813, 0)
        oob_exit()
        nic_reset()
        wrd(PLA, 0xC0A0, 0x00080002)
        if usb_speed < 3:
            wrd(PLA, 0xC0A4, 0x60)
            wrd(PLA, 0xC0A8, 0x78)
        else:
            wrd(PLA, 0xC0A4, 0x38)
            wrd(PLA, 0xC0A8, 0x48)
        wrd(PLA, 0xE618, 0x01000008)
        wrb(USB, 0xD40A, 0x03)
        wrd(USB, 0xD40C, 0x7A120180)
        wrd(USB, 0xD434, 0x00000101)
        clrw(PLA, 0xE854, 0x0040)
        wrw(PLA, 0xC016, 1522)
        setw(PLA, 0xE610, 0x0080)
    else:
        setw(PLA, 0xE85A, 0x0008)
        teredo_off(fam)
        clrd(PLA, 0xC010, 0xF)
        nic_reset()
        clrb(USB, 0xD4B0, 0x03)
        setb(USB, 0xD4B0, 0x03)
        oob_exit()
        clrw(PLA, 0xE854, 0x0040)
        wrw(PLA, 0xC016, 1522)
        wrb(PLA, 0xE615, 192)
        setw(PLA, 0xE610, 0x0080)
        nic_reset()
        wrd(PLA, 0xC0A0, 0x00080002)
        wrw(PLA, 0xC0A4, 0x00A0)
        wrw(PLA, 0xC0A8, 0x0110)
        wrd(PLA, 0xE618, 0x01000008)
    if fam == '8153b':
        wrw(USB, 0xCBFC, 0x0FFF)
        wrd(USB, 0xD40C, 0x00010001)
        clrw(PLA, 0xE0CC, 0x4000)
    adv = mdio_r(4)
    mdio_w(4, adv | 0x01E1)
    if fam != '8152':
        g = mdio_r(9)
        mdio_w(9, g | 0x0200)
    if 'anrestart' not in skip:
        mdio_w(0, 0x1200)

    status = rdw(PLA, 0xE908)
    if status & 0x02:
        if fam != '8152':
            coal = 15000 if fam == '8153b' else (85000 if usb_speed >= 4 else 250000 if usb_speed == 3 else 524280)
            if fam == '8153b':
                wrw(USB, 0xD42C, 128 // 8)
                wrw(USB, 0xD432, coal)
            else:
                wrw(USB, 0xD42C, coal // 8)
            room = 16384 - (1522 + 24 + 8)
            wrw(USB, 0xD42E, room // 8 if fam == '8153b' else room // 4)
            half = (status & 0x01) == 0
            slow = (status & 0x10) == 0
            ifg = 0x0200 if (slow and half) else 0x0300
            wrw(PLA, 0xE612, (rdw(PLA, 0xE612) & ~0x0308) | ifg)
        clrw(PLA, 0xC0B4, 0x0001)
        setw(PLA, 0xC0B4, 0x0001)
        if 'cr' not in skip:
            setb(PLA, 0xE813, 0x08 | 0x04)
        if fam == '8153b':
            wrb(USB, 0xD437, 0x03)
        if 'rxdy' not in skip:
            clrw(PLA, 0xE85A, 0x0008)
        m.control(0x40, 5, 0xCD00, PLA | 0xFF, bytes([0xFF] * 8), 8)
        rcr = rd(PLA, 0xC010)
        if 'rcr' not in skip:
            wrd(PLA, 0xC010, (rcr & ~0xF) | 0x0E)
    return m


def selftest():
    lines = []
    bad = 0

    def expect(name, cond):
        nonlocal bad
        print(('  OK    ' if cond else '  FAIL  ') + name)
        bad += 0 if cond else 1

    m = ax_reference(lambda s: lines.append(s))
    expect('ax179 reference: receive path enabled, no violation', m.can_rx() and m.violations == 0)
    for flag, what in (('clk', 'clock select'), ('rxctl', 'receive control'), ('anrestart', 'autonegotiation restart')):
        m = ax_reference(lambda s: None, skip=(flag,))
        expect('ax179 model refuses a driver without %s' % what, (not m.can_rx()) or m.violations > 0)
    m = ax_reference(lambda s: None, link='down')
    expect('ax179 model: link down keeps the receive path closed', not m.can_rx())
    for fam in ('8152', '8153a', '8153b'):
        m = rtl_reference(lambda s: None, fam)
        expect('rtl %s reference: receive and transmit path enabled, no violation' % fam, m.can_rx() and m.can_tx() and m.violations == 0)
        for flag, what in (('cr', 'CR RE/TE'), ('rxdy', 'RXDY gate release'), ('rcr', 'receive configuration'), ('anrestart', 'autonegotiation restart'), ('autoload', 'autoload wait')):
            m = rtl_reference(lambda s: None, fam, skip=(flag,))
            expect('rtl %s model refuses a driver without %s' % (fam, what), (not m.can_rx()) or m.violations > 0)
    m = rtl_reference(lambda s: None, '8153a', link='down')
    expect('rtl model: link down keeps the receive path closed', not m.can_rx())
    return bad


if __name__ == '__main__':
    which = sys.argv[1]
    if which == 'selftest':
        sys.exit(1 if selftest() else 0)
    out = []
    keep = lambda s: out.append(s) if s.startswith('W ') else None
    if which == 'ax179':
        ax_reference(keep, *sys.argv[2:4])
    else:
        rtl_reference(keep, which, *sys.argv[2:3])
    print('\n'.join(out))
