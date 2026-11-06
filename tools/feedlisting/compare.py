import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "ota"))
import listdoc
import listing

KEY_TO_GENERIC = {
    "legacy": {"fassung": "revision", "schluesselgen": "keygen", "kette": "chain", "gesperrt": "blocked", "paket": "package"},
    "english": {"revision": "revision", "keygen": "keygen", "chain": "chain", "blocked": "blocked", "package": "package"},
}


def normalize(style, raw):
    rows = raw.decode("ascii").rstrip("\n").split("\n")
    marker, body = rows[0], rows[1:]
    mapping = KEY_TO_GENERIC[style]
    out = []
    for row in body:
        fields = row.split("\t")
        out.append("\t".join([mapping.get(fields[0], fields[0])] + fields[1:]))
    return marker, out


def verify(feed_dir, key_path, style):
    text_name, sig_name = listdoc.STYLES[style]["files"]
    raw = open(os.path.join(feed_dir, text_name), "rb").read()
    sig = open(os.path.join(feed_dir, sig_name), "rb").read()
    opk = listing.load_opk()
    public = opk.ed25519_public(open(key_path, "rb").read())
    if not opk.ed25519_verify(public, raw, sig):
        raise SystemExit("signature of %s does not verify" % text_name)
    return raw


def main():
    feed_dir, key_path = sys.argv[1], sys.argv[2]
    legacy = normalize("legacy", verify(feed_dir, key_path, "legacy"))
    english = normalize("english", verify(feed_dir, key_path, "english"))
    if legacy[0] != "OTA2" or english[0] != "OTA3":
        raise SystemExit("unexpected markers %r %r" % (legacy[0], english[0]))
    if legacy[1] != english[1]:
        raise SystemExit("documents differ:\n%r\n%r" % (legacy[1], english[1]))
    if not any(r.startswith("package\t") for r in english[1]):
        raise SystemExit("no package rows")
    print("compare ok: %d rows" % len(english[1]))


main()
