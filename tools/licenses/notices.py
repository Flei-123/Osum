# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import registry  # noqa: E402

LICENSE_DIR = "/usr/share/licenses"
NOTICES_NAME = "THIRD-PARTY-NOTICES"
FILE_MODE = "@0644"
COPYLEFT_MARKERS = ("GPL", "MPL")
DEVICE_DATA = ("/etc/jarvis/",)
OFFER = ("The components marked [source] are distributed under licences that require the corresponding source to be "
         "available. The source of each is available at the URL given for it. The source of OrientOS itself is "
         "available at https://github.com/Flei-123 and on request from the author for three years after distribution.")


def split_spec(word):
    if "->" in word:
        return word.split("->")[0], None
    if "=" not in word:
        return word.split("@")[0], None
    dest, source = word.split("=", 1)
    return dest, source.split("@")[0]


def inside(path, roots):
    real = os.path.realpath(path)
    return any(real == base or real.startswith(base + os.sep) for base in roots)


def check_specs(components, profile, specs, own_roots):
    present, errors = {}, []
    active = [c for c in components if profile in c.profiles]
    for word in specs:
        if not word.startswith("/"):
            continue
        dest, source = split_spec(word)
        if dest.endswith("/"):
            continue
        hits = [c for c in active if registry.matches(c, dest)]
        for comp in hits:
            present[comp.id] = comp
        if hits:
            continue
        if registry.looks_foreign(dest):
            errors.append("%s: foreign-looking file without licence entry" % dest)
        elif source and not inside(source, own_roots) and not dest.startswith(DEVICE_DATA):
            errors.append("%s: source %s is outside the repository and has no licence entry" % (dest, source))
    return present, errors


def always_present(components, profile):
    return {c.id: c for c in components if profile in c.profiles and not c.paths}


def install_name(comp, text):
    return "%s/%s/%s" % (LICENSE_DIR, comp.id, os.path.basename(text))


def render_notices(present):
    lines = ["THIRD-PARTY NOTICES", "", "OrientOS contains the following components.", ""]
    for comp in sorted(present.values(), key=lambda c: c.id):
        tag = " [source]" if any(m in comp.spdx for m in COPYLEFT_MARKERS) else ""
        lines += ["%s %s%s" % (comp.name, comp.version, tag), "  Licence: %s" % comp.spdx,
                  "  Copyright: %s" % comp.copyright, "  Origin: %s" % comp.source]
        lines += ["  Text: %s" % install_name(comp, t) for t in comp.texts]
        lines.append("")
    lines += [OFFER, ""]
    return "\n".join(lines)


def build_specs(root, out, present):
    os.makedirs(out, exist_ok=True)
    notices = os.path.join(out, NOTICES_NAME)
    with open(notices, "w", encoding="utf-8") as handle:
        handle.write(render_notices(present))
    specs = ["/usr/", "/usr/share/", LICENSE_DIR + "/", "%s/%s=%s%s" % (LICENSE_DIR, NOTICES_NAME, notices, FILE_MODE)]
    for comp in sorted(present.values(), key=lambda c: c.id):
        if not comp.texts:
            continue
        specs.append("%s/%s/" % (LICENSE_DIR, comp.id))
        specs += ["%s=%s%s" % (install_name(comp, t), os.path.join(root, t), FILE_MODE) for t in comp.texts]
    return specs


def image(root, profile, out, spec_file):
    components = registry.load(root)
    problems = registry.lint(root, components)
    with open(spec_file, encoding="utf-8") as handle:
        specs = [line.rstrip("\n") for line in handle if line.strip()]
    present, errors = check_specs(components, profile, specs, [os.path.realpath(root), os.path.realpath(os.path.dirname(out))])
    present.update(always_present(components, profile))
    for message in problems + errors:
        print("licenses: " + message, file=sys.stderr)
    if problems or errors:
        return 1
    specs = build_specs(root, out, present)
    with open(os.path.join(out, "specs.txt"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(specs) + "\n")
    return 0


def listing(root, profile, list_file):
    components = registry.load(root)
    with open(list_file, encoding="utf-8") as handle:
        dests = [line.split()[0] for line in handle if line.startswith("/") and not line.split()[0].endswith("/")]
    _, errors = check_specs(components, profile, dests, [])
    for message in errors:
        print("licenses: " + message, file=sys.stderr)
    return 1 if errors else 0


def package_licenses(root):
    errors = []
    base = os.path.join(root, "pakete")
    for name in sorted(os.listdir(base)):
        info = os.path.join(base, name, "INFO")
        if not os.path.isfile(info):
            continue
        with open(info, encoding="utf-8") as handle:
            values = dict(line.rstrip("\n").split("=", 1) for line in handle if "=" in line)
        if not registry.SPDX_RE.match(values.get("license", "")):
            errors.append("pakete/%s/INFO: missing or invalid license=" % name)
    return errors


def main(argv):
    default_root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    root = os.path.realpath(os.environ.get("LICENSES_ROOT", default_root))
    if len(argv) == 2 and argv[1] == "packages":
        errors = package_licenses(root)
        print("\n".join(errors), file=sys.stderr)
        return 1 if errors else 0
    if len(argv) == 5 and argv[1] == "image":
        return image(root, argv[2], argv[3], argv[4])
    if len(argv) == 4 and argv[1] == "listing":
        return listing(root, argv[2], argv[3])
    if len(argv) == 2 and argv[1] == "lint":
        problems = registry.lint(root, registry.load(root))
        print("\n".join(problems), file=sys.stderr)
        return 1 if problems else 0
    print("usage: notices.py image <profile> <outdir> <specfile> | listing <profile> <listfile> | lint | packages", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
