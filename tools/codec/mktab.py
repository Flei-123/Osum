#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import json, os, sys

HIER = os.path.dirname(os.path.abspath(__file__))
def load_2(n):
    with open(os.path.join(HIER, n)) as f:
        return json.load(f)

T  = load_2('tabs.json')
DB = load_2('dbtab.json')
P4 = load_2('pred4.json')

aus = []
def z(s=''): aus.append(s)

def field(name, values, typ='u64', je=16, kommentar=None):
    z('// %s' % kommentar if kommentar else '')
    z('static mut %s: [%s; %d] = [' % (name, typ, len(values)))
    line_2 = '   '
    for i, v in enumerate(values):
        chunk = ' %d,' % v if i < len(values)-1 else ' %d]' % v
        if len(line_2) + len(chunk) > 76:
            z(line_2); line_2 = '   '
        line_2 += chunk
    z(line_2)
    z()

z('// SPDX-License-Identifier: GPL-2.0-only')
z('// kernel/user/codec/h264tab.fi -- DIE ZAHLENTAFELN DES H.264-DEKODIERERS.')
z('//')
z('// ERZEUGT von tools/codec/mktab.py. NICHT VON HAND AENDERN --')
z('// jede Aenderung hier geht beim naechsten Lauf verloren, und die')
z('// Zahlen stammen ohnehin nicht von hier:')
z('//')
z('//   die CAVLC-Tafeln aus FFmpegs libavcodec/h264_cavlc.c,')
z('//   die Entblockungstafeln aus libavcodec/h264_loopfilter.c,')
z('//   die Gewichte der Intra-4x4-Modi aus den Formeln 8.3.1.2.1-9')
z('//   der Norm ITU-T H.264 (ueber tools/codec/pred_gen.py).')
z('//')
z('// Eine abgetippte Huffman-Tafel hat einen Fehler, den niemand')
z('// SIEHT: er faellt drei Koeffizienten spaeter als "Code nicht in')
z('// der Tafel" auf, und dort sucht man ihn dann. Erzeugte Tafeln')
z('// koennen ihn nicht haben. tools/codec/run.sh rechnet zusaetzlich')
z('// nach, dass jede Tafel praefixfrei ist.')
z()
z('profile kernel')
z()
z('export {')
z('    CT_LEN, CT_BITS, CDC_LEN, CDC_BITS,')
z('    TZ_LEN, TZ_BITS, TZC_LEN, TZC_BITS, RUN_LEN, RUN_BITS,')
z('    ALPHA, BETA, TC0, PRED4W, PRED4G, PRED4I, ZIGZAG,')
z('    VMAT, QPC, LEVTAB_V, LEVTAB_N')
z('}')
z()

ct_len=[]; ct_bits=[]
for k in range(4):
    ct_len += T['coeff_token_len'][k]
    ct_bits += T['coeff_token_bits'][k]
field('CT_LEN', ct_len, kommentar=
     'coeff_token, Tafel 9-5: vier nC-Klassen (0-1, 2-3, 4-7, >=8) zu je\n'
     '// 68 Eintraegen, Index (klasse*17 + totalCoeff)*4 + trailingOnes.\n'
     '// Laenge 0 heisst: diese Verbindung gibt es nicht.')
field('CT_BITS', ct_bits)
field('CDC_LEN', T['chroma_dc_coeff_token_len'], kommentar=
     'coeff_token fuer den Chroma-DC-Block (4:2:0, maxCoeff 4).')
field('CDC_BITS', T['chroma_dc_coeff_token_bits'])

tz_len=[]; tz_bits=[]
for i in range(15):
    r=T['total_zeros_len'][i]; b=T['total_zeros_bits'][i]
    tz_len += r+[0]*(16-len(r)); tz_bits += b+[0]*(16-len(b))
field('TZ_LEN', tz_len, kommentar=
     'total_zeros, Tafel 9-7/9-8: 15 Zeilen (tzVlcIndex 1..15) zu 16,\n'
     '// mit Nullen aufgefuellt. Index (tzVlcIndex-1)*16 + total_zeros.')
field('TZ_BITS', tz_bits)
tzc_len=[]; tzc_bits=[]
for i in range(3):
    r=DB and T['chroma_dc_total_zeros_len'][i]; b=T['chroma_dc_total_zeros_bits'][i]
    tzc_len += r+[0]*(4-len(r)); tzc_bits += b+[0]*(4-len(b))
field('TZC_LEN', tzc_len, kommentar='total_zeros fuer den Chroma-DC-Block, Tafel 9-9(a).')
field('TZC_BITS', tzc_bits)

