#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$ROOT/lib"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

printf 'import monitors.hdmipin\nfn main() -> i32 {\n    hdmipin.plan_clear()\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "hdmipin compiles with --profile=kernel" \
    || { bad "hdmipin does not compile with --profile=kernel"; head -5 "$T/k.err"; }
"$FIRNC" tools/hdmi/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds against lib/monitors" \
    || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 25 ] && ok "oracle: $nok promises OK (>= 25)" || bad "oracle: only $nok OK (< 25)"
    pass=$((pass+nok))
fi

printf 'import monitors.hdmistream\nfn main() -> i32 {\n    hdmistream.plan_stop()\n    return 0\n}\n' > "$T/ks.fi"
"$FIRNC" --profile=kernel -c "$T/ks.fi" -o "$T/ks.o" 2> "$T/ks.err" \
    && ok "hdmistream compiles with --profile=kernel" \
    || { bad "hdmistream does not compile with --profile=kernel"; head -5 "$T/ks.err"; }
if "$FIRNC" tools/hdmi/streamoracle.fi -o "$T/streamoracle" 2> "$T/so.err"; then
    "$T/streamoracle" > "$T/sout.txt" 2>&1
    sok=$(grep -c '^OK' "$T/sout.txt")
    sbad=$(grep -c '^FAIL' "$T/sout.txt")
    sed -n 's/^FAIL /  FAIL  stream oracle: /p' "$T/sout.txt"
    [ "$sbad" = 0 ] && [ "$sok" -ge 15 ] && ok "stream oracle: $sok promises OK, no FAIL" || bad "stream oracle: ok=$sok fail=$sbad"
else
    bad "stream oracle does not build"; head -10 "$T/so.err"
fi

