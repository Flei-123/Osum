DefinitionBlock ("", "SSDT", 2, "OSUM", "BATPLAIN", 1)
{
    Scope (\_SB)
    {
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, One)
            Method (_STA, 0, NotSerialized) { Return (0x1F) }
            Method (_BIF, 0, NotSerialized)
            {
                Return (Package (0x0D) { One, @FULL@, @FULL@, One, 0x2A30, 0x01F4, 0x00C8, 0x0A, 0x0A, "BAT", "0001", "LION", "osum" })
            }
            Method (_BST, 0, NotSerialized)
            {
                Return (Package (0x04) { @STATE@, @RATE@, @REM@, @VOLT@ })
            }
        }
    }
}
