// SPDX-License-Identifier: GPL-2.0-only
DefinitionBlock ("", "SSDT", 2, "OSUM", "NOBCM", 0x00000001)
{
    Scope (\_SB)
    {
        Device (GFX0)
        {
            Name (_ADR, 0x00020000)
            Device (LCD0)
            {
                Name (_ADR, 0x0400)
                Method (_BCL, 0, NotSerialized)
                {
                    Return (Package (0x03) { 0x64, 0x32, 0x00 })
                }
            }
        }
    }
}
