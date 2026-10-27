import sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
Image.open(src).convert("RGB").crop((8, 336, 648, 752)).save(dst)
