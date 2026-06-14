# ============================================================================
# NT219 PQC Benchmark - Makefile  (Linux x86_64 / ARM aarch64)
# ----------------------------------------------------------------------------
# Builds the microbenchmark executable  build/bench_evp  from src/*.cpp,
# linking against a custom OpenSSL (>= 3.5) that provides ML-KEM / ML-DSA.
#
# Linking is STATIC: the OpenSSL code (including the default provider that
# carries ML-KEM / ML-DSA in 3.5+) is baked into the binary via libcrypto.a /
# libssl.a. The binary therefore has NO libcrypto.so dependency at run time
# (no LD_LIBRARY_PATH / no rpath needed):
#     ./build/bench_evp rsa 2048
# NOTE: the measurement scripts still invoke the `openssl` COMMAND-LINE tool
# (gen_tls_certs.sh, bench_tls.sh, verify_env.sh ...), which is a separate
# dynamic program -- keep `source scripts/setenv.sh` so that CLI is the 3.6.2 one.
#
# OpenSSL location is read automatically from scripts/versions.env
# (OSSL_PREFIX). Override with:  make OSSLROOT=/path/to/openssl
# Build a debug binary with:     make DEBUG=1
#
# Measurement helpers (call scripts/, do NOT affect how bench_evp is built):
#     make bench       # run the whole algorithm matrix -> data/summary_micro_<arch>.csv
#     make memory      # peak RSS per algorithm        -> data/memory_<arch>.csv
#     make codesize    # code size of crypto libraries -> data/codesize_<arch>.csv
# ============================================================================

