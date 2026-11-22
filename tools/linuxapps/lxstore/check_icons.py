import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "lib"))
import mkpkgs

registry = sys.argv[1] if len(sys.argv) > 1 else mkpkgs.REGISTRY
for app in mkpkgs.read_registry(registry):
    mkpkgs.icon_bundle(app["icon"])
print("icons ok")
