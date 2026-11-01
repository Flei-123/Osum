import os, sys, time

file_2, brand_2 = sys.argv[1], sys.argv[2]
offset = int(sys.argv[3]) / 1000.0
deadline_2 = float(sys.argv[4])
mb = brand_2.encode()
ende = time.time() + deadline_2
pos = 0
seen = False
while time.time() < ende:
    try:
        with open(file_2, "rb") as f:
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
