DefinitionBlock ("", "SSDT", 2, "OSUM", "HWREG2", 0x00000001)
{
    External (\_SB.H3, DeviceObj)
    Scope (\_SB.H3)
    {
        Name (TCBX, 0x1810)
    }
}
