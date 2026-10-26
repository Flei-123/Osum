// SPDX-License-Identifier: GPL-2.0-only
DefinitionBlock ("", "SSDT", 2, "OSUMTS", "ECAMAML", 1)
{
    External (\_SB.PCI0, DeviceObj)
    Scope (\_SB.PCI0)
    {
        Device (ERPT)
        {
            Name (_ADR, 0x00030000)
            OperationRegion (CFGX, PCI_Config, 0x100, 0x10)
            Field (CFGX, DWordAcc, NoLock, Preserve)
            {
                HDRX, 32,
            }
            Method (AERH, 0, NotSerialized)
            {
                Return (HDRX)
            }
        }
    }
}