mutate() {
    local name=$1 expr=$2 file=$3
    local L="$T/lib-$name"
    mkdir -p "$L"
    for d in lib/*; do
        [ "$(basename "$d")" = monitors ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    mkdir -p "$L/monitors"
    cp lib/monitors/*.fi "$L/monitors/"
    sed -e "$expr" lib/monitors/$file > "$L/monitors/$file"
    if cmp -s lib/monitors/$file "$L/monitors/$file"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/hdmi/oracle.fi -o "$T/o-$name" 2>/dev/null; then
        bad "control $name: mutated oracle does not build"
        return
    fi
    local nf
    nf=$("$T/o-$name" 2>&1 | grep -c '^FAIL')
    [ "$nf" -gt 0 ] && ok "control $name: oracle goes red ($nf FAIL)" \
                     || bad "control $name: oracle stays green on a broken lib"
}
mutate nopinctl  's/add(V_SET_PINCTL, PINCTL_OUT)/add(V_SET_PINCTL, 0)/' hdmipin.fi
mutate nounsol   's/add(V_SET_UNSOL, UNSOL_ENABLE | (tag \& 0x3F))/add(V_SET_UNSOL, tag \& 0x3F)/' hdmipin.fi
mutate noeapd    's/if (pincap \& PINCAP_EAPD) != 0 {/if false {/' hdmipin.fi
mutate nopower   's/if (wcap \& WCAP_POWER) != 0 {/if false {/' hdmipin.fi
mutate noconnsel 's/if conn_idx != NO_CONN {/if false {/' hdmipin.fi
mutate nowrap    's/var want: u64 = ordinal % count/var want: u64 = ordinal/' hdmipin.fi
mutate tagshift  's/return (resp >> 26) \& 0x3F/return (resp >> 24) \& 0x3F/' hdmipin.fi
mutate eldflag   's/return (resp \& 2) != 0/return (resp \& 1) != 0/' hdmipin.fi
mutate nopresence 's/return (sense \& layout.PS_PRESENCE) != 0/return true/' hdmipin.fi
mutate hdcp      's/return (octets.ld8(e, 5) \& 1) != 0/return (octets.ld8(e, 5) \& 2) != 0/' eld.fi
mutate delay     's/return octets.ld8(e, 6) \* 2/return octets.ld8(e, 6)/' eld.fi
mutate mfg       's/return octets.ld8(e, 16) | (octets.ld8(e, 17) << 8)/return octets.ld8(e, 17) | (octets.ld8(e, 16) << 8)/' eld.fi

grep -q 'hdmipin.plan_pin' kernel/drv/snd/hdmi.fi \
    && ok "the driver builds its verbs from the model" \
    || bad "hdmi.fi no longer uses hdmipin.plan_pin"
grep -q 'unsol_take' kernel/drv/snd/hdmi.fi \
    && ok "the driver consumes unsolicited responses" \
    || bad "hdmi.fi does not consume unsolicited responses"


bash tools/build-kernel.sh "$T/k.mb" > "$T/build.txt" 2>&1 \
    && ok "the kernel builds with the HDMI driver" \
    || { bad "the kernel does not build"; tail -8 "$T/build.txt"; }

boot() {
    local n=$1 cmd=$2 dev=$3
    timeout 120 $QEMU_X86 -kernel "$T/k.mb" -m 512 -append "$cmd" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -audiodev none,id=snd0 $dev > /dev/null 2>&1
}
ONE="-device intel-hda -device hda-duplex,audiodev=snd0"
TWO="$ONE -device intel-hda -device hda-output,audiodev=snd0"
if [ -s "$T/k.mb" ]; then
    boot plain "osum nokbd nosched noproc nofs audio audsay" "$ONE"
    grep -qaF "hdmi: scan controllers=1 pins=0" "$T/plain.txt" \
        && ok "one codec without digital pins: scan finds 1 controller, 0 pins" \
        || bad "plain boot: scan line missing or wrong"
    grep -qaF "hda: ready" "$T/plain.txt" \
        && ok "analog audio still comes up" || bad "analog audio no longer ready"
    grep -qaF "hdmi: pin=" "$T/plain.txt" \
        && bad "plain boot invents an HDMI pin" || ok "no invented HDMI pin without digital hardware"
    boot two "osum nokbd nosched noproc nofs audio audsay" "$TWO"
    grep -qaF "hdmi: scan controllers=2 pins=0" "$T/two.txt" \
        && ok "two controllers: the second one is scanned through the immediate path" \
        || bad "two controllers: scan line missing or wrong"
    grep -qaF "hda: ready" "$T/two.txt" \
        && ok "two controllers: the first still serves analog audio" || bad "two controllers: audio not ready"
    boot synth "osum nokbd nosched noproc nofs audio audgraph audsay" "$ONE"
    grep -qaF "hdmi: scan controllers=2 pins=1" "$T/synth.txt" \
        && ok "audgraph without real pins injects exactly one synthetic pin" \
        || bad "synthetic pin missing"
    grep -qaE "hdmi: pin=0 ctl=1 cad=0 nid=5 .* eld=36 mon=ABC dp=0 sad=2 rate=64" "$T/synth.txt" \
        && ok "pin line carries ELD length, monitor name, SAD count and best rate" \
        || bad "synthetic pin line wrong: $(grep -a 'hdmi: pin=' "$T/synth.txt" | head -1)"
    grep -qaF "pstate=0x0 pinctl=0x40 unsol=0x85 conv=3" "$T/synth.txt" \
        && ok "pin line shows the activation read-back" || bad "activation read-back missing"

    as --64 -o "$T/crt.o" kernel/user/crt.s 2>/dev/null
    SPEC="/bin/ /proc/"
    progs_ok=1
    for p in sh cat; do
        "$FIRNC" -o "$T/$p.o" "kernel/user/$p.fi" > "$T/$p.log" 2>&1 \
            && ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start -o "$T/$p.elf" "$T/crt.o" "$T/$p.o" 2>/dev/null \
            && SPEC="$SPEC /bin/$p=$T/$p.elf" || progs_ok=0
    done
    if [ "$progs_ok" = 1 ] && bash tools/mkfsfi/mkfs.sh build "$T/disk.img" 8192 $SPEC > "$T/mkfs.txt" 2>&1; then
        timeout 120 $QEMU_X86 -kernel "$T/k.mb" -m 512 \
            -append "osum nokbd nosched noring3 vfs audio audgraph script=/bin/cat /proc/hdmi;exit" \
            -serial "file:$T/proc.txt" -display none -no-reboot -audiodev none,id=snd0 $ONE \
            -drive "file=$T/disk.img,format=raw,if=ide,index=0" \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
        grep -qaF "hdmi v1 controllers=2 pins=1" "$T/proc.txt" \
            && ok "/proc/hdmi lists controllers and pins" || bad "/proc/hdmi header missing"
        grep -qaE "^pin 0 ctl=1 cad=0 nid=5 pincap=0x01000094 wcap=0x[0-9a-f]+ sense=0xc0000000 state=2" "$T/proc.txt" \
            && ok "/proc/hdmi pin line shows full-width pincap and sense" || bad "/proc/hdmi pin line wrong"
        grep -qaE "^eld 0 len=36 valid=1 mon=ABC dp=0 hdcp=1" "$T/proc.txt" \
            && ok "/proc/hdmi parses the ELD" || bad "/proc/hdmi eld line wrong"
        grep -qaE "^eldhex 0 1000080003230501" "$T/proc.txt" \
            && ok "/proc/hdmi dumps the raw ELD bytes" || bad "/proc/hdmi eldhex missing"
        grep -qaE "^sad 0 1 fmt=1 ch=8 rates=0x0*54([^0-9a-f]|$)" "$T/proc.txt" \
            && ok "/proc/hdmi lists the SADs" || bad "/proc/hdmi sad line missing"
    else
        bad "could not build the disk for the /proc/hdmi check"
    fi
fi

echo "hdmi: $pass promises, $fail errors"
[ "$fail" = 0 ]
