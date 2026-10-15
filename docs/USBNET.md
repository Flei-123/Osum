# USB tethering (L-015 / r802)

| function | protocol lib | gate | driver |
|---|---|---|---|
| CDC-ECM | -- (raw Ethernet on bulk) | `tools/usbecm` (QEMU end to end) | `kernel/drv/net/usbnet.fi` |
| RNDIS | `lib/usbnet/rndis.fi` (`tools/usbnet/run.sh`) | -- | none |
| CDC-NCM | `lib/usbnet/ncm.fi` (`tools/ncm/run.sh`, 68 checks) | -- | none |

RNDIS driver plan (testable in QEMU: `usb-net` offers an RNDIS configuration):
1. `usb.fi` `wanted`/`driver_for`: class 02/02/ff (QEMU) and E0/01/03 (Android) -> `DRV_RNDIS`; prefer ECM when both
   exist, take RNDIS when it is the only one (QEMU gate: kernel word forces RNDIS).
2. Bring-up on the control pipe: SEND_ENCAPSULATED_COMMAND (0x21/0x00) INIT, GET_ENCAPSULATED_RESPONSE (0xA1/0x01),
   QUERY permanent MAC, SET packet filter -- all builders/validators are in `rndis.fi`.
3. Data path: TX `wrap_packet` (44 byte header) on bulk OUT, RX `packet_ok`/`packet_data_*` per transfer
   (several packets per transfer possible).
NCM driver: needs a device (none in QEMU 7.2); bring-up GET_NTB_PARAMETERS -> SET_NTB_INPUT_SIZE ->
SET_NTB_FORMAT(0), data via `wrap_frame` / `ntb_dg_*`; alt setting 1 of the data interface carries the bulk pipes.
