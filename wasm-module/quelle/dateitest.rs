use std::fs;
use std::io::{Write, Read};
fn main() {
    let pfad = "/wasmtest.txt";
    let text = "Diese Zeile hat ein WASM-Modul geschrieben.\n";
    {
        let mut f = fs::File::create(pfad).expect("create");
        f.write_all(text.as_bytes()).expect("write");
    }
    let mut s = String::new();
    fs::File::open(pfad).expect("open").read_to_string(&mut s).expect("read");
    print!("zurueckgelesen: {}", s);
    println!("laenge: {} oktette, gleich: {}", s.len(), s == text);
    let argumente: Vec<String> = std::env::args().collect();
    println!("argumente: {:?}", argumente);
}
