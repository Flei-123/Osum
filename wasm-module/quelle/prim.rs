// DERSELBE ALGORITHMUS wie kernel/app/prim.fi -- Probedivision.
fn ist_prim(n: u64) -> bool {
    if n < 2 { return false; }
    if n % 2 == 0 { return n == 2; }
    let mut d: u64 = 3;
    while d * d <= n {
        if n % d == 0 { return false; }
        d += 2;
    }
    true
}
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let grenze: u64 = if a.len() > 1 { a[1].parse().unwrap_or(200000) } else { 200000 };
    let mut zahl: u64 = 0;
    let mut k: u64 = 2;
    while k < grenze {
        if ist_prim(k) { zahl += 1; }
        k += 1;
    }
    println!("primzahlen unter {}: {}", grenze, zahl);
}
