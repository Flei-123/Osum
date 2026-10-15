# USB tethering (L-015 / r802)

| function | protocol lib | gate | driver |
|---|---|---|---|
| CDC-ECM | -- (raw Ethernet on bulk) | `tools/usbecm` (QEMU end to end) | `kernel/drv/net/usbnet.fi` |
| RNDIS | `lib/usbnet/rndis.fi` (`tools/usbnet/run.sh`) | `tools/usbrndis` (QEMU end to end, word `rndisonly`) | `kernel/drv/net/usbnet.fi` (mode 1) + bring-up `rndis_start` in `kernel/usb/usb.fi` |
| CDC-NCM | `lib/usbnet/ncm.fi` (`tools/ncm/run.sh`, 74 checks incl. static wiring) | -- (no NCM model in QEMU; real phone/dongle needed) | `kernel/drv/net/usbnet.fi` (mode 2) + bring-up `ncm_start` in `kernel/usb/usb.fi` |

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
NCM driver (r811, written, UNVERIFIED on hardware):
1. `usb.fi` `wanted`/`driver_for`: class 02/0D -> `DRV_NCM`, accepted only in pass 2 of `configure` (last resort like RNDIS; ECM wins).
2. Data interface = same layout as ECM (class 0A, bulk pipes in alternate setting >= 1): `ecm_data` is reused.
3. `ncm_start`: MAC string -> GET_NTB_PARAMETERS (`params_ok`, NTB16 supported) -> SET_NTB_INPUT_SIZE 2048 (= RX buffer; a refusal is
   tolerated, the xHC truncates a longer NTB) -> SET_INTERFACE data alt -> `usbnet.attach_ncm` (div/rem/align/outmax of the device).
   A failure prints `usb: ncm failed step=N` (1 MAC, 2 parameters, 4 interface, 5 attach).
4. `usbnet.fi` mode 2: TX = one NTB16 per frame (`wrap_frame`, cap min(2048, dwNtbOutMaxSize), sequence counter), ZLP on a multiple of
   the packet size; RX = `ntb_ok`, then every datagram of the NTB in turn (`ncm_next`); the transfer is re-queued after the last one,
   after the copy. Bad entries are skipped and counted.
NOT done: NTB32, CRC mode, SET_NET_ADDRESS, notification endpoint (link assumed up), hot unplug. Regression: tools/usbecm 8/0,
tools/usbrndis 12/0 with the NCM code in the kernel.
