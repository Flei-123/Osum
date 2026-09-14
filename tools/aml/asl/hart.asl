// DIE SCHWERE FASSUNG. Was echte Laptop-DSDTs zusaetzlich tun:
// Mutex um den EC, Sleep/Stall, CondRefOf, ToInteger/ToBuffer,
// Concatenate, SizeOf, DerefOf, Switch (in AML: If-Ketten), Event,
// Methodenaufrufe mit Argumenten, serialisierte Methoden, ein
// eingebetteter Controller mit _REG, und _OSI.
DefinitionBlock ("", "DSDT", 2, "OSUM", "HART", 0x00000001)
{
    Scope (\_SB)
    {
        Device (EC0)
        {
            Name (_HID, EisaId ("PNP0C09"))
            Name (_UID, One)
            Name (_GPE, 0x18)
            Mutex (ECMX, 0x00)
            Name (ECOK, Zero)

            OperationRegion (ERAM, EmbeddedControl, Zero, 0xFF)
            Field (ERAM, ByteAcc, Lock, Preserve)
            {
                Offset (0x04),
                BCNT,   8,
                BSTS,   8,
                Offset (0x10),
                BRC0,   16,
                BFC0,   16,
                BVOL,   16,
                ADPT,   1,
                LIDS,   1,
                    ,   6
            }

            Method (_REG, 2, NotSerialized)
            {
                If (LEqual (Arg0, 0x03))
                {
                    Store (Arg1, ECOK)
                }
            }

            Method (_Q0A, 0, NotSerialized)   // Deckel
            {
                Notify (\_SB.LID0, 0x80)
            }
            Method (_Q0B, 0, NotSerialized)   // Akku
            {
                Notify (\_SB.BAT0, 0x80)
            }
        }

        Device (LID0)
        {
            Name (_HID, EisaId ("PNP0C0D"))
            Method (_STA, 0, NotSerialized) { Return (0x0F) }
            Method (_LID, 0, Serialized)
            {
                If (LNot (\_SB.EC0.ECOK))
                {
                    Return (One)
                }
                Store (\_SB.EC0.LIDS, Local0)
                Return (Local0)
            }
        }

        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, One)
            Name (PBIF, Package (0x0D)
            {
                One, 0xFFFFFFFF, 0xFFFFFFFF, One, 0x2A30,
                Zero, Zero, 0x40, 0x40, "", "", "", ""
            })
            Name (PBST, Package (0x04) { Zero, 0xFFFFFFFF, 0xFFFFFFFF, 0x2A30 })

            Method (_STA, 0, NotSerialized)
            {
                If (LNot (\_SB.EC0.ECOK)) { Return (0x0F) }
                If (And (\_SB.EC0.BSTS, 0x01)) { Return (0x1F) }
                Return (0x0F)
            }

            Method (UPBI, 0, Serialized)
            {
                Acquire (\_SB.EC0.ECMX, 0xFFFF)
                Store (\_SB.EC0.BFC0, Local0)
                Multiply (Local0, 0x0A, Local1)
                Store (Local1, Index (PBIF, 0x01))
                Store (Local1, Index (PBIF, 0x02))
                Store (Divide (Local1, 0x0A, Local2, Local3), Index (PBIF, 0x05))
                Store ("BAT0", Index (PBIF, 0x09))
                Store (Concatenate ("LI", "ON"), Index (PBIF, 0x0B))
                Release (\_SB.EC0.ECMX)
                Return (Zero)
            }

            Method (_BIF, 0, NotSerialized)
            {
                UPBI ()
                Return (PBIF)
            }

            Method (_BST, 0, Serialized)
            {
                Acquire (\_SB.EC0.ECMX, 0xFFFF)
                Store (Zero, Local0)
                Store (\_SB.EC0.BSTS, Local1)
                If (And (Local1, 0x02))
                {
                    Store (0x02, Local0)        // laedt
                }
                Else
                {
                    If (And (Local1, 0x01))
                    {
                        Store (One, Local0)     // entlaedt
                    }
                }
                Store (Local0, Index (PBST, Zero))
                Store (\_SB.EC0.BRC0, Local2)
                Multiply (Local2, 0x0A, Local3)
                Store (Local3, Index (PBST, 0x02))
                Store (\_SB.EC0.BVOL, Local4)
                Store (Local4, Index (PBST, 0x03))
                Store (SizeOf (PBST), Local5)
                Release (\_SB.EC0.ECMX)
                Return (PBST)
            }

            Method (_BIX, 0, NotSerialized)
            {
                Name (PBIX, Package (0x14)
                {
                    Zero, One, 0x0FA0, 0x0FA0, One, 0x2A30,
                    Zero, Zero, 0x40, 0x40, 0x64, 0x64,
                    Zero, Zero, Zero, Zero,
                    "BAT0", "0001", "LION", "OSUM"
                })
                Return (PBIX)
            }
        }

        Device (ADP1)
        {
            Name (_HID, "ACPI0003")
            Method (_PSR, 0, NotSerialized)
            {
                If (LNot (\_SB.EC0.ECOK)) { Return (One) }
                Store (\_SB.EC0.ADPT, Local0)
                Return (Local0)
            }
        }

        Method (_INI, 0, NotSerialized)
        {
            If (CondRefOf (\_OSI))
            {
                If (\_OSI ("Windows 2015")) { Store (One, \_SB.EC0.ECOK) }
            }
        }
    }

    Scope (\_GPE)
    {
        Method (_L18, 0, NotSerialized)
        {
            Notify (\_SB.EC0, 0x80)
        }
        Method (_E03, 0, NotSerialized)
        {
            Store (0x0A, Local0)
            While (LGreater (Local0, Zero))
            {
                Decrement (Local0)
            }
            Notify (\_SB.LID0, 0x80)
        }
        Method (_L1D, 0, Serialized)
        {
            Sleep (0x0A)
            Stall (0x64)
            Notify (\_SB.BAT0, 0x80)
        }
    }
    Name (\_S5, Package (0x04) { 0x05, 0x05, Zero, Zero })
}
