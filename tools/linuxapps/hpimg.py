import os, select, subprocess, sys, time

img, wd, mem, smp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
cmds = sys.argv[5:]
off = 2048 * 512
subprocess.run(['mcopy', '-o', '-i', img + '@@%d' % off, '::/limine.conf', wd + '/l.orig'], check=True)
lines = open(wd + '/l.orig').read().splitlines()
start = [i for i, l in enumerate(lines) if l.startswith('/Command line')][0]
end = next((j for j in range(start + 1, len(lines)) if lines[j].startswith('/')), len(lines))
open(wd + '/l.conf', 'w').write('timeout: 0\ndefault_entry: 1\n\n' + '\n'.join(lines[start:end]) + '\n')
for t in ('::/limine.conf', '::/boot/limine.conf'):
    subprocess.run(['mcopy', '-o', '-i', img + '@@%d' % off, wd + '/l.conf', t], check=True)
acc = ['-accel', 'kvm', '-cpu', 'host'] if os.access('/dev/kvm', os.W_OK) else []
p = subprocess.Popen(['qemu-system-x86_64'] + acc + ['-m', mem, '-smp', smp, '-drive', 'file=%s,format=raw,if=none,id=s' % img,
                     '-device', 'ide-hd,drive=s', '-serial', 'stdio', '-display', 'none', '-monitor', 'none', '-no-reboot', '-nic', 'none'],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
buf = b''


def read_until(timeout, stop=None):
    global buf
    end_t = time.time() + timeout
    while time.time() < end_t:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if r:
            d = os.read(p.stdout.fileno(), 65536)
            if not d:
                break
            buf += d
        if stop and stop in buf[-4000:]:
            return True
    return False


out = open(wd + '/console.txt', 'wb')
read_until(90, b'osum$')
for c in cmds:
    n = len(buf)
    p.stdin.write((c + '\necho @@END\n').encode())
    p.stdin.flush()
    read_until(float(os.environ.get('CMD_TIMEOUT', '600')), b'\n@@END')
    out.write(('$ ' + c + '\n').encode())
    out.write(buf[n:])
    out.write(b'\n')
    out.flush()
p.kill()
out.close()
