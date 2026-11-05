DefinitionBlock ("", "SSDT", 2, "OSUM", "BATPOISN", 1)
{
    External (\NOPE, MethodObj)
    Scope (\_SB)
    {
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, One)
            Name (CNT, Zero)
            Method (_STA, 0, NotSerialized) { Return (0x1F) }
            Method (_BIF, 0, NotSerialized)
            {
                If (CNT == Zero)
                {
                    CNT = One
                    NOPE ()
                }
                Return (Package (0x0D) { One, 5000, 5000, One, 0x2A30, 0x01F4, 0x00C8, 0x0A, 0x0A, "BAT", "0001", "LION", "osum" })
            }
            Method (_BST, 0, NotSerialized)
            {
                Return (Package (0x04) { One, 0x200, 2500, 0x2A30 })
            }
        }
    }
}
