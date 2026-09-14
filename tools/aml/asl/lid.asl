// Ein Deckel, ein Akku, eine Einschalttaste -- so, wie sie auf einem
// Laptop wirklich in der DSDT stehen. Nachgebaut nach ACPI 6.4
// Kapitel 9.4 (_LID), 10.2 (_BST/_BIF/_BIX) und 4.8.3.1 (GPE-Bloecke).
DefinitionBlock ("", "DSDT", 2, "OSUM", "LAPTOP", 0x00000001)
{
    Scope (\_SB)
    {
        // ------------------------------------------------ der Deckel
        Device (LID0)
        {
            Name (_HID, EisaId ("PNP0C0D"))
            Name (LIDS, One)          // 1 = offen
            Method (_LID, 0, NotSerialized)
            {
                Return (LIDS)
            }
            Name (_PRW, Package (0x02) { 0x18, 0x03 })
        }

        // ------------------------------------------------ die Taste
        Device (PWRB)
        {
            Name (_HID, EisaId ("PNP0C0C"))
            Name (_UID, Zero)
            Name (_PRW, Package (0x02) { 0x18, 0x03 })
        }

        // ------------------------------------------------ der Akku
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, One)
            Name (_STA, 0x1F)

            // Der eingebettete Controller, aus dem die Werte kommen.
            OperationRegion (ECRM, SystemIO, 0x62, 0x02)
            Field (ECRM, ByteAcc, Lock, Preserve)
            {
                ECMD, 8,
                EDAT, 8
            }

            Name (BFCC, 0x0FA0)       // Vollkapazitaet
            Name (BSTA, Package (0x04) { 0, 0, 0, 0 })

            Method (_BIF, 0, NotSerialized)
            {
                Name (BPKG, Package (0x0D)
                {
                    One, 0x0FA0, 0x0FA0, One, 0x2A30,
                    0x01A4, 0x0096, 0x0108, 0x0064,
                    "BAT0", "0001", "LION", "OSUM"
                })
                Return (BPKG)
            }

            Method (_BST, 0, NotSerialized)
            {
                Store (EDAT, Local0)
                And (Local0, 0x03, Local1)       // Zustandsbits
                ShiftRight (Local0, 0x02, Local2)
                Multiply (Local2, 0x0A, Local3)  // Restkapazitaet
                If (LGreater (Local3, BFCC))
                {
                    Store (BFCC, Local3)
                }
                Store (Local1, Index (BSTA, Zero))
                Store (0x01F4, Index (BSTA, One))
                Store (Local3, Index (BSTA, 0x02))
                Store (0x2A30, Index (BSTA, 0x03))
                Return (BSTA)
            }
        }

        Device (ACAD)
        {
            Name (_HID, "ACPI0003")
            Name (ACP, One)
            Method (_PSR, 0, NotSerialized) { Return (ACP) }
            Name (_PCL, Package (0x01) { \_SB })
        }
    }

    // ============================================ die GPE-Methoden
    // DAS IST DER PUNKT DER GANZEN RUNDE: was die Firmware beim
    // Ereignis wirklich ausfuehrt.
    Scope (\_GPE)
    {
        // Der Deckel, flankengesteuert (_Lxx = level, _Exx = edge).
        Method (_L18, 0, NotSerialized)
        {
            Notify (\_SB.LID0, 0x80)
            Notify (\_SB.PWRB, 0x80)
        }
        Method (_E1A, 0, NotSerialized)
        {
            Store (One, \_SB.LID0.LIDS)
            Notify (\_SB.LID0, 0x80)
        }
        // Der Akku.
        Method (_L1B, 0, NotSerialized)
        {
            Notify (\_SB.BAT0, 0x80)   // BST hat sich geaendert
            Notify (\_SB.BAT0, 0x81)   // BIF hat sich geaendert
            Notify (\_SB.ACAD, 0x80)
        }
    }

    Name (\_S5, Package (0x04) { 0x05, 0x05, Zero, Zero })
}
