fn main() {
    println!("Hallo von fremder Software auf OrientOS!");
    let mut s: u64 = 0;
    for i in 1..=100u64 { s += i * i; }
    println!("summe der quadrate 1..100 = {}", s);
}
