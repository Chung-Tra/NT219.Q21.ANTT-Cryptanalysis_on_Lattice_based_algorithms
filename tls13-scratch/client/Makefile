# tls13-scratch/client/Makefile -- TLS 1.3 client tu cuon protocol (track D, NT219).
# LINK TINH libcrypto.a va liboqs.a. Cung style illustrated-tls13.

OSSLROOT ?= $(shell bash -c '. ../../scripts/versions.env 2>/dev/null && echo $$OSSL_PREFIX')
ifeq ($(strip $(OSSLROOT)),)
  OSSLROOT := $(HOME)/pqc/openssl
endif

# --- Added: Path tracking for liboqs ---
OQSROOT ?= $(HOME)/pqc/liboqs

ifneq ($(wildcard $(OSSLROOT)/lib64/libcrypto.a),)
  OSSLLIB := $(OSSLROOT)/lib64
  else ifneq ($(wildcard $(OSSLROOT)/lib/libcrypto.a),)
  OSSLLIB := $(OSSLROOT)/lib
endif

# --- Added: Look for liboqs.a inside build directory or root lib paths ---
ifneq ($(wildcard $(OQSROOT)/build/lib/liboqs.a),)
  OQSLIB := $(OQSROOT)/build/lib
else ifneq ($(wildcard $(OQSROOT)/lib/liboqs.a),)
  OQSLIB := $(OQSROOT)/lib
else ifneq ($(wildcard $(OQSROOT)/lib64/liboqs.a),)
  OQSLIB := $(OQSROOT)/lib64
endif

ifdef OSSLLIB
  CFLAGS += -I$(OSSLROOT)/include
  OSSL   := $(OSSLLIB)/libcrypto.a -ldl
else
  OSSL   := -lcrypto
endif

# --- Added: If liboqs library paths exist, include headers and map static archive ---
ifdef OQSLIB
  CFLAGS += -I$(OQSROOT)/include
  OQS    := $(OQSLIB)/liboqs.a
else
  OQS    := -loqs
endif

COMMON  := ../common
CFLAGS  += -I$(COMMON) -Wall -Wextra -O2 -pthread
LDLIBS  := -lm

# --- Modified: Included $(OQS) variable into the link line ---
client: client.c $(COMMON)/tls13.c $(COMMON)/tls13.h
	$(CC) $(CFLAGS) -o client client.c $(COMMON)/tls13.c $(OSSL) $(OQS) $(LDLIBS)

clean:
	rm -f client
.PHONY: clean
