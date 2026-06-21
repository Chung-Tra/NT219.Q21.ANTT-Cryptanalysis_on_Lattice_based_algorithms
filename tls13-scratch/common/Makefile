# tls13-scratch/common/Makefile -- engine dung chung + self-test fidelity (LINK TINH).
OSSLROOT ?= $(shell bash -c '. ../../scripts/versions.env 2>/dev/null && echo $$OSSL_PREFIX')
ifeq ($(strip $(OSSLROOT)),)
  OSSLROOT := $(HOME)/pqc/openssl
endif
ifneq ($(wildcard $(OSSLROOT)/lib64/libcrypto.a),)
  OSSLLIB := $(OSSLROOT)/lib64
else ifneq ($(wildcard $(OSSLROOT)/lib/libcrypto.a),)
  OSSLLIB := $(OSSLROOT)/lib
endif
ifdef OSSLLIB
  CFLAGS += -I$(OSSLROOT)/include
  OSSL   := $(OSSLLIB)/libcrypto.a -ldl
else
  OSSL   := -lcrypto
endif

# ==============================================================================
# DETECT LIBOQS (Matches your OpenSSL path & fallback architecture)
# ==============================================================================
OQSROOT ?= $(shell bash -c '. ../../scripts/versions.env 2>/dev/null && echo $$OQS_PREFIX')
ifeq ($(strip $(OQSROOT)),)
  OQSROOT := $(HOME)/pqc/liboqs
endif

# Check typical CMake in-tree build locations as well as standard install structures
ifneq ($(wildcard $(OQSROOT)/build/lib/liboqs.a),)
  OQSLIB := $(OQSROOT)/build/lib
else ifneq ($(wildcard $(OQSROOT)/lib/liboqs.a),)
  OQSLIB := $(OQSROOT)/lib
else ifneq ($(wildcard $(OQSROOT)/lib64/liboqs.a),)
  OQSLIB := $(OQSROOT)/lib64
endif

ifdef OQSLIB
  # Include both standard headers and CMake auto-generated headers if applicable
  CFLAGS += -I$(OQSROOT)/include -I$(OQSROOT)/build/include
  OQS    := $(OQSLIB)/liboqs.a
else
  OQS    := -loqs
endif
# ==============================================================================

CFLAGS  += -Wall -Wextra -O2 -pthread
LDLIBS  := -lm

# self-test: tai lap illustrated-tls13/captures/keylog.txt dung tung byte
repro: repro_keylog.c tls13.c tls13.h
	$(CC) $(CFLAGS) -o repro_keylog repro_keylog.c tls13.c $(OSSL) $(OQS) $(LDLIBS)
	./repro_keylog

clean:
	rm -f repro_keylog
.PHONY: repro clean
