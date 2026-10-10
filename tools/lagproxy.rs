// UDP relay that imitates a real internet link for the load test:
// every datagram, in each direction, is delayed by `delay ± jitter` ms and
// dropped with probability `loss`. Each client gets its own socket towards
// the server, so the server still sees separate peers.
// usage: lagproxy LISTEN_PORT SERVER_PORT DELAY_MS JITTER_MS LOSS_PERCENT
use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

struct Item { at: Instant, seq: u64, up: bool, idx: usize, data: Vec<u8> }
impl PartialEq for Item { fn eq(&self, o: &Self) -> bool { self.at == o.at && self.seq == o.seq } }
impl Eq for Item {}
impl PartialOrd for Item { fn partial_cmp(&self, o: &Self) -> Option<std::cmp::Ordering> { Some(self.cmp(o)) } }
impl Ord for Item { fn cmp(&self, o: &Self) -> std::cmp::Ordering { (self.at, self.seq).cmp(&(o.at, o.seq)) } }

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> f64 { self.0 ^= self.0 << 13; self.0 ^= self.0 >> 7; self.0 ^= self.0 << 17; (self.0 >> 11) as f64 / (1u64 << 53) as f64 }
}

struct Shared {
    heap: Mutex<BinaryHeap<Reverse<Item>>>,
    cv: Condvar,
    clients: Mutex<Vec<(SocketAddr, Arc<UdpSocket>)>>,
    seq: AtomicU64, fwd: AtomicU64, dropped: AtomicU64,
}

fn enqueue(sh: &Shared, rng: &mut Rng, delay: f64, jitter: f64, loss: f64, up: bool, idx: usize, data: &[u8]) {
    if rng.next() < loss { sh.dropped.fetch_add(1, Ordering::Relaxed); return; }
    let d = (delay + (rng.next() * 2.0 - 1.0) * jitter).max(0.0);
    let item = Item { at: Instant::now() + Duration::from_micros((d * 1000.0) as u64), seq: sh.seq.fetch_add(1, Ordering::Relaxed), up, idx, data: data.to_vec() };
    sh.heap.lock().unwrap().push(Reverse(item));
    sh.cv.notify_one();
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let listen: u16 = a[1].parse().unwrap();
    let server: u16 = a[2].parse().unwrap();
    let delay: f64 = a[3].parse().unwrap();
    let jitter: f64 = a[4].parse().unwrap();
    let loss: f64 = a[5].parse::<f64>().unwrap() / 100.0;
    let front = Arc::new(UdpSocket::bind(("0.0.0.0", listen)).unwrap());
    let sh = Arc::new(Shared { heap: Mutex::new(BinaryHeap::new()), cv: Condvar::new(), clients: Mutex::new(Vec::new()), seq: AtomicU64::new(0), fwd: AtomicU64::new(0), dropped: AtomicU64::new(0) });

    // delivery thread
    { let sh = sh.clone(); let front = front.clone();
      std::thread::spawn(move || loop {
        let mut heap = sh.heap.lock().unwrap();
        loop {
            let now = Instant::now();
            match heap.peek() {
                Some(Reverse(it)) if it.at <= now => break,
                Some(Reverse(it)) => { let w = it.at - now; heap = sh.cv.wait_timeout(heap, w).unwrap().0; }
                None => { heap = sh.cv.wait(heap).unwrap(); }
            }
        }
        let Reverse(it) = heap.pop().unwrap();
        drop(heap);
        let (addr, back) = { let c = sh.clients.lock().unwrap(); (c[it.idx].0, c[it.idx].1.clone()) };
        if it.up { let _ = back.send(&it.data); } else { let _ = front.send_to(&it.data, addr); }
        sh.fwd.fetch_add(1, Ordering::Relaxed);
      }); }
    // stats thread
    { let sh = sh.clone();
      std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(5));
        eprintln!("PROXY forwarded={} dropped={} clients={}", sh.fwd.load(Ordering::Relaxed), sh.dropped.load(Ordering::Relaxed), sh.clients.lock().unwrap().len());
      }); }

    let mut map: HashMap<SocketAddr, usize> = HashMap::new();
    let mut rng = Rng(0x9E3779B97F4A7C15);
    let mut buf = [0u8; 65536];
    loop {
        let (n, from) = match front.recv_from(&mut buf) { Ok(v) => v, Err(_) => continue };
        let idx = match map.get(&from) {
            Some(i) => *i,
            None => {
                let back = Arc::new(UdpSocket::bind(("127.0.0.1", 0)).unwrap());
                back.connect(("127.0.0.1", server)).unwrap();
                let idx = { let mut c = sh.clients.lock().unwrap(); c.push((from, back.clone())); c.len() - 1 };
                map.insert(from, idx);
                let sh2 = sh.clone();
                std::thread::spawn(move || {
                    let mut rng = Rng(0xD1B54A32D192ED03 ^ (idx as u64 + 1).wrapping_mul(0x9E3779B97F4A7C15));
                    let mut b = [0u8; 65536];
                    loop { if let Ok(n) = back.recv(&mut b) { enqueue(&sh2, &mut rng, delay, jitter, loss, false, idx, &b[..n]); } }
                });
                idx
            }
        };
        enqueue(&sh, &mut rng, delay, jitter, loss, true, idx, &buf[..n]);
    }
}
