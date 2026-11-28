const fs = require('fs');
const os = require('os');
const net = require('net');
const http = require('http');
const dgram = require('dgram');
const zlib = require('zlib');
const crypto = require('crypto');
const path = require('path');
const childProcess = require('child_process');
const { Worker, isMainThread, parentPort, workerData } = require('worker_threads');

const LOOPBACK = '127.0.0.1';
const WAIT_MS = 10000;
const BIG_BYTES = 128 << 20;
const ZLIB_BYTES = 100000;

const withTimeout = (promise, label) =>
  Promise.race([promise, new Promise((_, reject) => setTimeout(() => reject(new Error(label + ' timeout')), WAIT_MS))]);

const collect = (stream) =>
  new Promise((resolve) => {
    let received = '';
    stream.on('data', (chunk) => { received += chunk; });
    stream.on('end', () => resolve(received));
  });

const cases = {
  async fs() {
    const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'nodefs'));
    await fs.promises.writeFile(path.join(dir, 'a'), 'a');
    await fs.promises.rename(path.join(dir, 'a'), path.join(dir, 'b'));
    await fs.promises.symlink('b', path.join(dir, 'link'));
    const names = (await fs.promises.readdir(dir)).sort();
    await fs.promises.rm(dir, { recursive: true });
    return names.join(',');
  },
  async tcp() {
    const server = net.createServer((socket) => socket.end('tcp-ok'));
    await new Promise((resolve) => server.listen(0, LOOPBACK, resolve));
    const data = await withTimeout(collect(net.connect(server.address().port, LOOPBACK)), 'tcp');
    server.close();
    return data;
  },
  async http() {
    const server = http.createServer((request, response) => response.end('pong'));
    await new Promise((resolve) => server.listen(0, LOOPBACK, resolve));
    const body = await withTimeout(new Promise((resolve, reject) => {
      http.get({ host: LOOPBACK, port: server.address().port, path: '/' }, (response) => resolve(collect(response))).on('error', reject);
    }), 'http');
    server.close();
    return body;
  },
  async udp() {
    const receiver = dgram.createSocket('udp4');
    await new Promise((resolve) => receiver.bind(0, LOOPBACK, resolve));
    const message = withTimeout(new Promise((resolve) => receiver.on('message', (data) => resolve(data.toString()))), 'udp');
    const sender = dgram.createSocket('udp4');
    sender.send('udp-ok', receiver.address().port, LOOPBACK, () => sender.close());
    const received = await message;
    receiver.close();
    return received;
  },
  async spawn() {
    const result = childProcess.spawnSync('/bin/sh', ['-c', 'echo child-$((6*7))'], { encoding: 'utf8' });
    return result.stdout.trim() + ' rc=' + result.status;
  },
  async fork() {
    const child = childProcess.fork(__filename, ['forkchild']);
    const reply = await withTimeout(new Promise((resolve) => child.on('message', resolve)), 'fork');
    child.kill();
    return reply;
  },
  async worker() {
    const shared = new SharedArrayBuffer(4);
    const worker = new Worker(__filename, { workerData: shared });
    const message = await withTimeout(new Promise((resolve) => worker.on('message', resolve)), 'worker');
    return message + ' value=' + Atomics.load(new Int32Array(shared), 0);
  },
  async zlib() {
    const data = Buffer.alloc(ZLIB_BYTES, 'z');
    return 'same=' + (zlib.gunzipSync(zlib.gzipSync(data)).length === data.length);
  },
  async crypto() {
    const digest = crypto.createHash('sha256').update('abc').digest('hex').slice(0, 8);
    return digest + ' key=' + crypto.scryptSync('pw', 'salt', 16).length + ' rnd=' + crypto.randomBytes(8).length;
  },
  async watch() {
    const dir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'nodewatch'));
    const event = withTimeout(new Promise((resolve) => {
      const watcher = fs.watch(dir, (type, name) => { watcher.close(); resolve(type + ':' + name); });
    }), 'watch');
    await fs.promises.writeFile(path.join(dir, 'new'), 'x');
    const seen = await event;
    await fs.promises.rm(dir, { recursive: true });
    return seen;
  },
  async timers() {
    const start = Date.now();
    await new Promise((resolve) => setTimeout(resolve, 30));
    const ticks = await new Promise((resolve) => {
      let count = 0;
      const handle = setInterval(() => { if (++count === 3) { clearInterval(handle); resolve(count); } }, 10);
    });
    return 'ticks=' + ticks + ' slept=' + (Date.now() - start >= 30);
  },
  async cpus() {
    return 'cpus=' + os.cpus().length + ' mem=' + (os.totalmem() > 0);
  },
  async dns() {
    const found = await withTimeout(require('dns').promises.lookup('localhost'), 'dns');
    return 'lookup=' + (found.address.length > 0);
  },
  async bigbuffer() {
    return 'bytes=' + Buffer.alloc(BIG_BYTES, 1).length;
  },
};

function runWorker() {
  const view = new Int32Array(workerData);
  Atomics.store(view, 0, 7);
  Atomics.notify(view, 0);
  parentPort.postMessage('worker-done');
}

function runMain() {
  const name = process.argv[2];
  if (name === 'forkchild') {
    process.send('fork-ok');
    setTimeout(() => process.exit(0), WAIT_MS);
    return;
  }
  if (!cases[name]) {
    console.log('FAIL unknown case');
    process.exit(2);
  }
  cases[name]().then(
    (result) => { console.log('OK', result); process.exit(0); },
    (error) => { console.log('FAIL', error.message); process.exit(1); },
  );
}

if (isMainThread) {
  runMain();
} else {
  runWorker();
}
