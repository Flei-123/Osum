from concurrent.futures import ThreadPoolExecutor


class Context:
    def __init__(self, bridge, active=True, timeout=90):
        self.bridge = bridge
        self.active = active
        self.timeout = timeout
        self.cache = {}

    def prefetch(self, commands, workers=4):
        todo = [c for c in dict.fromkeys(commands) if c not in self.cache]
        with ThreadPoolExecutor(max_workers=workers) as ex:
            for command, reply in zip(todo, ex.map(lambda c: self.bridge.run(c, self.timeout), todo)):
                self.cache[command] = reply

    def run(self, command):
        if command not in self.cache:
            self.cache[command] = self.bridge.run(command, self.timeout)
        return self.cache[command]

    def text(self, command):
        reply = self.run(command)
        return reply.body if reply.done else ""

    def answered(self, command):
        return self.run(command).done
