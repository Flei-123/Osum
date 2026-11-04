import json
import time

OK, FAIL, WARN, INFO = "OK", "FAIL", "WARN", "INFO"


class Result:
    def __init__(self, group, name, status, detail=""):
        self.group, self.name, self.status, self.detail = group, name, status, detail

    def as_dict(self):
        return dict(group=self.group, name=self.name, status=self.status, detail=self.detail)


def ok(group, name, detail=""):
    return Result(group, name, OK, detail)


def fail(group, name, detail=""):
    return Result(group, name, FAIL, detail)


def warn(group, name, detail=""):
    return Result(group, name, WARN, detail)


def info(group, name, detail=""):
    return Result(group, name, INFO, detail)


def verdict(group, name, passed, detail="", otherwise=FAIL):
    return Result(group, name, OK if passed else otherwise, detail)


class Report:
    def __init__(self, device):
        self.device = device
        self.started = time.time()
        self.results = []

    def extend(self, results):
        for r in results:
            self.results.append(r)
            print("%-5s %s/%s: %s" % (r.status, r.group, r.name, r.detail[:160]), flush=True)

    def count(self, status):
        return sum(1 for r in self.results if r.status == status)

    def exit_code(self):
        return 1 if self.count(FAIL) else 0

    def summary(self):
        return "%d OK / %d FAIL / %d WARN / %d INFO in %.0f s" % (
            self.count(OK), self.count(FAIL), self.count(WARN), self.count(INFO), time.time() - self.started)

    def write(self, outdir):
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        lines = ["# hw_walk %s (%s)" % (self.device, stamp), "", "- result: **%s**" % self.summary(), ""]
        group = None
        for r in self.results:
            if r.group != group:
                group = r.group
                lines += ["", "## " + group, ""]
            lines.append("- %s **%s**: %s" % (r.status, r.name, r.detail))
        with open(outdir + "/protocol.md", "w") as f:
            f.write("\n".join(lines) + "\n")
        with open(outdir + "/protocol.json", "w") as f:
            json.dump(dict(device=self.device, time=stamp, summary=self.summary(),
                           results=[r.as_dict() for r in self.results]), f, indent=1)
