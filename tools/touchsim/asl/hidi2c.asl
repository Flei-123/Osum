// SPDX-License-Identifier: GPL-2.0-only
// W-TOUCH4: HID-over-I2C devices as a laptop firmware names them (PNP0C50 in _HID or _CID, I2cSerialBus in _CRS,
// controller _ADR = PCI device/function, _DSM function 1 = HID description register). Controllers match the
// touchsim controllers by PCI device/function (I2C0 = dev 0, I2C1 = dev 1). SNS0 is a decoy (no PNP0C50) that
// must NEVER be probed. LID0 only makes acpiev hold the namespace.
DefinitionBlock ("", "SSDT", 2, "OSUM", "HIDI2C", 0x00000001)
{
    Scope (\_SB)
    {
        Device (LID0)
        {
            Name (_HID, EisaId ("PNP0C0D"))
            Method (_LID, 0, NotSerialized) { Return (One) }
        }
        Device (I2C0)
        {
            Name (_ADR, 0x00000000)
        }
        Device (I2C1)
        {
            Name (_ADR, 0x00010000)
        }
        Device (TPD0)
        {
            Name (_HID, "ELAN0001")
            Name (_CID, "PNP0C50")
            Method (_CRS, 0, NotSerialized)
            {
                Name (SBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x002C, ControllerInitiated, 0x00061A80, AddressingMode7Bit, "\\_SB.I2C0", 0x00, ResourceConsumer, , Exclusive, )
                })
                Return (SBUF)
            }
            Method (_DSM, 4, Serialized)
            {
                If (LEqual (Arg0, ToUUID ("3CDFF6F7-4267-4555-AD05-B30A3D8938DE")))
                {
                    If (LEqual (Arg2, Zero)) { Return (Buffer (One) { 0x03 }) }
                    If (LEqual (Arg2, One)) { Return (0x0001) }
                }
                Return (Buffer (One) { 0x00 })
            }
        }
        Device (TSC0)
        {
            Name (_HID, EisaId ("PNP0C50"))
            Method (_CRS, 0, NotSerialized)
            {
                Name (SBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0010, ControllerInitiated, 0x00061A80, AddressingMode7Bit, "\\_SB.I2C1", 0x00, ResourceConsumer, , Exclusive, )
                })
                Return (SBUF)
            }
            Method (_DSM, 4, Serialized)
            {
                If (LEqual (Arg2, One)) { Return (0x0020) }
                Return (Buffer (One) { 0x00 })
            }
        }
        Device (PEN0)
        {
            Name (_HID, "WCOM5002")
            Name (_CID, Package () { "ACPI\\WCOM5002", "PNP0C50" })
            Method (_CRS, 0, NotSerialized)
            {
                Name (SBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0011, ControllerInitiated, 0x00061A80, AddressingMode7Bit, "\\_SB.I2C1", 0x00, ResourceConsumer, , Exclusive, )
                })
                Return (SBUF)
            }
        }
        Device (SNS0)
        {
            Name (_HID, "BMA250E")
            Method (_CRS, 0, NotSerialized)
            {
                Name (SBUF, ResourceTemplate ()
                {
                    I2cSerialBusV2 (0x0015, ControllerInitiated, 0x00061A80, AddressingMode7Bit, "\\_SB.I2C0", 0x00, ResourceConsumer, , Exclusive, )
                })
                Return (SBUF)
            }
        }
    }
}
