// Same algorithm as atmos.gd, compiled natively, to bound what C#/C++/Rust would give.
use std::time::Instant;
fn build(w: usize, h: usize) -> (Vec<u8>, [Vec<f32>; 3]) {
    let n = w * h;
    let mut walls = vec![0u8; n];
    let mut g = [vec![0f32; n], vec![0f32; n], vec![0f32; n]];
    let mut s: u32 = 1234;
    let mut rnd = || { s ^= s << 13; s ^= s >> 17; s ^= s << 5; (s as f32) / (u32::MAX as f32) };
    for y in 0..h { for x in 0..w {
        let i = y * w + x;
        let border = x == 0 || y == 0 || x == w - 1 || y == h - 1;
        let grid_wall = (x % 16 == 0 || y % 16 == 0) && !(x % 16 == 8 || y % 16 == 8);
        if border || grid_wall { walls[i] = 1; } else {
            g[0][i] = 21.0 + rnd() * 4.0; g[1][i] = 79.0 + rnd() * 4.0; g[2][i] = rnd();
        }
    }}
    (walls, g)
}
fn step(w: usize, h: usize, walls: &[u8], a: &[Vec<f32>; 3], b: &mut [Vec<f32>; 3], q: &mut [u8], k: f32) {
    for y in 1..h - 1 { let row = y * w; for x in 1..w - 1 {
        let i = row + x;
        if walls[i] != 0 { continue; }
        let mut tot = 0f32;
        for gi in 0..3 {
            let c = a[gi][i]; let mut d = 0f32;
            for j in [i - 1, i + 1, i - w, i + w] { if walls[j] == 0 { d += a[gi][j] - c; } }
            let v = c + k * d; b[gi][i] = v; tot += v;
        }
        let p = (tot * 2.0) as i32; q[i] = if p < 255 { p as u8 } else { 255 };
    }}
}
fn main() {
    for (w, h) in [(60usize, 40usize), (128, 96), (255, 255)] {
        let (walls, mut a) = build(w, h);
        let mut b = [vec![0f32; w * h], vec![0f32; w * h], vec![0f32; w * h]];
        let mut q = vec![0u8; w * h];
        for _ in 0..5 { step(w, h, &walls, &a, &mut b, &mut q, 0.2); std::mem::swap(&mut a, &mut b); }
        let mut samples = Vec::new();
        for _ in 0..200 {
            let t = Instant::now();
            step(w, h, &walls, &a, &mut b, &mut q, 0.2); std::mem::swap(&mut a, &mut b);
            samples.push(t.elapsed().as_secs_f64() * 1000.0);
        }
        samples.sort_by(|x, y| x.partial_cmp(y).unwrap());
        let chk: f64 = a.iter().map(|v| v.iter().map(|x| *x as f64).sum::<f64>()).sum();
        println!("native grid {}x{} step median={:.4} ms p95={:.4} ms (checksum {:.1}, q[mid]={})", w, h, samples[100], samples[190], chk, q[(h/2)*w + w/2 + 1]);
    }
}
