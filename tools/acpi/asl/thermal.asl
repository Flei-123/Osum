// SPDX-License-Identifier: GPL-2.0-only
DefinitionBlock ("", "SSDT", 2, "OSUM", "THERMAL", 0x00000001)
{
    Scope (\_SB)
    {
        OperationRegion (THRM, SystemMemory, 0x9F40, 0x10)
        Field (THRM, ByteAcc, NoLock, Preserve)
        {
            TZAV, 16,
            TZBV, 16,
            TZCV, 8,
            TZCS, 8
        }

        Mutex (TZMX, 0)
        Name (TCLS, 0)
    }

    Scope (\_TZ)
    {
        ThermalZone (TZA0)
        {
            Method (_TMP, 0, NotSerialized)
            {
                Return (\_SB.TZAV)
            }

            Method (_CRT, 0, NotSerialized)
            {
                Return (3732)
            }

            Method (_HOT, 0, NotSerialized)
            {
                Return (3632)
            }

            Method (_PSV, 0, NotSerialized)
            {
                Return (3232)
            }
        }
    }

    Scope (\_SB)
    {
        ThermalZone (TZB0)
        {
            Method (_TMP, 0, NotSerialized)
            {
                Return (\_SB.TZBV)
            }
        }
    }

    Scope (\_SB)
    {
        ThermalZone (TZC0)
        {
            Method (_STA, 0, NotSerialized)
            {
                Return (\_SB.TZCS)
            }

            Method (_PSV, 0, NotSerialized)
            {
                Store (\_SB.TZCV, Local0)
                Add (Local0, 20, Local0)
                Multiply (Local0, 10, Local0)
                Add (Local0, 0x0AAC, Local0)
                Return (Local0)
            }

            Method (_CRT, 0, NotSerialized)
            {
                Return (0x0FAC)
            }

            Method (_TMP, 0, Serialized)
            {
                Acquire (\_SB.TZMX, 0xFFFF)
                Store (\_SB.TZCV, Local0)
                Release (\_SB.TZMX)
                If (LNotEqual (Local0, \_SB.TCLS))
                {
                    Store (Local0, \_SB.TCLS)
                    Notify (TZC0, 0x81)
                }

                Multiply (Local0, 10, Local1)
                Add (Local1, 0x0AAC, Local1)
                Return (Local1)
            }
        }
    }
}
