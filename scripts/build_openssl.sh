#!/usr/bin/env bash
# =============================================================================
# build_openssl.sh - Build OpenSSL (>= 3.5: native ML-KEM / ML-DSA) into $HOME.
#
#   bash scripts/build_openssl.sh                # normal build (+ test suite)
#   SKIP_TESTS=1 bash scripts/build_openssl.sh   # faster (CI/Docker)
#   FORCE=1      bash scripts/build_openssl.sh   # rebuild over existing install
#
# Fetch pattern = the official OQS fullbuild.sh one-liner:
#   git clone --depth 1 --branch <tag>    (downloads EXACTLY the pinned release)
# To build a different release later: change OPENSSL_TAG in versions.env,
# delete $SRC_ROOT/openssl, then re-run with FORCE=1.
# =============================================================================
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/versions.env"

# Skip if already installed (FORCE=1 overrides).
if [ -x "$OSSL_PREFIX/bin/openssl" ] && [ "${FORCE:-0}" != "1" ]; then
  echo "OpenSSL already installed at $OSSL_PREFIX (set FORCE=1 to rebuild). Skipping."
  exit 0
fi

# Download EXACTLY the pinned release.
mkdir -p "$SRC_ROOT"
cd "$SRC_ROOT"
if [ ! -d openssl ]; then
  git clone --depth 1 --branch "$OPENSSL_TAG" https://github.com/openssl/openssl.git
fi
cd openssl

# Record the exact commit built (reproducibility evidence, brief section 7.3).
mkdir -p "$REPO_ROOT/docs"
git rev-parse HEAD > "$REPO_ROOT/docs/openssl.commit"

# Configure for a $HOME prefix (no sudo, system OpenSSL untouched), then build.
./Configure --prefix="$OSSL_PREFIX" --openssldir="$OSSL_PREFIX/ssl"
make -j"$JOBS"
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  make test
fi
make install_sw install_ssldirs

# Verify PQC is really there (fail loud instead of measuring the wrong library).
export LD_LIBRARY_PATH="$OSSL_PREFIX/lib:$OSSL_PREFIX/lib64:${LD_LIBRARY_PATH:-}"
"$OSSL_PREFIX/bin/openssl" version
"$OSSL_PREFIX/bin/openssl" list -kem-algorithms | grep -qi "ML-KEM" \
  || { echo "ERROR: ML-KEM not found -> this OpenSSL has no PQC."; exit 1; }
"$OSSL_PREFIX/bin/openssl" list -signature-algorithms | grep -qi "ML-DSA" \
  || { echo "ERROR: ML-DSA not found -> this OpenSSL has no PQC."; exit 1; }

echo "DONE. Next step:   source scripts/setenv.sh"
