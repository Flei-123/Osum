DefinitionBlock ("", "SSDT", 2, "OSUM", "ECTEST", 1)
{
    Scope (\_SB)
    {
        Device (EC0)
        {
            Name (_HID, EisaId ("PNP0C09"))
            Name (_UID, One)
            Name (_GPE, 0x1B)
            Name (_CRS, ResourceTemplate ()
            {
                IO (Decode16, 0x0062, 0x0062, 0x00, 0x01)
                IO (Decode16, 0x0066, 0x0066, 0x00, 0x01)
            })
            OperationRegion (ECOR, EmbeddedControl, Zero, 0x0100)
            Field (ECOR, ByteAcc, NoLock, Preserve)
            {
                Offset (0x04),
                VAL1, 8,
                Offset (0x08),
                OUTV, 8
            }
            Name (REGD, Zero)
            Method (_REG, 2, NotSerialized)
            {
                If (LAnd (LEqual (Arg0, 0x03), LEqual (Arg1, One)))
                {
                    Store (One, REGD)
                }
            }
            Method (_Q11, 0, NotSerialized)
            {
                Notify (EC0, 0x86)
            }
            Method (_Q12, 0, NotSerialized)
            {
                If (LEqual (VAL1, 0x5A))
                {
                    Store (0x77, OUTV)
                    Notify (EC0, 0x87)
                }
            }
        }
        Device (HPW)
        {
            Name (_HID, EisaId ("HPQ0001"))
        }
        Device (WMI0)
        {
            Name (_HID, "PNP0C14")
        }
    }
}
