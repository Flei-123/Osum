use std::hint::black_box;
fn main() {
    let mut s: u64 = 0;
    let mut i: u64 = 0;
    let n: u64 = black_box(3000000);
    while i < n {
        s = s.wrapping_add(black_box(i) ^ (s >> 3));
        i += 1;
    }
    println!("summe: {}", black_box(s));
}
