import importlib
import pkgutil

GROUPS = []


def group(name, commands=(), active_commands=()):
    def wrap(fn):
        GROUPS.append(dict(name=name, fn=fn, commands=list(commands), active_commands=list(active_commands)))
        return fn
    return wrap


def load_all():
    import checks
    for mod in pkgutil.iter_modules(checks.__path__):
        importlib.import_module("checks." + mod.name)
    return GROUPS