run_len=[]; run_bits=[]
for i in range(7):
    r=T['run_len'][i]; b=T['run_bits'][i]
    run_len += r+[0]*(16-len(r)); run_bits += b+[0]*(16-len(b))
field('RUN_LEN', run_len, kommentar=
     'run_before, Tafel 9-10: 7 Zeilen (zerosLeft 1..6 und >6) zu 16.')
field('RUN_BITS', run_bits)

field('ALPHA', DB['alpha'], kommentar=
     'alpha, Tafel 8-16. 52*3 lang: der Index ist qp+Versatz+52, damit\n'
     '// ein negativer Versatz nicht unter null greift.')
field('BETA', DB['beta'], kommentar='beta, Tafel 8-16, ebenso verschoben.')
tc0=[]
for row in DB['tc0']: tc0 += row
field('TC0', tc0, kommentar=
     'tc0, Tafel 8-17: je Index vier Werte (bS 0..3), Index ia*4+bS.')

w=[0]*(9*16); g=[0]*(9*16*4); idx=[0]*(9*16*4)
for ms, rows in P4.items():
    m=int(ms)
    for i,row in enumerate(rows):
        w[m*16+i]=row[0]
        for k,(gg,ii) in enumerate(row[1:]):
            g[(m*16+i)*4+k]=gg
            idx[(m*16+i)*4+k]=ii
field('PRED4W', w, kommentar=
     'Die acht gerichteten Intra-4x4-Modi als GEWICHTSTAFEL (Modus 2,\n'
     '// DC, rechnet der Code selbst). PRED4W[m*16+i] ist die Summe der\n'
     '// Gewichte des Punktes i im Modus m -- immer eine Zweierpotenz,\n'
     '// also der Rundungsteiler. Null heisst: diesen Modus gibt es hier\n'
     '// nicht (Modus 2).')
field('PRED4G', g, kommentar=
     'Bis zu vier Gewichte je Punkt, Index (m*16+i)*4+k.')
field('PRED4I', idx, kommentar=
     'Der Nachbar zum Gewicht: 0..3 = links oben->unten, 4 = Ecke,\n'
     '// 5..8 = oben, 9..12 = rechts oben.')

field('ZIGZAG', [0,1,4,8,5,2,3,6,9,12,13,10,7,11,14,15], kommentar=
     'Der Zickzack eines 4x4-Blocks, Tafel 8-13.')
vm=[]
for row in [[10,16,13],[11,18,14],[13,20,16],[14,23,18],[16,25,20],[18,29,23]]:
    vm+=row
field('VMAT', vm, kommentar=
     'normAdjust, Tafel 8-15: je qP%6 drei Werte (Positionsklassen).')
field('QPC', [29,30,31,32,32,33,34,34,35,35,36,36,37,37,37,38,38,38,39,39,39,39],
     kommentar='qPc aus qPy fuer qPy >= 30, Tafel 8-15.')

def av_log2(x): return x.bit_length()-1 if x>0 else 0
LV=[]; LN=[]
for sl in range(7):
    for i in range(256):
        prefix = 8 - av_log2(2*i) if i>0 else 8
        if prefix + 1 + sl <= 8:
            lc=(prefix<<sl)+(i>>(av_log2(i)-sl))-(1<<sl)
            mask=-(lc&1)
            lc=(((2+lc)>>1)^mask)-mask
            LV.append(lc & 0xFFFFFFFFFFFFFFFF if lc>=0 else (lc+(1<<64)))
            LN.append(prefix+1+sl)
        elif prefix+1 <= 8:
            LV.append(prefix+100); LN.append(prefix+1)
        else:
            LV.append(108); LN.append(8)
field('LEVTAB_V', LV, typ='i64' if False else 'u64', kommentar=
     'Die Wertetafel des CAVLC-Lesers, genau wie FFmpeg sie baut\n'
     '// (init_cavlc_level_tab): je suffixLength 0..6 eine Zeile zu 256\n'
     '// Eintraegen ueber die naechsten 8 Bits. Ein Wert >= 100 heisst\n'
     '// "langer Weg", die Zahl ist dann 100+level_prefix. Sonst ist es\n'
     '// der fertige Wert -- als Zweierkomplement in 64 Bit, weil Firn\n'
     '// hier u64 fuehrt; der Leser rechnet ihn zurueck.')
field('LEVTAB_N', LN, kommentar='Wieviele Bits der Eintrag verbraucht.')

text = [l for l in '\n'.join(aus).split('\n') if not l.lstrip().startswith('//')]
squeezed = []
for line in text:
    if line == '' and squeezed and squeezed[-1] == '':
        continue
    squeezed.append(line)
while squeezed and squeezed[-1] == '':
    squeezed.pop()
sys.stdout.write('\n'.join(squeezed) + '\n')
