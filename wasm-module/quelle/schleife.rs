// Reine Schleife OHNE Division: misst den Deuter, nicht die Rest-Rechnung.
fn main() {
    let mut s: u64 = 0;
    let mut i: u64 = 0;
    while i < 3000000 {
        s = s.wrapping_add(i ^ (s >> 3));
        i += 1;
    }
    println!("summe: {}", s);
}
