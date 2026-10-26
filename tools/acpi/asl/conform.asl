DefinitionBlock ("", "SSDT", 2, "OSUM", "CONFORM", 1)
{
    Device (CNFM)
    {
        Name (V10, 0x10)
        Name (V3, 3)
        Name (V7, 7)
        Name (VA5, 0xA5)
        Name (VBIG, 0xFFFFFFFFFFFFFFFF)
        Name (S1, "abc")
        Name (S2, "defg")
        Name (S3, "0x2A")
        Name (S4, "123")
        Name (B1, Buffer (4) { 0x01, 0x02, 0x03, 0x04 })
        Name (B2, Buffer (2) { 0xAA, 0xBB })
        Name (P1, Package (4) { 10, 20, 30, 40 })
        Name (P2, Package (2) { Package (2) { 1, 2 }, Package (2) { 3, 4 } })
        Name (P3, Package (3) { "x", "yz", 5 })
        Name (CNT, 0)
        Mutex (MX0, 0)
        Event (EV0)
        Alias (V10, AL10)

        OperationRegion (MEM0, SystemMemory, 0x9F80, 0x20)
        Field (MEM0, ByteAcc, NoLock, Preserve)
        {
            FB0, 8,
            FB1, 8,
            FW0, 16,
            FD0, 32,
            FQ0, 64
        }
        Field (MEM0, ByteAcc, NoLock, Preserve)
        {
            Offset (0x10),
            FA, 1,
            FB, 3,
            FC, 4,
            FD, 8
        }
        Field (MEM0, ByteAcc, NoLock, Preserve)
        {
            Offset (0x10),
            FE, 8
        }

        OperationRegion (MEM1, SystemMemory, 0x9FA0, 0x40)
        Field (MEM1, ByteAcc, NoLock, Preserve)
        {
            WA, 128,
            WB, 8,
            , 4,
            WD, 100,
            WE, 8
        }

        Method (HELP, 2, NotSerialized) { Return (Add (Arg0, Arg1)) }
        Method (HEL7, 7, NotSerialized) { Return (Add (Arg0, Add (Arg1, Add (Arg2, Add (Arg3, Add (Arg4, Add (Arg5, Arg6))))))) }
        Method (FACT, 1, NotSerialized)
        {
            If (LLessEqual (Arg0, 1)) { Return (1) }
            Return (Multiply (Arg0, FACT (Subtract (Arg0, 1))))
        }
        Method (RSTR, 0, NotSerialized) { Return (Concatenate (S1, S2)) }
        Method (RBUF, 0, NotSerialized) { Return (Buffer (3) { 7, 8, 9 }) }
        Method (RPKG, 0, NotSerialized) { Return (Package (2) { 5, 6 }) }

        Method (T001, 0, NotSerialized) { Store (Add (V10, V3), Local0) If (LNotEqual (Local0, 0x13)) { Return (1) } Return (0) }
        Method (T002, 0, NotSerialized) { Store (Subtract (V10, V3), Local0) If (LNotEqual (Local0, 0x0D)) { Return (2) } Return (0) }
        Method (T003, 0, NotSerialized) { Store (Multiply (V10, V3), Local0) If (LNotEqual (Local0, 0x30)) { Return (3) } Return (0) }
        Method (T004, 0, NotSerialized) { Divide (V10, V3, Local1, Local0) If (LNotEqual (Local0, 5)) { Return (4) } If (LNotEqual (Local1, 1)) { Return (5) } Return (0) }
        Method (T006, 0, NotSerialized) { Store (Mod (V10, V3), Local0) If (LNotEqual (Local0, 1)) { Return (6) } Return (0) }
        Method (T007, 0, NotSerialized) { Store (ShiftLeft (V3, V7), Local0) If (LNotEqual (Local0, 0x180)) { Return (7) } Return (0) }
        Method (T008, 0, NotSerialized) { Store (ShiftRight (VA5, 4), Local0) If (LNotEqual (Local0, 0x0A)) { Return (8) } Return (0) }
        Method (T009, 0, NotSerialized) { Store (And (VA5, 0x0F), Local0) If (LNotEqual (Local0, 0x05)) { Return (9) } Return (0) }
        Method (T010, 0, NotSerialized) { Store (Or (VA5, 0x0F), Local0) If (LNotEqual (Local0, 0xAF)) { Return (10) } Return (0) }
        Method (T011, 0, NotSerialized) { Store (Xor (VA5, 0xFF), Local0) If (LNotEqual (Local0, 0x5A)) { Return (11) } Return (0) }
        Method (T012, 0, NotSerialized) { Store (Not (V10), Local0) If (LNotEqual (Local0, 0xFFFFFFFFFFFFFFEF)) { Return (12) } Return (0) }
        Method (T013, 0, NotSerialized) { Store (Nand (VA5, 0xFF), Local0) If (LNotEqual (Local0, 0xFFFFFFFFFFFFFF5A)) { Return (13) } Return (0) }
        Method (T014, 0, NotSerialized) { Store (Nor (VA5, 0xFF), Local0) If (LNotEqual (Local0, 0xFFFFFFFFFFFFFF00)) { Return (14) } Return (0) }
        Method (T015, 0, NotSerialized) { Store (FindSetLeftBit (VA5), Local0) If (LNotEqual (Local0, 8)) { Return (15) } Store (FindSetRightBit (VA5), Local1) If (LNotEqual (Local1, 1)) { Return (16) } Return (0) }
        Method (T017, 0, NotSerialized) { Store (V10, Local0) Increment (Local0) Increment (Local0) Decrement (Local0) If (LNotEqual (Local0, 0x11)) { Return (17) } Return (0) }
        Method (T018, 0, NotSerialized) { Add (VBIG, 1, Local0) If (LNotEqual (Local0, 0)) { Return (18) } Return (0) }
        Method (T019, 0, NotSerialized) { If (LAnd (V3, 0)) { Return (19) } If (LOr (0, 0)) { Return (20) } If (LNot (LOr (V3, 0))) { Return (21) } Return (0) }
        Method (T022, 0, NotSerialized) { If (LGreater (V3, V10)) { Return (22) } If (LLess (V10, V3)) { Return (23) } If (LNot (LGreaterEqual (V10, V10))) { Return (24) } If (LNot (LLessEqual (V3, V10))) { Return (25) } If (LNotEqual (V3, 3)) { Return (26) } Return (0) }
        Method (T027, 0, NotSerialized) { If (LNotEqual (S1, "abc")) { Return (27) } If (LEqual (S1, "abd")) { Return (28) } If (LNot (LLess (S1, S2))) { Return (29) } Return (0) }
        Method (T030, 0, NotSerialized) { Store (Concatenate (S1, S2), Local0) If (LNotEqual (Local0, "abcdefg")) { Return (30) } If (LNotEqual (SizeOf (Local0), 7)) { Return (31) } Return (0) }
        Method (T032, 0, NotSerialized) { Store (Concatenate (S1, 0x1F), Local0) If (LNotEqual (Local0, "abc1F")) { Return (32) } Return (0) }
        Method (T033, 0, NotSerialized) { Store (Concatenate (B1, B2), Local0) If (LNotEqual (SizeOf (Local0), 6)) { Return (33) } If (LNotEqual (DerefOf (Index (Local0, 4)), 0xAA)) { Return (34) } If (LNotEqual (DerefOf (Index (Local0, 0)), 1)) { Return (35) } Return (0) }
        Method (T036, 0, NotSerialized) { Store (Concatenate (V10, V3), Local0) If (LNotEqual (SizeOf (Local0), 16)) { Return (36) } If (LNotEqual (DerefOf (Index (Local0, 0)), 0x10)) { Return (37) } If (LNotEqual (DerefOf (Index (Local0, 8)), 3)) { Return (38) } Return (0) }
        Method (T039, 0, NotSerialized) { Store (Mid ("hello world", 6, 5), Local0) If (LNotEqual (Local0, "world")) { Return (39) } Store (Mid (S2, 1, 100), Local1) If (LNotEqual (Local1, "efg")) { Return (40) } Return (0) }
        Method (T041, 0, NotSerialized) { Store (Mid (B1, 1, 2), Local0) If (LNotEqual (SizeOf (Local0), 2)) { Return (41) } If (LNotEqual (DerefOf (Index (Local0, 0)), 2)) { Return (42) } Return (0) }
        Method (T043, 0, NotSerialized) { Store (ToString (B1, 2), Local0) If (LNotEqual (SizeOf (Local0), 2)) { Return (43) } Return (0) }
        Method (T044, 0, NotSerialized) { Store (ToHexString (VA5), Local0) If (LNotEqual (Local0, "A5")) { Return (44) } Store (ToDecimalString (V10), Local1) If (LNotEqual (Local1, "16")) { Return (45) } Return (0) }
        Method (T046, 0, NotSerialized) { Store (ToInteger (S3), Local0) If (LNotEqual (Local0, 0x2A)) { Return (46) } Store (ToInteger (S4), Local1) If (LNotEqual (Local1, 123)) { Return (47) } Return (0) }
        Method (T048, 0, NotSerialized) { Store (ToBuffer (V10), Local0) If (LNotEqual (SizeOf (Local0), 8)) { Return (48) } If (LNotEqual (DerefOf (Index (Local0, 0)), 0x10)) { Return (49) } Return (0) }
        Method (T050, 0, NotSerialized) { If (LNotEqual (DerefOf (Index (P1, 2)), 30)) { Return (50) } If (LNotEqual (SizeOf (P1), 4)) { Return (51) } Return (0) }
        Method (T052, 0, NotSerialized) { If (LNotEqual (DerefOf (Index (DerefOf (Index (P2, 1)), 0)), 3)) { Return (52) } Return (0) }
        Method (T053, 0, NotSerialized) { Store (Package (3) { 1, 2, 3 }, Local0) Store (99, Index (Local0, 1)) If (LNotEqual (DerefOf (Index (Local0, 1)), 99)) { Return (53) } If (LNotEqual (DerefOf (Index (Local0, 2)), 3)) { Return (54) } Return (0) }
        Method (T055, 0, NotSerialized) { Store (Match (P1, MEQ, 30, MTR, 0, 0), Local0) If (LNotEqual (Local0, 2)) { Return (55) } Store (Match (P1, MGE, 25, MTR, 0, 0), Local1) If (LNotEqual (Local1, 2)) { Return (56) } Store (Match (P1, MGT, 40, MTR, 0, 0), Local2) If (LNotEqual (Local2, Ones)) { Return (57) } Store (Match (P1, MLE, 20, MGE, 20, 0), Local3) If (LNotEqual (Local3, 1)) { Return (58) } Return (0) }
        Method (T059, 0, NotSerialized) { Store (Buffer (4) { 0, 0, 0, 0 }, Local0) CreateByteField (Local0, 1, BYT) CreateWordField (Local0, 2, WRD) Store (0x5A, BYT) Store (0x1234, WRD) If (LNotEqual (DerefOf (Index (Local0, 1)), 0x5A)) { Return (59) } If (LNotEqual (DerefOf (Index (Local0, 2)), 0x34)) { Return (60) } If (LNotEqual (DerefOf (Index (Local0, 3)), 0x12)) { Return (61) } Return (0) }
        Method (T062, 0, NotSerialized) { Store (Buffer (8) { 0, 0, 0, 0, 0, 0, 0, 0 }, Local0) CreateDWordField (Local0, 0, DW) CreateQWordField (Local0, 0, QW) CreateBitField (Local0, 63, BT) Store (0x11223344, DW) If (LNotEqual (DerefOf (Index (Local0, 3)), 0x11)) { Return (62) } Store (1, BT) If (LNotEqual (DerefOf (Index (Local0, 7)), 0x80)) { Return (63) } If (LNotEqual (QW, 0x8000000011223344)) { Return (64) } Return (0) }
        Method (T065, 0, NotSerialized) { Store (0x5A, FB0) Store (0xC3, FB1) If (LNotEqual (FW0, 0)) { Return (65) } Store (0x1234, FW0) If (LNotEqual (FW0, 0x1234)) { Return (66) } Store (0xDEADBEEF, FD0) If (LNotEqual (FD0, 0xDEADBEEF)) { Return (67) } If (LNotEqual (FB0, 0x5A)) { Return (68) } Return (0) }
        Method (T069, 0, NotSerialized) { Store (0, FE) Store (0, FD) Store (1, FA) Store (5, FB) Store (0xC, FC) If (LNotEqual (FA, 1)) { Return (69) } If (LNotEqual (FB, 5)) { Return (70) } If (LNotEqual (FC, 0xC)) { Return (71) } If (LNotEqual (FE, 0xCB)) { Return (72) } If (LNotEqual (FD, 0)) { Return (73) } Return (0) }
        Method (T073, 0, NotSerialized) { Store (0x0123456789ABCDEF, FQ0) If (LNotEqual (FQ0, 0x0123456789ABCDEF)) { Return (73) } Return (0) }
        Method (T074, 0, NotSerialized) { Store (Zero, Local0) Store (0, Local1) While (LLess (Local0, 10)) { Increment (Local0) If (LEqual (Local0, 3)) { Continue } If (LEqual (Local0, 8)) { Break } Add (Local1, Local0, Local1) } If (LNotEqual (Local1, 25)) { Return (74) } Return (0) }
        Method (T075, 0, NotSerialized) { If (LEqual (V3, 4)) { Return (75) } ElseIf (LEqual (V3, 3)) { Return (0) } Else { Return (76) } }
        Method (T077, 0, NotSerialized) { If (LNotEqual (HELP (V10, V3), 0x13)) { Return (77) } If (LNotEqual (HEL7 (1, 2, 3, 4, 5, 6, 7), 28)) { Return (78) } Return (0) }
        Method (T079, 0, NotSerialized) { If (LNotEqual (FACT (5), 120)) { Return (79) } If (LNotEqual (FACT (10), 3628800)) { Return (80) } Return (0) }
        Method (T081, 0, NotSerialized) { If (LNotEqual (RSTR (), "abcdefg")) { Return (81) } Store (RBUF (), Local0) If (LNotEqual (DerefOf (Index (Local0, 2)), 9)) { Return (82) } Store (RPKG (), Local1) If (LNotEqual (DerefOf (Index (Local1, 1)), 6)) { Return (83) } Return (0) }
        Method (T084, 0, NotSerialized) { Store (V10, CNT) Add (CNT, 1, CNT) If (LNotEqual (CNT, 0x11)) { Return (84) } If (LNotEqual (AL10, 0x10)) { Return (85) } Return (0) }
        Method (T086, 0, NotSerialized) { If (LNotEqual (_OSI ("Windows 2015"), Ones)) { Return (86) } If (LNotEqual (_OSI ("Linux"), 0)) { Return (87) } If (LNotEqual (_OSI ("Processor Device"), Ones)) { Return (88) } Return (0) }
        Method (T089, 0, NotSerialized) { If (LNotEqual (\_REV, 2)) { Return (89) } If (LNotEqual (SizeOf (\_OS), 20)) { Return (90) } Return (0) }
        Method (T091, 0, NotSerialized) { Store (Timer, Local0) Stall (50) Store (Timer, Local1) If (LLessEqual (Local1, Local0)) { Return (91) } If (LGreater (Subtract (Local1, Local0), 5000000)) { Return (92) } Return (0) }
        Method (T093, 0, NotSerialized) { If (LNotEqual (Acquire (MX0, 0xFFFF), 0)) { Return (93) } Release (MX0) Return (0) }
        Method (T094, 0, NotSerialized) { Signal (EV0) If (LNotEqual (Wait (EV0, 100), 0)) { Return (94) } If (LEqual (Wait (EV0, 100), 0)) { Return (95) } Signal (EV0) Reset (EV0) If (LEqual (Wait (EV0, 100), 0)) { Return (96) } Return (0) }
        Method (T097, 0, NotSerialized) { If (LNotEqual (ToBCD (1234), 0x1234)) { Return (97) } If (LNotEqual (FromBCD (0x4321), 4321)) { Return (98) } Return (0) }
        Method (T099, 0, NotSerialized) { If (LNot (CondRefOf (V10))) { Return (99) } If (CondRefOf (NOPE)) { Return (100) } Return (0) }
        Method (T101, 0, NotSerialized) { If (LNotEqual (ObjectType (V10), 1)) { Return (101) } If (LNotEqual (ObjectType (S1), 2)) { Return (102) } If (LNotEqual (ObjectType (B1), 3)) { Return (103) } If (LNotEqual (ObjectType (P1), 4)) { Return (104) } Return (0) }
        Method (T106, 0, NotSerialized) { Store (0x9F90, Local7) OperationRegion (RT0, SystemMemory, Local7, 4) Field (RT0, ByteAcc, NoLock, Preserve) { RTA, 8, RTB, 8 } Store (0x3C, RTA) Store (0xC3, RTB) If (LNotEqual (RTA, 0x3C)) { Return (106) } If (LNotEqual (RTB, 0xC3)) { Return (107) } Return (0) }
        Method (T108, 0, NotSerialized) { Store (1, Local0) Store (Local0, Debug) Noop Return (0) }
        Method (T109, 0, NotSerialized) { Store (Revision, Local0) If (LLess (Local0, 2)) { Return (109) } Return (0) }
        Method (T110, 0, NotSerialized) { Store (0xFF, Local0) Store (Local0, FB0) Store (FB0, Local1) If (LNotEqual (Local1, 0xFF)) { Return (110) } Return (0) }
        Method (T111, 0, NotSerialized) { Store (Concatenate ("ab", "cd"), Local0) Store (Mid (Local0, 1, 2), Local1) If (LNotEqual (Local1, "bc")) { Return (111) } Return (0) }
        Method (T112, 0, NotSerialized) { Store (Package (2) { "x", 3 }, Local0) If (LNotEqual (DerefOf (Index (Local0, 0)), "x")) { Return (112) } If (LNotEqual (DerefOf (Index (P3, 1)), "yz")) { Return (113) } Return (0) }
        Method (T114, 0, NotSerialized) { Store (ConcatenateResTemplate (ResourceTemplate () { IO (Decode16, 0x60, 0x60, 1, 1) }, ResourceTemplate () { IRQNoFlags () { 9 } }), Local0) If (LNotEqual (SizeOf (Local0), 13)) { Return (114) } If (LNotEqual (DerefOf (Index (Local0, 8)), 0x22)) { Return (115) } Return (0) }
        Method (T116, 0, NotSerialized) { Store (Buffer (16) { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }, WA) Store (0x5A, WB) Store (WA, Local0) If (LNotEqual (SizeOf (Local0), 16)) { Return (116) } If (LNotEqual (DerefOf (Index (Local0, 0)), 1)) { Return (117) } If (LNotEqual (DerefOf (Index (Local0, 15)), 16)) { Return (118) } If (LNotEqual (WB, 0x5A)) { Return (119) } Return (0) }
        Method (T120, 0, NotSerialized) { Store (Buffer (13) { 0xFF, 0x00, 0xAA, 0x55, 1, 2, 3, 4, 5, 6, 7, 8, 0x0F }, WD) Store (0x33, WE) Store (WD, Local0) If (LNotEqual (SizeOf (Local0), 13)) { Return (120) } If (LNotEqual (DerefOf (Index (Local0, 0)), 0xFF)) { Return (121) } If (LNotEqual (DerefOf (Index (Local0, 2)), 0xAA)) { Return (122) } If (LNotEqual (DerefOf (Index (Local0, 12)), 0x0F)) { Return (123) } If (LNotEqual (WE, 0x33)) { Return (124) } Return (0) }
        Method (TBAD, 0, NotSerialized) { Return (999) }
    }
}
