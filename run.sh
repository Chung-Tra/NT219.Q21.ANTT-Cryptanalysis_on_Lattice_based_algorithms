#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
# Kich hoat OpenSSL PQC cho phien (run_micro.sh cung tu source; lam day cho chac).
# shellcheck disable=SC1091
[ -f scripts/setenv.sh ] && source scripts/setenv.sh >/dev/null 2>&1 || true

# Ghim xung CPU (neu co). Khong co sudo/cpupower -> bo qua, vo hai.
sudo cpupower frequency-set -g performance 2>/dev/null   # VM/container -> bỏ qua
ARCH=$(uname -m)
FAST="rsa 3072;ecdsa p256;ecdsa p384;ecdsa p521;ecdh p256;ecdh p384;ecdh p521;mlkem 512;mlkem 768;mlkem 1024;mldsa 44;mldsa 65;mldsa 87"
SLOW="rsa 7680;rsa 15360"

for i in 1 2 3 4 5; do
  # --- Lượt 1: 13 thuật toán còn lại, 2000 vòng ---
  MICRO_ALGOS="$FAST" BENCH_WARMUP=50 BENCH_ITERS=2000 BENCH_KEYGEN_ITERS=200 make bench
  cp data/summary_micro_${ARCH}.csv data/raw/${ARCH}/summary_batch$i.csv          # header + 13 algo

  # --- Lượt 2: rsa 7680 + rsa 15360, 100 vòng (keygen=3 vì RSA-15360 keygen cực chậm) ---
  MICRO_ALGOS="$SLOW" BENCH_WARMUP=10 BENCH_ITERS=100 BENCH_KEYGEN_ITERS=100 make bench
  tail -n +2 data/summary_micro_${ARCH}.csv >> data/raw/${ARCH}/summary_batch$i.csv   # + 2 algo (bỏ header)
  cp data/raw/${ARCH}/summary_batch$i.csv data/summary_micro_${ARCH}.csv          # canonical = đủ 15

  # --- Archive raw+kv từng thuật toán (cả 2 lượt đều còn ở top-level) ---
  for f in data/raw/${ARCH}/*.raw.csv; do
    [ -e "$f" ] || continue
    a=$(basename "$f" .raw.csv); mkdir -p "data/raw/${ARCH}/$a"
    mv "$f" "data/raw/${ARCH}/$a/batch$i.raw.csv"
    [ -e "data/raw/${ARCH}/$a.kv.txt" ] && mv "data/raw/${ARCH}/$a.kv.txt" "data/raw/${ARCH}/$a/batch$i.kv.txt"
  done
done
