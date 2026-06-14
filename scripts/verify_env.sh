#!/usr/bin/env bash
# =============================================================================
# verify_env.sh - Verify the environment AND write the environment report.
# Satisfies brief section 7.3: "Document compiler versions (gcc/clang), flags
# (-O2/-O3 ...), and CPU governor settings."  Report: docs/env_report_<arch>.txt
# Exits non-zero if the custom OpenSSL or its PQC algorithms are missing
# (the anti crypto-failure gate: fail loud, never measure the wrong library).
# =============================================================================
# DESIGN NOTES
#   - Two roles: (1) GATE against the classic crypto-failure (silently using
#     system OpenSSL without ML-KEM/ML-DSA -> exit 1 with fix hint);
#     (2) EVIDENCE: answers the brief 7.3 verbatim requirement "Document
#     compiler versions (gcc/clang), flags, and CPU governor settings".
#   - Governor read from /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
#     (Linux kernel cpufreq sysfs, admin-guide/pm/cpufreq).
#   - Run on EVERY machine -> docs/env_report_<arch>.txt per platform.
#   Verified live: OpenSSL 3.0 -> FAIL path; PQC build -> PASS + report.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
source "$HERE/versions.env"

ARCH="$(uname -m)"
REPORT="$REPO_ROOT/docs/env_report_${ARCH}.txt"
mkdir -p "$REPO_ROOT/docs"

# --- Hard checks (gate) -------------------------------------------------------
[ -x "$OSSL_PREFIX/bin/openssl" ] \
  || { echo "FAIL: no openssl at $OSSL_PREFIX. Run scripts/build_openssl.sh"; exit 1; }
export LD_LIBRARY_PATH="$OSSL_PREFIX/lib:$OSSL_PREFIX/lib64:${LD_LIBRARY_PATH:-}"

OSSL_VER="$("$OSSL_PREFIX/bin/openssl" version)"
KEMS=$("$OSSL_PREFIX/bin/openssl" list -kem-algorithms        | grep -ci "ML-KEM" || true)
SIGS=$("$OSSL_PREFIX/bin/openssl" list -signature-algorithms  | grep -ci "ML-DSA" || true)
[ "$KEMS" -ge 1 ] || { echo "FAIL: ML-KEM not available in $OSSL_VER"; exit 1; }
[ "$SIGS" -ge 1 ] || { echo "FAIL: ML-DSA not available in $OSSL_VER"; exit 1; }

# --- Soft facts (documented, not fatal) ---------------------------------------
GOV_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
GOVERNOR="$( [ -r "$GOV_FILE" ] && cat "$GOV_FILE" || echo "unavailable (container/VM)" )"
RELEASE_FLAGS="$(grep -E '^RELEASE' "$REPO_ROOT/Makefile" 2>/dev/null || echo 'RELEASE flags: (Makefile not found)')"

# --- Write the report ----------------------------------------------------------
{
  echo "# Environment report  ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo "uname        : $(uname -a)"
  echo "gcc          : $(gcc --version | head -1)"
  echo "cmake        : $(cmake --version 2>/dev/null | head -1 || echo 'not installed')"
  echo "perl         : $(perl -e 'print $^V')"
  echo "cpu governor : $GOVERNOR"
  echo "openssl      : $OSSL_VER   (prefix: $OSSL_PREFIX)"
  echo "ML-KEM algos : $KEMS    ML-DSA algos: $SIGS"
  echo "openssl commit: $(cat "$REPO_ROOT/docs/openssl.commit" 2>/dev/null || echo 'n/a')"
  echo "liboqs commit : $(cat "$REPO_ROOT/docs/liboqs.commit"  2>/dev/null || echo 'n/a (WP3 not built)')"
  echo "build flags  : $RELEASE_FLAGS"
} | tee "$REPORT"

echo "PASS. Report written to: $REPORT"
