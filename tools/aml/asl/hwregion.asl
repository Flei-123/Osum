DefinitionBlock ("", "SSDT", 2, "OSUM", "HWREG1", 0x00000001)
{
    External (\_SB.H3.TCBX, IntObj)
    Scope (\_SB)
    {
        Device (H1)
        {
            OperationRegion (TCBA, SystemIO, TCBB, 0x10)
            Name (TCBB, 0x1800)
            Name (MARK, 0x55)
        }

        Device (H2)
        {
            OperationRegion (RGN1, SystemMemory, 0x9F20, 0x10)
            Field (RGN1, ByteAcc, NoLock, Preserve)
            {
                FLD1, 16,
                FLD2, 16
            }
            OperationRegion (TCBA, SystemIO, FLD1, 0x10)
            Name (MARK, 0x55)
        }

        Device (H3)
        {
            OperationRegion (TCBA, SystemIO, TCBX, 0x10)
            Name (MARK, 0x55)
        }

        Device (H4)
        {
            Method (TCBM, 0, NotSerialized)
            {
                Return (0x1820)
            }
            OperationRegion (TCBA, SystemIO, TCBM (), 0x10)
            Method (TCBU, 0, NotSerialized)
            {
                Store (0x1830, Local0)
                If (LGreater (Local0, 0x10))
                {
                    Return (Local0)
                }
                Return (Zero)
            }
            OperationRegion (TCBB, SystemIO, TCBU (), 0x10)
            Name (MARK, 0x55)
        }

        Device (H5)
        {
            OperationRegion (RGN1, SystemMemory, 0x9F20, 0x10)
            Field (RGN1, ByteAcc, NoLock, Preserve)
            {
                FLD1, 16,
                FLD2, 16
            }
            OperationRegion (TCBA, SystemIO, Add (FLD1, 0x20), 0x10)
            OperationRegion (TCBB, SystemIO, And (FLD2, 0xFFF0), FLD2)
            Name (MARK, 0x55)
        }

        Device (H6)
        {
            OperationRegion (TCBA, SystemIO, 0x1840, TCBL)
            Name (TCBL, 0x10)
            Name (MARK, 0x55)
        }

        Device (H7)
        {
            Name (BUF0, Buffer (0x04) { 0x00, 0x18, 0x00, 0x00 })
            CreateDWordField (BUF0, Zero, BFLD)
            OperationRegion (TCBA, SystemIO, BFLD, 0x10)
            Name (MARK, 0x55)
        }

        Device (H8)
        {
            Name (PKG0, Package () { 0x1800, 0x1850 })
            OperationRegion (TCBA, SystemIO, DerefOf (Index (PKG0, One)), 0x10)
            OperationRegion (TCBB, SystemIO, \_SB.H8.TCBZ, 0x10)
            Name (TCBZ, 0x1860)
            Name (MARK, 0x55)
        }

        Device (H9)
        {
            OperationRegion (TCBA, SystemIO, Timer, 0x10)
            OperationRegion (TCBB, SystemIO, ToInteger ("0x1870"), 0x10)
            OperationRegion (TCBC, SystemIO, Multiply (Timer, 0x02), Divide (0x100, 0x10))
            OperationRegion (TCBD, SystemIO, ToInteger (Concatenate ("0x", "1880")), 0x10)
            Name (TCBL, 0x10)
            OperationRegion (TCBE, SystemIO, Add (ToInteger (Concatenate ("0x", "1890")), 0x10), Add (TCBL, 0x10))
            Name (MARK, 0x55)
        }

        Device (HA)
        {
            Method (ARGM, 1, NotSerialized)
            {
                OperationRegion (TCBA, SystemIO, Arg0, 0x10)
                Return (Zero)
            }
            Name (MARK, 0x55)
        }
    }
}
