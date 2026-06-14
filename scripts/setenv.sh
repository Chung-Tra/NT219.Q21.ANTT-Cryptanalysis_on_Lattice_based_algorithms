#!/usr/bin/env bash
# =============================================================================
# setenv.sh - Activate the custom OpenSSL (with PQC) for the CURRENT shell.
# Follows the official OpenSSL demos convention: libraries are found at run
# time via LD_LIBRARY_PATH (no rpath baked into binaries).
#
# IMPORTANT: source it, do NOT execute it:
#     source scripts/setenv.sh
# =============================================================================
# DESIGN NOTES
#   - Must be SOURCED, never executed: env vars set in a child process vanish
#     with it. Quick check after sourcing: `which openssl` -> $OSSL_PREFIX/bin.
#   - No rpath anywhere in this project (matches the official OpenSSL demos
#     convention): the library is found at RUN time via LD_LIBRARY_PATH set
#     here, keeping binaries relocatable and the mechanism explicit.
#   - Handles both lib/ and lib64/ (OpenSSL picks one per platform).
#   Verified: activating then `openssl version` -> 3.6.2 (not system 3.0).
_SETENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SETENV_DIR/versions.env"

export PATH="$OSSL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$OSSL_PREFIX/lib:$OSSL_PREFIX/lib64:${LD_LIBRARY_PATH:-}"

echo "Activated OpenSSL from: $OSSL_PREFIX"
"$OSSL_PREFIX/bin/openssl" version 2>/dev/null \
  || echo "(openssl not built yet at $OSSL_PREFIX - run scripts/build_openssl.sh)"
