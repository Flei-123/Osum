import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.RandomAccessFile;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardWatchEventKinds;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.IntStream;

public class Compat {
    static final int WORKERS = 8;
    static final int TASKS = 64;
    static final int NULL_LOOPS = 30000;
    static final int GARBAGE_ROUNDS = 40;
    static final int GARBAGE_BYTES = 1 << 20;
    static final int MAP_BYTES = 1 << 16;
    static final int WAIT_SECONDS = 20;
    static final int SLEEP_MS = 30;

    interface Case {
        String run() throws Exception;
    }

    static String hello() {
        return "hello osum java=" + System.getProperty("java.version");
    }

    static String threads() throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(WORKERS);
        AtomicLong total = new AtomicLong();
        ConcurrentHashMap<Integer, Integer> seen = new ConcurrentHashMap<>();
        List<Future<?>> futures = new ArrayList<>();
        for (int i = 1; i <= TASKS; i++) {
            final int n = i;
            futures.add(pool.submit(() -> {
                total.addAndGet(n);
                seen.put(n, n);
            }));
        }
        for (Future<?> future : futures) {
            future.get(WAIT_SECONDS, TimeUnit.SECONDS);
        }
        pool.shutdown();
        long parallel = IntStream.rangeClosed(1, 1000).parallel().asLongStream().sum();
        return "sum=" + total.get() + " seen=" + seen.size() + " parallel=" + parallel;
    }

    static String nio() throws Exception {
        try (Selector selector = Selector.open(); ServerSocketChannel server = ServerSocketChannel.open()) {
            server.bind(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0));
            server.configureBlocking(false);
            server.register(selector, SelectionKey.OP_ACCEPT);
            int port = ((InetSocketAddress) server.getLocalAddress()).getPort();
            Thread client = new Thread(() -> {
                try (SocketChannel channel = SocketChannel.open(new InetSocketAddress(InetAddress.getLoopbackAddress(), port))) {
                    channel.write(ByteBuffer.wrap("nio-ok".getBytes()));
                } catch (Exception ignored) {
                }
            });
            client.start();
            StringBuilder received = new StringBuilder();
            long deadline = System.currentTimeMillis() + WAIT_SECONDS * 1000L;
            while (received.length() < 6 && System.currentTimeMillis() < deadline) {
                selector.select(500);
                for (SelectionKey key : new ArrayList<>(selector.selectedKeys())) {
                    selector.selectedKeys().remove(key);
                    if (key.isAcceptable()) {
                        SocketChannel accepted = server.accept();
                        accepted.configureBlocking(false);
                        accepted.register(selector, SelectionKey.OP_READ);
                    } else if (key.isReadable()) {
                        ByteBuffer buffer = ByteBuffer.allocate(16);
                        int count = ((SocketChannel) key.channel()).read(buffer);
                        if (count > 0) {
                            received.append(new String(buffer.array(), 0, count));
                        }
                    }
                }
            }
            client.join();
            return received.toString();
        }
    }

    static String mapped() throws Exception {
        Path file = Files.createTempFile("javamap", ".bin");
        try (RandomAccessFile raf = new RandomAccessFile(file.toFile(), "rw")) {
            raf.setLength(MAP_BYTES);
            FileChannel.MapMode mode = FileChannel.MapMode.READ_WRITE;
            java.nio.MappedByteBuffer buffer = raf.getChannel().map(mode, 0, MAP_BYTES);
            buffer.put("mapped".getBytes());
            buffer.force();
        }
        byte[] back = Files.readAllBytes(file);
        Files.delete(file);
        return new String(back, 0, 6);
    }

    static String http() throws Exception {
        try (ServerSocket server = new ServerSocket(0, 5, InetAddress.getLoopbackAddress())) {
            Thread serverThread = new Thread(() -> {
                try (Socket socket = server.accept()) {
                    BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream()));
                    String line;
                    while ((line = in.readLine()) != null && !line.isEmpty()) {
                    }
                    socket.getOutputStream().write("HTTP/1.0 200 OK\r\nContent-Length: 4\r\n\r\npong".getBytes());
                } catch (Exception ignored) {
                }
            });
            serverThread.start();
            java.net.http.HttpClient client = java.net.http.HttpClient.newHttpClient();
            java.net.http.HttpRequest request = java.net.http.HttpRequest.newBuilder(
                java.net.URI.create("http://127.0.0.1:" + server.getLocalPort() + "/ping")).build();
            String body = client.send(request, java.net.http.HttpResponse.BodyHandlers.ofString()).body();
            serverThread.join();
            return body;
        }
    }

    static String process() throws Exception {
        Process child = new ProcessBuilder("/bin/sh", "-c", "echo child-$((6*7))").redirectErrorStream(true).start();
        String line = new BufferedReader(new InputStreamReader(child.getInputStream())).readLine();
        int rc = child.waitFor();
        return line + " rc=" + rc;
    }

    static String garbage() {
        List<byte[]> keep = new ArrayList<>();
        for (int i = 0; i < GARBAGE_ROUNDS; i++) {
            keep.add(new byte[GARBAGE_BYTES]);
            if (keep.size() > 8) {
                keep.remove(0);
            }
        }
        System.gc();
        return "heap=" + (Runtime.getRuntime().totalMemory() > 0);
    }

    static int touch(int[] values, int index) {
        return values[index];
    }

    static String nullPointers() {
        int[] values = new int[4];
        int caught = 0;
        for (int i = 0; i < NULL_LOOPS; i++) {
            try {
                touch(i % 3 == 0 ? null : values, 1);
            } catch (NullPointerException expected) {
                caught++;
            }
        }
        return "npe=" + caught;
    }

    static String files() throws Exception {
        Path dir = Files.createTempDirectory("javafiles");
        Path a = Files.writeString(dir.resolve("a"), "a");
        Files.copy(a, dir.resolve("b"), StandardCopyOption.REPLACE_EXISTING);
        Files.move(dir.resolve("b"), dir.resolve("c"));
        Files.createSymbolicLink(dir.resolve("link"), Path.of("a"));
        List<String> names = new ArrayList<>();
        try (var stream = Files.list(dir)) {
            stream.forEach(path -> names.add(path.getFileName().toString()));
        }
        java.util.Collections.sort(names);
        try (var walk = Files.walk(dir)) {
            walk.sorted(java.util.Comparator.reverseOrder()).forEach(path -> path.toFile().delete());
        }
        return names.toString();
    }

    static String watch() throws Exception {
        Path dir = Files.createTempDirectory("javawatch");
        try (WatchService service = dir.getFileSystem().newWatchService()) {
            dir.register(service, StandardWatchEventKinds.ENTRY_CREATE);
            Files.writeString(dir.resolve("new"), "x");
            WatchKey key = service.poll(WAIT_SECONDS, TimeUnit.SECONDS);
            String name = key == null ? "none" : key.pollEvents().get(0).context().toString();
            Files.delete(dir.resolve("new"));
            Files.delete(dir);
            return "created=" + name;
        }
    }

    static String time() throws Exception {
        long start = System.nanoTime();
        Thread.sleep(SLEEP_MS);
        long elapsedMs = (System.nanoTime() - start) / 1_000_000;
        String zone = java.time.ZoneId.systemDefault().getId();
        return "slept=" + (elapsedMs >= SLEEP_MS) + " zone=" + (!zone.isEmpty());
    }

    static String cpus() {
        return "cpus=" + Runtime.getRuntime().availableProcessors();
    }

    static String memory() {
        Runtime runtime = Runtime.getRuntime();
        return "max=" + (runtime.maxMemory() > 0);
    }

    public static void main(String[] args) throws Exception {
        String name = args.length > 0 ? args[0] : "";
        java.util.Map<String, Case> cases = new java.util.LinkedHashMap<>();
        cases.put("hello", Compat::hello);
        cases.put("threads", Compat::threads);
        cases.put("nio", Compat::nio);
        cases.put("mapped", Compat::mapped);
        cases.put("http", Compat::http);
        cases.put("process", Compat::process);
        cases.put("gc", Compat::garbage);
        cases.put("npe", Compat::nullPointers);
        cases.put("files", Compat::files);
        cases.put("watch", Compat::watch);
        cases.put("time", Compat::time);
        cases.put("cpus", Compat::cpus);
        cases.put("memory", Compat::memory);
        Case chosen = cases.get(name);
        if (chosen == null) {
            System.out.println("FAIL unknown case");
            System.exit(2);
        }
        System.out.println("OK " + chosen.run());
        System.exit(0);
    }
}
