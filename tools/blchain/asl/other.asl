// SPDX-License-Identifier: GPL-2.0-only
DefinitionBlock ("", "SSDT", 2, "OSUM", "BLOTHER", 0x00000001)
{
    Scope (\_SB)
    {
        Device (PCI0)
        {
            Name (_HID, EisaId ("PNP0A08"))
            Name (_CID, EisaId ("PNP0A03"))
            Device (GFX0)
            {
                Name (_ADR, 0x00020000)
                Name (BLV, 100)
                Device (DD1F)
                {
                    Name (_ADR, 0x80000400)
                    Method (_BCL, 0, NotSerialized)
                    {
                        Return (Package (0x0D)
                        {
                            0x64, 0x32, 0x00, 0x0A, 0x14, 0x1E, 0x28, 0x32,
                            0x3C, 0x46, 0x50, 0x5A, 0x64
                        })
                    }
                    Method (_BCM, 1, NotSerialized)
                    {
                        Store (Arg0, \_SB.PCI0.GFX0.BLV)
                    }
                    Method (_BQC, 0, NotSerialized)
                    {
                        Return (\_SB.PCI0.GFX0.BLV)
                    }
                }
            }
        }
    }
}