# ---- Project layout --------------------------------------------------------
SRCDIR  := src
BINDIR  := build
EXEC    := $(BINDIR)/bench_evp
SOURCES := $(wildcard $(SRCDIR)/*.cpp)
OBJECTS := $(patsubst $(SRCDIR)/%.cpp,$(BINDIR)/%.o,$(SOURCES))

# ---- Toolchain and base flags ----------------------------------------------
# C++ standard is intentionally NOT pinned: modern g++ (GCC 11+) defaults to
# C++17.
# -pthread: enables POSIX threads correctly at BOTH compile and link time
#   (use this, not a bare -lpthread). Harmless if the code is single-threaded.
CXX      ?= g++
WARNINGS := -Wall
# Release = "RelWithDebInfo" for a benchmark:
#   -O3            full optimization (representative timing)
#   -g2            debug symbols -> profile with perf / get crash backtraces
#                  (symbols do NOT slow execution; they only enlarge the file)
#   -DNDEBUG       disable assert() -> clean release timing
RELEASE  := -O3 -g2 -DNDEBUG -fno-strict-aliasing -funroll-loops -fomit-frame-pointer
# Debug = step through with a debugger (NOT for profiling: -O0 is unrepresentative)
DEBUGOPT := -g2 -O0

CXXFLAGS += $(WARNINGS) -pthread
LDFLAGS  += -pthread
# System libraries, placed AFTER the static OpenSSL archive in the link line
# (libcrypto.a pulls in dlopen + libm). -ldl is a harmless no-op on glibc>=2.34.
# If the linker reports missing symbols, add -lz (zlib) and/or -latomic (32-bit).
LDLIBS   += -lm -ldl

# ---- Build mode: release (default) or debug (make DEBUG=1) -----------------
ifdef DEBUG
  CXXFLAGS += $(DEBUGOPT)
  LDFLAGS  += -g
else
  CXXFLAGS += $(RELEASE)
endif

# ---- OpenSSL location (single source of truth: scripts/versions.env) -------
# ROOT_DIR is the absolute directory of THIS Makefile, so `make` works from
# any working directory. OSSLROOT defaults to OSSL_PREFIX from versions.env.
ROOT_DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
OSSLROOT ?= $(shell bash -c '. "$(ROOT_DIR)scripts/versions.env" 2>/dev/null && echo "$$OSSL_PREFIX"')

# Fail loudly if OpenSSL cannot be located, instead of silently linking the
# system OpenSSL (which may lack PQC and cause runtime crypto failures).
ifeq ($(strip $(OSSLROOT)),)
  $(error Cannot determine OSSLROOT. Run make from the repo root, or pass OSSLROOT=/path/to/openssl)
endif

# OpenSSL installs its libraries under lib/ or lib64/ depending on the build.
# Detect which one exists so the static archives below point to the real dir.
ifneq ($(wildcard $(OSSLROOT)/lib64),)
  OSSLLIBDIR := $(OSSLROOT)/lib64
else
  OSSLLIBDIR := $(OSSLROOT)/lib
endif

# Header path (-I). -L is the link-time search path; with the full-path static
# archives below it is only a harmless fallback (the link uses the .a directly,
# so there is no .so to find and no rpath / LD_LIBRARY_PATH at run time).
CPPFLAGS += -I$(OSSLROOT)/include
LDFLAGS  += -L$(OSSLLIBDIR)

# Static OpenSSL archives -- link the .a files explicitly (this is the
# "declare the exact library" form). bench_evp uses libcrypto only; the TLS
# tools also need libssl, listed BEFORE libcrypto (ssl depends on crypto).
OSSL_A     := $(OSSLLIBDIR)/libcrypto.a
OSSL_A_SSL := $(OSSLLIBDIR)/libssl.a $(OSSLLIBDIR)/libcrypto.a

# ---- Targets: build --------------------------------------------------------
.PHONY: all clean distclean
.DEFAULT_GOAL := all

all: $(EXEC)

# Link the executable: object files, then the STATIC OpenSSL archive, then the
# system libraries (libraries after the objects that need them, as the linker
# resolves left-to-right).
$(EXEC): $(OBJECTS)
	$(CXX) $(LDFLAGS) $^ $(OSSL_A) $(LDLIBS) -o $@

# Compile each src/*.cpp into build/*.o (create build/ on demand).
$(BINDIR)/%.o: $(SRCDIR)/%.cpp
	@mkdir -p $(BINDIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

# Remove build artifacts.
clean:
	rm -rf $(BINDIR)

# Remove build artifacts plus generated analysis output.
distclean: clean
	rm -rf analysis_out *.log core

# ---- Targets: measurement helpers (WP5) ------------------------------------
# Thin wrappers over scripts/. They never change how bench_evp is compiled;
# the "per algorithm" view comes from arguments, exactly like the official
# liboqs speed_kem/speed_sig and `openssl speed` tools.
.PHONY: bench memory codesize

# Run the whole algorithm matrix -> raw CSVs + data/summary_micro_<arch>.csv
bench: $(EXEC)
	scripts/run_micro.sh

# Peak RSS per algorithm via GNU time -v -> data/memory_<arch>.csv
memory: $(EXEC)
	scripts/measure_memory.sh

# Code size of built crypto libraries via `size` -> data/codesize_<arch>.csv
codesize:
	scripts/measure_codesize.sh

# ---- Targets: WP4 + analysis (additive; wrappers like bench/memory/codesize)
.PHONY: tls analyze

# TLS 1.3 handshake matrix (cert x group) -> data/tls_handshake_<arch>.csv
tls:
	scripts/bench_tls.sh

# Aggregate all CSVs into tables + charts -> analysis_out/
analyze:
	python3 scripts/analyze.py

# ---- Target: self-implemented HTTPS server (brief 7.6; additive) -----------
.PHONY: tlsmini
tlsmini: $(BINDIR)/tls_mini_server

$(BINDIR)/tls_mini_server: $(SRCDIR)/tls_mini_server.c
	@mkdir -p $(BINDIR)
	$(CC) $(CPPFLAGS) -Wall -O2 -o $@ $< $(LDFLAGS) $(OSSL_A_SSL) $(LDLIBS)

# ---- Target: self-implemented TLS timing client (WP4; additive) ------------
.PHONY: tlsclient
tlsclient: $(BINDIR)/tls_timer_client

$(BINDIR)/tls_timer_client: $(SRCDIR)/tls_timer_client.c
	@mkdir -p $(BINDIR)
	$(CC) $(CPPFLAGS) -Wall -O2 -o $@ $< $(LDFLAGS) $(OSSL_A_SSL) $(LDLIBS)
