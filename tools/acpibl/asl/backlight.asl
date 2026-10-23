// SPDX-License-Identifier: GPL-2.0-only
DefinitionBlock ("", "SSDT", 2, "OSUM", "BLIGHT", 0x00000001)
{
    Scope (\_SB)
    {
        OperationRegion (BLST, SystemMemory, 0x9F20, 0x10)
        Field (BLST, ByteAcc, NoLock, Preserve)
        {
            BLVL, 8,
            BCNT, 8
        }

        Device (GFX0)
        {
            Name (_ADR, 0x00020000)
            Device (LCD0)
            {
                Name (_ADR, 0x0400)
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
                    Store (Arg0, BLVL)
                    Add (BCNT, One, BCNT)
                }
                Method (_BQC, 0, NotSerialized)
                {
                    Return (BLVL)
                }
            }
        }
    }
}
