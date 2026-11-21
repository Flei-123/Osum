#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
cleanup() { git worktree remove --force "$TMPD/mut" > /dev/null 2>&1; git worktree remove --force "$TMPD/nol" > /dev/null 2>&1; git worktree remove --force "$TMPD/noi" > /dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

make_bundle() { # make_bundle <dir> <name> <info> <keys> <start>
    local d="$TMPD/apps/$1.osp"
    cp -a assets/apps/trashbin.osp "$d"
    sed -i -e "s|^name=.*|name=$2|" -e "s|^info=.*|info=$3|" -e "s|^keys=.*|keys=$4|" -e "s|^id=.*|id=com.test.$1|" "$d/INFO"
    printf '%s\n' "$5" > "$d/start.txt"
}

mkdir -p "$TMPD/apps" "$TMPD/files"
printf '#apps\t2\t2\nA\tcom.fleitec.certus\tCertus\tCertus\tinternet\tFleitec\tGPL\tKurz\tShort\tD\tD\t\t\t\nV\tcom.fleitec.certus\tsystem\tosum-any\t1.0.0\t0\t\t\t\t1\t1\t1\tuntested\nA\tcom.test.zebranotes\tZebra Notizen\tZebra Notes\ttools\tTest\tMIT\tKurz\tShort\tD\tD\t\t\t\nV\tcom.test.zebranotes\tsystem\tosum-any\t1.0.0\t0\t\t\t\t1\t1\t1\tpartial\nA\tcom.test.quokkaview\tQuokka Viewer\tQuokka Viewer\ttools\tTest\tMIT\tKurz\tShort\tD\tD\t\t\t\nV\tcom.test.quokkaview\tsystem\tosum-any\t1.0.0\t0\t\t\t\t1\t1\t1\tworks\n' > "$TMPD/catalog.tsv"
for keep in explorer settings taskmgr; do cp -a assets/apps/$keep.osp "$TMPD/apps/"; done
for n in $(seq -w 1 30); do make_bundle "a-gorp$n" "Gorp $n" "Filler" "gorpfill" /bin/edit; done
cp -a assets/apps/certus.osp "$TMPD/apps/"
printf '/bin/echo\n' > "$TMPD/apps/certus.osp/start.txt"
make_bundle aa-reader "Aa Reader" "Reads certus files" "reader" /bin/edit
make_bundle ab-certus "Abcertus" "Tool" "tool" /bin/edit
make_bundle ac-certus-pad "Ac Certus Pad" "Pad" "pad" /bin/edit
make_bundle notes-one "Notes One" "Notes" "notes" /bin/edit
make_bundle notes-two "Notes Two" "Notes" "notes" /bin/edit
make_bundle xremote "Remote control" "Let another device see and control this computer" "remote,fernwartung,freeviewer,host,x-remote,fernsteuerung,fernzugriff" /bin/edit
make_bundle firefox "Firefox" "Web browser" "firefox,browser,web,internet,www,mozilla,surf" /bin/edit
make_bundle terminal "Terminal" "A command prompt with a shell" "terminal,konsole,shell,sh,eingabe,befehl,kommando,prompt" /bin/edit
make_bundle teamlist "Teamlist" "Lists teams" "team" /bin/edit
make_bundle qk-side "Sidecar" "Works with quokka viewer" "sidecar" /bin/edit
printf 'use=notes-two:3\n' > "$TMPD/startuse.conf"
LONG=a-very-long-file-name-for-the-index-test.txt
for f in certus-notes.txt zzqq-file.txt spinatus.txt tattoo.txt x-remote-notes.txt $LONG; do printf 'x\n' > "$TMPD/files/$f"; done
MKFS_EXTRA="/data/ /var/ /var/store/ /var/store/apps=$TMPD/catalog.tsv@0644"
for f in certus-notes.txt zzqq-file.txt spinatus.txt tattoo.txt x-remote-notes.txt $LONG; do MKFS_EXTRA="$MKFS_EXTRA /data/$f=$TMPD/files/$f@0644"; done

echo "== mutant tree: the old ranking =="
git worktree add --detach "$TMPD/mut" HEAD > /dev/null 2>&1 || { bad "mutant worktree"; echo "SEARCHRANKUI: $pass passed, $fail failed"; exit 1; }
python3 -I - "$TMPD/mut" <<'PY'
import sys
root = sys.argv[1]
p = root + "/kernel/user/startrank.fi"
s = open(p).read()
s = s.replace("fn rank_apps(", "fn rank_apps_ranked(").replace("fn rank_files(", "fn rank_files_ranked(")
s += "\nfn rank_apps(term: u64, out: u64, max: u64) -> u64 {\n    return appdir.search(term, out, max)\n}\n\nfn rank_files(term: u64, out: u64, max: u64) -> u64 {\n    return nidx.find(term, out, max)\n}\n"
open(p, "w").write(s)
q = root + "/kernel/user/launcher.fi"
b = open(q, "rb").read()
old = b"if !g_home && napp + nset > 0 {"
assert b.count(old) == 1
open(q, "wb").write(b.replace(old, b"if !g_home {"))
PY

git worktree add --detach "$TMPD/nol" HEAD > /dev/null 2>&1 || bad "nolearn worktree"
python3 -I - "$TMPD/nol" <<'PY'
import re, sys
p = sys.argv[1] + "/kernel/user/startlearn.fi"
s = open(p).read()
def stub(name, sig, body):
    global s
    m = re.search(r"fn %s\(.*?\n}\n" % name, s, re.S)
    assert m, name
    s = s[:m.start()] + "fn %s%s {\n    %s\n}\n" % (name, sig, body) + s[m.end():]
stub("record", "(query: u64, token: u64)", "let _ignored: u64 = query + token")
stub("bonus", "(token: u64) -> u64", "return token * 0")
stub("pinned", "(query: u64, token: u64) -> bool", "return query + token == 1 && false")
stub("suggest", "(out: u64, max: u64) -> u64", "return out * 0 + max * 0")
open(p, "w").write(s)
q = sys.argv[1] + "/kernel/user/launcher.fi"
b = open(q, "rb").read()
old = b"g_store_best = napp > 0 &&"
assert b.count(old) == 1
open(q, "wb").write(b.replace(old, b"g_store_best = false && napp > 0 &&"))
PY

git worktree add --detach "$TMPD/noi" HEAD > /dev/null 2>&1 || bad "noindex worktree"
python3 -I - "$TMPD/noi" <<'PY'
import sys
p = sys.argv[1] + "/kernel/user/startsettings.fi"
s = open(p).read()
for name in ("fn add_deep_entries(term: u64, out: u64, max: u64) {\n", "fn typo_pages(term: u64, out: u64, max: u64) {\n"):
    assert s.count(name) == 1, name
    s = s.replace(name, name + "    if term != 0 {\n        return\n    }\n")
open(p, "w").write(s)
PY

run_tree() { # run_tree <tree> <name>
    ( cd "$1" && APPS_DIR="$TMPD/apps" EH_ETC_EXTRA="/etc/startuse.conf=$TMPD/startuse.conf@0644" EH_MKFS_EXTRA="$MKFS_EXTRA" \
        DESIGNBUILD="$TMPD/build-$2" bash tools/design/eh6.sh "$TMPD/$2" res=1920x1080 accel=kvm tafel=nein \
        drehbuch="$ROOT/tools/searchrank/script.txt" > "$TMPD/$2.log" 2>&1 )
}
echo "== two runs in parallel: ranked and old =="
run_tree "$ROOT" new &
P1=$!
run_tree "$TMPD/mut" old &
P2=$!
run_tree "$TMPD/nol" nol &
P3=$!
run_tree "$TMPD/noi" noi &
P4=$!
wait $P1 $P2 $P3 $P4

if [ -n "${SEARCHRANKUI_SHOTS:-}" ]; then mkdir -p "$SEARCHRANKUI_SHOTS"; cp "$TMPD"/new/1*.ppm "$TMPD"/new/2*.ppm "$SEARCHRANKUI_SHOTS/" 2>/dev/null; cp "$TMPD/new/serial.txt" "$SEARCHRANKUI_SHOTS/serial.txt" 2>/dev/null; fi
val() { sed -n "s/^$2=//p" "$1" | head -1; }
for n in new old nol noi; do
    S="$TMPD/$n/serial.txt"
    [ -s "$S" ] || { bad "$n: no serial output: $(tail -3 "$TMPD/$n.log" | tr '\n' ' ')"; continue; }
    python3 -I tools/searchrank/check.py "$S" certus > "$TMPD/$n.certus" 2>&1
    python3 -I tools/searchrank/check.py "$S" zzqq > "$TMPD/$n.zzqq" 2>&1
    python3 -I tools/searchrank/check.py "$S" notes > "$TMPD/$n.notes" 2>&1
    for q in autostart autostrat netzwerk account wlan "data folder" freeviewer quokka xremote x-remote "X Remote" fernst firfox fire term einst te bluetooth long-file; do
        python3 -I tools/searchrank/check.py "$S" "$q" > "$TMPD/$n.q_${q// /_}" 2>&1
    done
done

D="$TMPD/new"
[ "$(val $D.certus first_app)" = "Certus" ] && ok "certus: the first row is the app Certus" \
    || bad "certus: first row is '$(val $D.certus first_app)'"
[ "$(val $D.certus apps)" = "Certus|Ac Certus Pad|Abcertus|Aa Reader" ] \
    && ok "certus: exact, word start, substring, description" \
    || bad "certus: app order is '$(val $D.certus apps)'"
[ -n "$(val $D.certus files)" ] && grep -q 'apps=4' "$D.certus" \
    && ok "certus: the file hit comes after all four apps" \
    || bad "certus: file hit missing or apps wrong: $(val $D.certus head)"
grep -q 'apps=0 .*dateien=1' "$D.zzqq" && ok "no app named zzqq: only the file is listed" \
    || bad "zzqq: unexpected hits: $(val $D.zzqq head)"
grep -aq 'launcher: oeffne datei' "$D/serial.txt" && bad "Enter opened a file without any app hit" \
    || ok "Enter with no app hit opens nothing"
[ "$(val $D.notes first_app)" = "Notes Two" ] && ok "notes: the used app comes first at equal rank" \
    || bad "notes: first row is '$(val $D.notes first_app)'"
grep -aq 'launcher: use \[notes-two\] n=4' "$D/serial.txt" && ok "starting Notes Two counts the use (3 -> 4)" \
    || bad "no use count line for notes-two"
for f in 00-menu 01-certus; do [ -s "$D/$f.ppm" ] || bad "missing picture $f"; done
if [ -s "$D/00-menu.ppm" ] && [ -s "$D/01-certus.ppm" ]; then
    n=$(python3 -I tools/menualive/check.py diff "$D/00-menu.ppm" "$D/01-certus.ppm" 8 580 450 1035 | sed 's/changed=//')
    [ "${n:-0}" -gt 500 ] && ok "typing changed the menu ($n pixels)" || bad "typing changed ${n:-0} pixels"
fi

echo "== typo, separators, synonyms: the best hit is the app with its row and card =="
expect_best() { # expect_best <query-file-suffix> <query label> <expected app>
    local got; got=$(val "$D.q_$1" best)
    [ "$got" = "$3" ] && ok "'$2': best match is $3" || bad "'$2': best match is '$got' (want $3)"
    [ "$(val "$D.q_$1" first_app)" = "$3" ] && ok "'$2': first app row is $3" || bad "'$2': first app row is '$(val "$D.q_$1" first_app)'"
    grep -q '\.osp' <<< "$(val "$D.q_$1" files)" && bad "'$2': a .osp bundle is listed as file" || ok "'$2': no .osp bundle listed as file"
}
expect_best xremote xremote "Remote control"
expect_best x-remote x-remote "Remote control"
expect_best X_Remote "X Remote" "Remote control"
expect_best fernst fernst "Remote control"
expect_best firfox firfox "Firefox"
expect_best fire fire "Firefox"
expect_best term term "Terminal"
expect_best einst einst "Settings"
grep -aq 'launcher: rect id=7 ' "$D/serial.txt" && ok "the best match card is reported as a rectangle" || bad "no best match card rectangle"
h=$(grep -a 'launcher: rect id=7 ' "$D/serial.txt" | tail -1 | sed -n 's/.* h=\([0-9]*\).*/\1/p')
[ "${h:-0}" -ge 48 ] && ok "the best match card is large (h=$h)" || bad "the best match card is small (h=${h:-0})"
for id in 8 9; do
    grep -aq "launcher: rect id=$id " "$D/serial.txt" && ok "best match button id=$id is reported as a rectangle" || bad "no rectangle for best match button id=$id"
done
rect_field() { grep -a "launcher: rect id=$1 " "$D/serial.txt" | tail -1 | sed -n "s/.* $2=\\([0-9]*\\).*/\\1/p"; }
list_x=$(rect_field 2 x); list_w=$(rect_field 2 w)
list_right=$(( ${list_x:-0} + ${list_w:-0} ))
[ "$(rect_field 8 x | sed "s/^$/0/")" -ge "$list_right" ] && ok "detail card buttons stand right of the result list (x=$(rect_field 8 x) >= $list_right)" || bad "detail card buttons overlap the result list"
[ "$(rect_field 8 y | sed "s/^$/0/")" -gt "$(rect_field 7 y | sed "s/^$/99999/")" ] && ok "detail card buttons stand below the top of the best match" || bad "detail card buttons above the best match"
[ "$(val $D.certus stores)" = "" ] && ok "certus is installed: no store hit for it" || bad "certus: store hits '$(val $D.certus stores)'"
[ "$(val $D.q_quokka best)" = "Quokka Viewer" ] && ok "'quokka': the store hit with a name match beats an installed app that only mentions it" || bad "'quokka': best is '$(val $D.q_quokka best)'"
[ "$(val $D.q_quokka apps)" = "Sidecar" ] && ok "'quokka': the installed app is still listed" || bad "'quokka': apps are '$(val $D.q_quokka apps)'"
[ "$(val $TMPD/nol.q_quokka best)" = "Sidecar" ] && ok "store-best off: the installed app stays best" || bad "store-best off: best is '$(val $TMPD/nol.q_quokka best)' -- the test is blind"
grep -aq 'launcher: use \[xremote\]' "$D/serial.txt" && ok "Enter on 'xremote' starts the app" || bad "Enter on 'xremote' started nothing"
python3 -I tools/searchrank/check.py "$D/serial.txt" zebra > "$D.q_zebra" 2>&1
[ "$(val $D.q_zebra stores)" = "zebranotes" ] && ok "'zebra': the catalog app is listed as a store hit" || bad "'zebra': store hits are '$(val $D.q_zebra stores)'"
grep -q 'apps=0 ' "$D.q_zebra" && ok "'zebra': no installed app hit" || bad "'zebra': unexpected installed hit"
grep -aq 'launcher: store open \[zebranotes\] pid=' "$D/serial.txt" && ok "Enter on a store hit opens the Store page for it" || bad "Enter on the store hit did nothing"
zebra_from=$(grep -an 'launcher: suche \[zebra\]' "$D/serial.txt" | tail -1 | cut -d: -f1)
tail -n +"${zebra_from:-1}" "$D/serial.txt" > "$D/zebra_tail.txt"
for id in 7 8 9; do
    grep -aq "launcher: rect id=$id " "$D/zebra_tail.txt" && ok "'zebra': detail card element id=$id is reported" || bad "'zebra': no detail card element id=$id"
done
maxus=$(grep -a '^launcher: suche \[' "$D/serial.txt" | sed -n 's/.* us=\([0-9]*\).*/\1/p' | sort -n | tail -1)
[ "${maxus:-999999}" -le 16000 ] && ok "slowest search took ${maxus} us (<= 16 ms)" || bad "slowest search took ${maxus:-?} us"
echo "SEARCH_MAX_US=${maxus:-0}"

echo "== learning: after picks, the prefix goes to the learned app =="
[ "$(val $D.q_te best)" = "Terminal" ] && ok "'te': best match is Terminal after 2 picks (Teamlist has more uses)" \
    || bad "'te': best match is '$(val $D.q_te best)'"
[ "$(grep -a 'launcher: rec k=0 ' "$D/serial.txt" | tail -1 | sed -n 's/.*name=\[\(.*\)\].*/\1/p')" = "Teamlist" ] \
    && ok "empty field suggests the most used app first" || bad "empty field suggestion k=0 is '$(grep -a 'launcher: rec k=0 ' "$D/serial.txt" | tail -1)'"

echo "== settings results and long names =="
case "$(val $D.q_bluetooth settings)" in *Bluetooth*) ok "'bluetooth': a Settings page is listed" ;; *) bad "'bluetooth': settings are '$(val $D.q_bluetooth settings)'" ;; esac
grep -q 'apps=0 ' "$D.q_bluetooth" && ok "'bluetooth': no app hit, Enter goes to the Settings page" || bad "'bluetooth': unexpected apps: $(val $D.q_bluetooth apps)"
grep -aq 'launcher: settings page=[0-9]* pid=' "$D/serial.txt" && ok "Enter on a Settings hit starts Settings on that page" || bad "no 'launcher: settings page=' line"
[ "$(val $D.q_long-file files)" = "/data/a-very-long-file-name-fo" ] && ok "a name longer than the slot is cut and terminated" \
    || bad "long name listed as '$(val $D.q_long-file files)'"
