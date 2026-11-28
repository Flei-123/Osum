use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::unix::net::{UnixListener, UnixStream};
use std::process::Command;
use std::sync::mpsc;
use std::sync::{Arc, Barrier, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const WORKER_COUNT: usize = 8;
const BIG_BYTES: usize = 128 << 20;
const MAP_ENTRIES: u64 = 200_000;
const SLEEP_MS: u64 = 30;

type CaseResult = Result<String, String>;

fn text<E: std::fmt::Display>(error: E) -> String {
    error.to_string()
}

fn hello() -> CaseResult {
    Ok("hello osum".to_string())
}

fn threads() -> CaseResult {
    let (sender, receiver) = mpsc::channel();
    let total = Arc::new(Mutex::new(0usize));
    let barrier = Arc::new(Barrier::new(WORKER_COUNT));
    let mut handles = Vec::new();
    for id in 0..WORKER_COUNT {
        let sender = sender.clone();
        let total = Arc::clone(&total);
        let barrier = Arc::clone(&barrier);
        handles.push(thread::spawn(move || {
            barrier.wait();
            *total.lock().unwrap() += id;
            sender.send(id).unwrap();
        }));
    }
    drop(sender);
    for handle in handles {
        handle.join().map_err(|_| "join".to_string())?;
    }
    let received: usize = receiver.iter().sum();
    let sum = *total.lock().unwrap();
    Ok(format!("sum={} recv={}", sum, received))
}

fn condvar() -> CaseResult {
    let pair = Arc::new((Mutex::new(false), Condvar::new()));
    let signaller = Arc::clone(&pair);
    let handle = thread::spawn(move || {
        thread::sleep(Duration::from_millis(SLEEP_MS));
        *signaller.0.lock().unwrap() = true;
        signaller.1.notify_all();
    });
    let (lock, cvar) = &*pair;
    let mut ready = lock.lock().unwrap();
    while !*ready {
        let (guard, timeout) = cvar.wait_timeout(ready, Duration::from_secs(5)).map_err(text)?;
        ready = guard;
        if timeout.timed_out() {
            return Err("condvar timeout".to_string());
        }
    }
    drop(ready);
    handle.join().map_err(|_| "join".to_string())?;
    Ok("condvar".to_string())
}

fn tcp() -> CaseResult {
    let listener = TcpListener::bind("127.0.0.1:0").map_err(text)?;
    let address = listener.local_addr().map_err(text)?;
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut buffer = [0u8; 4];
        stream.read_exact(&mut buffer).unwrap();
        stream.write_all(&buffer).unwrap();
    });
    let mut client = TcpStream::connect(address).map_err(text)?;
    client.write_all(b"echo").map_err(text)?;
    let mut reply = String::new();
    client.read_to_string(&mut reply).map_err(text)?;
    server.join().map_err(|_| "join".to_string())?;
    Ok(reply)
}

fn unix() -> CaseResult {
    let path = format!("/tmp/rusttest-{}.sock", std::process::id());
    let listener = UnixListener::bind(&path).map_err(text)?;
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream.write_all(b"unix-ok").unwrap();
    });
    let mut client = UnixStream::connect(&path).map_err(text)?;
    let mut reply = String::new();
    client.read_to_string(&mut reply).map_err(text)?;
    server.join().map_err(|_| "join".to_string())?;
    let _ = fs::remove_file(&path);
    Ok(reply)
}

fn process() -> CaseResult {
    let output = Command::new("/bin/sh").arg("-c").arg("echo child-$((6*7))").output().map_err(text)?;
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn files() -> CaseResult {
    let dir = format!("/tmp/rusttest-{}", std::process::id());
    fs::create_dir_all(format!("{}/sub", dir)).map_err(text)?;
    fs::write(format!("{}/a", dir), b"a").map_err(text)?;
    fs::write(format!("{}/b", dir), b"b").map_err(text)?;
    fs::rename(format!("{}/b", dir), format!("{}/sub/c", dir)).map_err(text)?;
    std::os::unix::fs::symlink("a", format!("{}/link", dir)).map_err(text)?;
    let mut names: Vec<String> = fs::read_dir(&dir)
        .map_err(text)?
        .map(|entry| entry.unwrap().file_name().to_string_lossy().to_string())
        .collect();
    names.sort();
    let target = fs::read_link(format!("{}/link", dir)).map_err(text)?;
    fs::remove_dir_all(&dir).map_err(text)?;
    Ok(format!("{:?} link={}", names, target.display()))
}

fn bigalloc() -> CaseResult {
    let mut data = vec![0u8; BIG_BYTES];
    for index in (0..data.len()).step_by(4096) {
        data[index] = 1;
    }
    let touched = data.iter().step_by(4096).map(|&byte| byte as usize).sum::<usize>();
    Ok(format!("pages={}", touched))
}

fn hashmap() -> CaseResult {
    let mut map = HashMap::new();
    for key in 0..MAP_ENTRIES {
        map.insert(key, key * 2);
    }
    let sum: u64 = map.values().sum();
    Ok(format!("sum={}", sum))
}

fn panics() -> CaseResult {
    let result = std::panic::catch_unwind(|| {
        let values: Vec<u32> = Vec::new();
        values[3]
    });
    if result.is_err() {
        Ok("caught".to_string())
    } else {
        Err("no panic".to_string())
    }
}

fn timing() -> CaseResult {
    let start = Instant::now();
    thread::sleep(Duration::from_millis(SLEEP_MS));
    let elapsed = start.elapsed();
    if elapsed < Duration::from_millis(SLEEP_MS) || elapsed > Duration::from_secs(5) {
        return Err(format!("elapsed {:?}", elapsed));
    }
    Ok("slept".to_string())
}

fn cpus() -> CaseResult {
    let count = thread::available_parallelism().map_err(text)?;
    Ok(format!("cpus={}", count))
}

fn main() {
    let name = std::env::args().nth(1).unwrap_or_default();
    let cases: Vec<(&str, fn() -> CaseResult)> = vec![
        ("hello", hello),
        ("threads", threads),
        ("condvar", condvar),
        ("tcp", tcp),
        ("unix", unix),
        ("process", process),
        ("files", files),
        ("bigalloc", bigalloc),
        ("hashmap", hashmap),
        ("panic", panics),
        ("timing", timing),
        ("cpus", cpus),
    ];
    for (case, run) in cases {
        if case != name {
            continue;
        }
        match run() {
            Ok(result) => println!("OK {}", result),
            Err(error) => {
                println!("FAIL {}", error);
                std::process::exit(1);
            }
        }
        return;
    }
    println!("FAIL unknown case");
    std::process::exit(2);
}
