package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"sort"
	"sync"
	"syscall"
	"time"
)

const (
	goroutineCount = 200
	garbageChunks  = 64
	chunkBytes     = 1 << 20
	tickCount      = 5
	tickInterval   = 20 * time.Millisecond
	waitLimit      = 5 * time.Second
	mapBytes       = 1 << 16
)

type testCase func() (string, error)

var cases = map[string]testCase{
	"hello":      hello,
	"goroutines": goroutines,
	"gc":         garbage,
	"http":       httpLoopback,
	"unix":       unixLoopback,
	"exec":       execChild,
	"timers":     timers,
	"signal":     signals,
	"files":      files,
	"mmap":       mapFile,
	"cpus":       cpus,
}

func hello() (string, error) {
	return "hello osum", nil
}

func goroutines() (string, error) {
	var group sync.WaitGroup
	results := make(chan int, goroutineCount)
	for i := 1; i <= goroutineCount; i++ {
		group.Add(1)
		go func(n int) {
			defer group.Done()
			time.Sleep(time.Millisecond)
			results <- n
		}(i)
	}
	group.Wait()
	close(results)
	sum := 0
	for n := range results {
		sum += n
	}
	return fmt.Sprintf("sum=%d", sum), nil
}

func garbage() (string, error) {
	var keep [][]byte
	for i := 0; i < garbageChunks; i++ {
		chunk := make([]byte, chunkBytes)
		chunk[0] = byte(i)
		keep = append(keep, chunk)
	}
	runtime.GC()
	keep = nil
	runtime.GC()
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return fmt.Sprintf("gc=%d", stats.NumGC), nil
}

func httpLoopback() (string, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "pong") })
	go http.Serve(listener, mux)
	response, err := http.Get("http://" + listener.Addr().String() + "/ping")
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	return string(body), err
}

func unixLoopback() (string, error) {
	path := filepath.Join(os.TempDir(), fmt.Sprintf("gotest-%d.sock", os.Getpid()))
	defer os.Remove(path)
	listener, err := net.Listen("unix", path)
	if err != nil {
		return "", err
	}
	defer listener.Close()
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		conn.Write([]byte("unix-ok"))
	}()
	conn, err := net.Dial("unix", path)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	data, err := io.ReadAll(conn)
	return string(data), err
}

func execChild() (string, error) {
	output, err := exec.Command("/bin/sh", "-c", "echo child-$((6*7))").Output()
	return string(output), err
}

func timers() (string, error) {
	start := time.Now()
	ticker := time.NewTicker(tickInterval)
	defer ticker.Stop()
	for i := 0; i < tickCount; i++ {
		<-ticker.C
	}
	elapsed := time.Since(start)
	if elapsed < tickInterval*tickCount/2 || elapsed > waitLimit {
		return "", fmt.Errorf("elapsed %v", elapsed)
	}
	return fmt.Sprintf("ticks=%d", tickCount), nil
}

func signals() (string, error) {
	received := make(chan os.Signal, 1)
	signal.Notify(received, syscall.SIGUSR1)
	if err := syscall.Kill(os.Getpid(), syscall.SIGUSR1); err != nil {
		return "", err
	}
	select {
	case <-received:
		return "sigusr1", nil
	case <-time.After(waitLimit):
		return "", fmt.Errorf("no signal")
	}
}

func files() (string, error) {
	dir, err := os.MkdirTemp("", "gotest")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(dir)
	for _, name := range []string{"b", "a", "c"} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(name), 0o644); err != nil {
			return "", err
		}
	}
	if err := os.Rename(filepath.Join(dir, "c"), filepath.Join(dir, "d")); err != nil {
		return "", err
	}
	if err := os.Symlink("a", filepath.Join(dir, "link")); err != nil {
		return "", err
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", err
	}
	var names []string
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	sort.Strings(names)
	target, err := os.Readlink(filepath.Join(dir, "link"))
	return fmt.Sprintf("%v link=%s", names, target), err
}

func mapFile() (string, error) {
	file, err := os.CreateTemp("", "gomap")
	if err != nil {
		return "", err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	if err := file.Truncate(mapBytes); err != nil {
		return "", err
	}
	data, err := syscall.Mmap(int(file.Fd()), 0, mapBytes, syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		return "", err
	}
	copy(data, "mapped")
	if err := syscall.Munmap(data); err != nil {
		return "", err
	}
	back := make([]byte, 6)
	if _, err := file.ReadAt(back, 0); err != nil {
		return "", err
	}
	return string(back), nil
}

func cpus() (string, error) {
	return fmt.Sprintf("cpus=%d procs=%d", runtime.NumCPU(), runtime.GOMAXPROCS(0)), nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("FAIL usage")
		os.Exit(2)
	}
	run, found := cases[os.Args[1]]
	if !found {
		fmt.Println("FAIL unknown case")
		os.Exit(2)
	}
	result, err := run()
	if err != nil {
		fmt.Println("FAIL", err)
		os.Exit(1)
	}
	fmt.Println("OK", result)
}
