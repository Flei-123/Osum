from model import Rec

PRPH_WADDR, PRPH_RADDR, PRPH_WDAT, PRPH_RDAT = 0x444, 0x448, 0x44C, 0x450
MEM_RADDR, MEM_WADDR, MEM_WDAT, MEM_RDAT = 0x40C, 0x410, 0x418, 0x41C
PRPH_MASK = 0xFFFFF
MEM_MASK = 0x00FFFFFF

WINDOWS = {
    "prph": {"raddr": PRPH_RADDR, "waddr": PRPH_WADDR, "rdat": PRPH_RDAT, "wdat": PRPH_WDAT, "mask": PRPH_MASK, "step": 0},
    "sram": {"raddr": MEM_RADDR, "waddr": MEM_WADDR, "rdat": MEM_RDAT, "wdat": MEM_WDAT, "mask": MEM_MASK, "step": 4},
}


def strip_bar(recs, bar):
    if not bar:
        return recs
    for r in recs:
        if r.space == "csr" and r.off >= bar:
            r.off -= bar
    return recs


def fold_windows(recs):
    cursor = {"prph": {"r": None, "w": None}, "sram": {"r": None, "w": None}}
    out = []
    for r in recs:
        if r.space != "csr" or r.kind not in ("r32", "w32"):
            out.append(r)
            continue
        hit = None
        for space, win in WINDOWS.items():
            if r.kind == "w32" and r.off == win["raddr"]:
                cursor[space]["r"] = r.val & win["mask"]
                hit = "eat"
            elif r.kind == "w32" and r.off == win["waddr"]:
                cursor[space]["w"] = r.val & win["mask"]
                hit = "eat"
            elif r.kind == "r32" and r.off == win["rdat"] and cursor[space]["r"] is not None:
                out.append(Rec(r.seq, r.t_us, space + "_r", space, cursor[space]["r"], r.val, {}, r.line))
                cursor[space]["r"] += win["step"]
                hit = "emit"
            elif r.kind == "w32" and r.off == win["wdat"] and cursor[space]["w"] is not None:
                out.append(Rec(r.seq, r.t_us, space + "_w", space, cursor[space]["w"], r.val, {}, r.line))
                cursor[space]["w"] += win["step"]
                hit = "emit"
            if hit:
                break
        if hit is None:
            out.append(r)
    return out
