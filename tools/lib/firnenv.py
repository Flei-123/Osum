import os


def firnc_path(root):
    explicit = os.environ.get("FIRNC")
    if explicit:
        return explicit
    version = os.environ.get("FIRN_VERSION")
    if not version:
        with open(os.path.join(root, "firn.toolchain")) as handle:
            version = handle.read().split()[1]
    home = os.environ.get("FIRN_HOME", os.path.expanduser("~/.firn"))
    return os.path.join(home, "versions", version, "bin", "firnc")
