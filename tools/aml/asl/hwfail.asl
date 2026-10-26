DefinitionBlock ("", "SSDT", 2, "OSUM", "HWFAIL", 0x00000001)
{
    External (\_SB.NORG, UnknownObj)
    Scope (\_SB)
    {
        Device (F1)
        {
            Name (_HID, "OSUM0001")
            Field (\_SB.NORG, ByteAcc, NoLock, Preserve)
            {
                FLDA, 8
            }
            Name (MARK, 0x55)
        }
    }
}
