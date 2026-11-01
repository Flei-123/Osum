import os, sys, time

datei, marke = sys.argv[1], sys.argv[2]
versatz = int(sys.argv[3]) / 1000.0
frist = float(sys.argv[4])
mb = marke.encode()
ende = time.time() + frist
pos = 0
gesehen = False
while time.time() < ende:
    try:
        with open(datei, "rb") as f:
            f.seek(0)
            inhalt = f.read()
    except OSError:
        inhalt = b""
    if mb in inhalt:
        gesehen = True
        break
    time.sleep(0.02)
if not gesehen:
    sys.exit(3)
time.sleep(versatz)
sys.exit(0)
