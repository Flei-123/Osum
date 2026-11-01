import os, sys, time

datei, marke = sys.argv[1], sys.argv[2]
offset = int(sys.argv[3]) / 1000.0
frist = float(sys.argv[4])
mb = marke.encode()
ende = time.time() + frist
pos = 0
seen = False
while time.time() < ende:
    try:
        with open(datei, "rb") as f:
            f.seek(0)
            inhalt = f.read()
    except OSError:
        inhalt = b""
    if mb in inhalt:
        seen = True
        break
    time.sleep(0.02)
if not seen:
    sys.exit(3)
time.sleep(offset)
sys.exit(0)
