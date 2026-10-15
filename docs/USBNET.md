# USB tethering (L-015 / r802)

| function | protocol lib | gate | driver |
|---|---|---|---|
| CDC-ECM | -- (raw Ethernet on bulk) | `tools/usbecm` (QEMU end to end) | `kernel/drv/net/usbnet.fi` |
| RNDIS | `lib/usbnet/rndis.fi` (`tools/usbnet/run.sh`) | `tools/usbrndis` (QEMU end to end, word `rndisonly`) | `kernel/drv/net/usbnet.fi` (mode 1) + bring-up `rndis_start` in `kernel/usb/usb.fi` |
| CDC-NCM | `lib/usbnet/ncm.fi` (`tools/ncm/run.sh`, 68 checks) | -- | none |

RNDIS driver (r811, done):
1. `usb.fi` `wanted`/`driver_for`: class 02/02/ff (QEMU), E0/01/03 (Android) and EF/04/01 -> `DRV_RNDIS`. `configure` walks the
   configurations twice: pass 1 WITHOUT RNDIS (so CDC-ECM wins when the device offers both), pass 2 accepts RNDIS when nothing
   else matched. Kernel word `rndisonly` (M_USBRNDIS) refuses ECM and takes RNDIS at once (test bed of the gate).
2. `rndis_data`: bulk pipes from the DATA interface (union descriptor, else control interface + 1; alt 0 or higher).
3. `rndis_start` on the control pipe (polling GET_ENCAPSULATED_RESPONSE, no notification endpoint): INITIALIZE (host max
   transfer 2048) -> QUERY OID_802_3_PERMANENT_ADDRESS (the MAC) -> SET packet filter (directed|multicast|broadcast) ->
   `usbnet.attach_rndis`. A failure prints `usb: rndis failed step=N`.
4. Data path in `usbnet.fi` (C_MODE = 1): TX `wrap_packet` (44 byte header) on bulk OUT (+ ZLP on a multiple of the packet size);
   RX unpacks every `packet_ok` PACKET_MSG of a transfer (several per transfer possible; the transfer is re-queued after the
   last one; a malformed packet drops the rest of the transfer).
Gate `tools/usbrndis/run.sh`: bound to rndis, MAC from OID query, DHCP lease, ping; control: without the word ECM is taken and
RNDIS never; without usb-net no rndis line.
NOT done: RNDIS keepalive/indications, hot unplug, real Android phone test (needs the boss and a phone).
NCM driver: needs a device (none in QEMU 7.2); bring-up GET_NTB_PARAMETERS -> SET_NTB_INPUT_SIZE ->
SET_NTB_FORMAT(0), data via `wrap_frame` / `ntb_dg_*`; alt setting 1 of the data interface carries the bulk pipes.