grep -aq 'launcher: .*[Pp]anic\|#PF\|program died' "$D/serial.txt" && bad "launcher died during the run" || ok "launcher survived all queries"

echo "== deep links: settings pages, typo, task manager pages =="
case "$(val $D.q_autostart settings)" in *Autostart*) ok "'autostart': the Settings page Autostart is listed" ;; *) bad "'autostart': settings are '$(val $D.q_autostart settings)'" ;; esac
case "$(val $D.q_autostart settings)" in *"Startup apps"*) ok "'autostart': the Task Manager page is listed from the deep link index" ;; *) bad "'autostart': no Task Manager deep link in '$(val $D.q_autostart settings)'" ;; esac
case "$(val $D.q_autostart paths)" in *"> Apps"*) ok "'autostart': the card path reads '$(val $D.q_autostart paths | cut -d'|' -f1)'" ;; *) bad "'autostart': paths are '$(val $D.q_autostart paths)'" ;; esac
case "$(val $D.q_autostart paths)" in *"Task Manager"*) ok "'autostart': the Task Manager link shows its own path" ;; *) bad "'autostart': Task Manager path missing in '$(val $D.q_autostart paths)'" ;; esac
case "$(val $D.q_autostrat settings)" in *Autostart*) ok "'autostrat' (typo): the Settings page is still found" ;; *) bad "'autostrat': settings are '$(val $D.q_autostrat settings)'" ;; esac
case "$(val $D.q_data_folder settings)" in *"Data folder"*) ok "'data folder': the Explorer deep link is listed" ;; *) bad "'data folder': settings are '$(val $D.q_data_folder settings)'" ;; esac
case "$(val $D.q_data_folder paths)" in *Files*) ok "'data folder': its card path is Files" ;; *) bad "'data folder': paths are '$(val $D.q_data_folder paths)'" ;; esac
case "$(val $D.q_freeviewer settings)" in *"in the Store"*) ok "'freeviewer': the Store deep link is listed" ;; *) bad "'freeviewer': settings are '$(val $D.q_freeviewer settings)'" ;; esac
for q in netzwerk account wlan; do
    [ -n "$(val $D.q_$q settings)" ] && ok "'$q': a Settings page is listed ($(val $D.q_$q settings | cut -c1-40))" || bad "'$q': no Settings page"
