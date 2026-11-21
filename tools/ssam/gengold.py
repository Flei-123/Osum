import struct
import sys

import ref

KBD_REPORT = bytes([0, 0, 4, 0, 0, 0, 0, 0])
HUGE_HEAD = struct.pack("<BHB", 0x00, 0x4000, 0)
SYN_HUGE = ref.SYN + HUGE_HEAD + struct.pack("<H", ref.crc16(HUGE_HEAD))


def cases():
    desc_req = ref.descriptor_request(1, 0, 0x76)
    good_event = ref.event_frame(7, ref.TC_HID, ref.TID_KIP, 1, 0, KBD_REPORT)
    bad_payload = bytearray(good_event)
    bad_payload[-1] ^= 0x01
    bad_header = bytearray(good_event)
    bad_header[6] ^= 0x01
    return {
        "ack5": ref.ack(5),
        "ack0": ref.ack(0),
        "nak": ref.nak(),
        "req_desc": ref.request_frame(0, 39, ref.TC_HID, ref.TID_KIP, 1, 4, desc_req),
        "req_desc_seq1": ref.request_frame(1, 40, ref.TC_HID, ref.TID_KIP, 1, 4, desc_req),
        "req_evreg": ref.request_frame(0, 39, ref.TC_REG, ref.TID_KIP, 0, 1, ref.event_params(ref.TC_HID, 1)),
        "req_empty": ref.request_frame(0, 39, ref.TC_SAM, ref.TID_SAM, 0, 0x13),
        "evt_kbd": good_event,
        "evt_tpad": ref.event_frame(8, ref.TC_HID, ref.TID_KIP, 3, 0, bytes([1, 5, 250, 0])),
        "evt_nsq": ref.event_frame(0, ref.TC_HID, ref.TID_KIP, 1, 0, KBD_REPORT, sequenced=False),
        "evt_big": ref.event_frame(9, ref.TC_HID, ref.TID_KIP, 1, 0, bytes(range(200))),
        "evt_toobig": ref.event_frame(10, ref.TC_HID, ref.TID_KIP, 1, 0, bytes(300)),
        "evt_bad_payload_crc": bytes(bad_payload),
        "evt_bad_header_crc": bytes(bad_header),
        "rsp_desc": ref.response_frame(9, 39, ref.TC_HID, ref.TID_KIP, 1, 4, ref.descriptor_slice(1, 0, b"\x01\x02\x03", True)),
        "rsp_wrong_rqid": ref.response_frame(8, 41, ref.TC_HID, ref.TID_KIP, 1, 4, b"\x00"),
        "rsp_status0": ref.response_frame(11, 39, ref.TC_REG, ref.TID_KIP, 0, 1, b"\x00"),
        "rsp_status1": ref.response_frame(11, 39, ref.TC_REG, ref.TID_KIP, 0, 1, b"\x01"),
        "huge_len_then_event": SYN_HUGE + ref.event_frame(0, ref.TC_HID, ref.TID_KIP, 1, 0, KBD_REPORT, sequenced=False),
        "garbage": bytes([0x00, 0xAA, 0xAA, 0x13, 0x55, 0xFF]),
        "evparams": ref.event_params(ref.TC_HID, 1),
        "hiddesc": ref.hid_descriptor(0x3B),
        "hiddesc_bad_type": bytes([9, 0x22, 0, 1, 0, 1, 0x22, 0x3B, 0]),
        "hiddesc_two": bytes([9, 0x21, 0, 1, 0, 2, 0x22, 0x3B, 0]),
        "attrs": ref.attributes(0x045E, 0x09AF, 0x0100),
        "slice_ok": ref.descriptor_slice(1, 4, b"abcd", False),
        "slice_overrun": ref.descriptor_slice(1, 4, b"abcd", False)[:-2],
        "descreq": desc_req,
        "kbd_desc": ref.KEYBOARD_REPORT_DESC,
    }


def emit():
    items = cases()
    out = ["import libc.octets", "", "export { %s }" % ", ".join("g_" + n for n in items), ""]
    for name, data in items.items():
        out.append("fn g_%s(p: u64) -> u64 {" % name)
        for i, byte in enumerate(data):
            out.append("    octets.st8(p, %d, %d)" % (i, byte))
        out.append("    return %d" % len(data))
        out.append("}")
        out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    sys.stdout.write(emit())