done
grep -aq 'launcher: settings page=[0-9]* pid=' "$D/serial.txt" && ok "Enter on 'autostart' starts Settings" || bad "no Settings start line"
grep -aq 'settings: autostart page entries=' "$D/serial.txt" && ok "Settings opened the Autostart page (page 37) from the search hit" || bad "Settings never built the Autostart page"
N2="$TMPD/noi"
case "$(val $N2.q_autostart settings)" in *"Startup apps"*) bad "no-index tree still lists the Task Manager page -- the test is blind" ;; *) ok "no-index tree: the Task Manager deep link is gone" ;; esac
case "$(val $N2.q_autostrat settings)" in *Autostart*) bad "no-index tree still finds the typo -- the test is blind" ;; *) ok "no-index tree: the typo 'autostrat' finds nothing" ;; esac

echo "== counter-proof: old ranking =="
O="$TMPD/old"
[ "$(val $O.certus first_app)" != "Certus" ] && ok "old ranking: first row is '$(val $O.certus first_app)' not Certus" \
    || bad "old ranking still put Certus first -- the test is blind"
grep -aq 'launcher: oeffne datei' "$O/serial.txt" && ok "old behaviour: Enter opened a file" \
    || bad "old behaviour did not open a file -- the test is blind"

for q in xremote X_Remote firfox; do
    [ "$(val $O.q_$q first_app)" != "$(val $D.q_$q first_app)" ] \
        && ok "old ranking: '$q' gives '$(val $O.q_$q first_app)'" || bad "old ranking answered '$q' as well -- the test is blind"
done
grep -q '\.osp' <<< "$(val $O.q_xremote files)" && ok "old ranking: .osp bundle listed as file" || bad "old ranking listed no .osp file -- the test is blind"
N="$TMPD/nol"
[ "$(val $N.q_te best)" = "Teamlist" ] && ok "learning off: 'te' stays on Teamlist" || bad "learning off: 'te' best is '$(val $N.q_te best)' -- the test is blind"
[ "$(grep -a 'launcher: rec k=0 ' "$N/serial.txt" | tail -1 | sed -n 's/.*name=\[\(.*\)\].*/\1/p')" = "Terminal" ] \
    && ok "learning off: suggestion follows the plain recent list" || bad "learning off: suggestion is unchanged -- the test is blind"

echo
echo "SEARCHRANKUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
