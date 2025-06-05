# Based on c_src.mk from erlang.mk by Loic Hoguin <essen@ninenines.eu>

LMDB_VERSION = 0.9.31
LMDB_URL = https://github.com/LMDB/lmdb/archive/LMDB_$(LMDB_VERSION).tar.gz
LMDB_BASE_DIR = lmdb
LMDB_ARCHIVE = $(LMDB_BASE_DIR)/LMDB_$(LMDB_VERSION).tar.gz
LMDB_EXTRACTED_DIR = $(LMDB_BASE_DIR)/lmdb-LMDB_$(LMDB_VERSION)
LMDB_LIB_DIR = $(LMDB_EXTRACTED_DIR)/libraries/liblmdb

CURDIR := $(shell pwd)
BASEDIR := $(abspath $(CURDIR)/..)

PROJECT ?= $(notdir $(BASEDIR))
PROJECT := $(strip $(PROJECT))

ERTS_INCLUDE_DIR ?= $(shell erl -eval 'io:format("~s", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])]), halt().' -noshell)
ERL_INTERFACE_INCLUDE_DIR ?= $(shell erl -eval 'io:format("~s", [code:lib_dir(erl_interface, include)]), halt().' -noshell)
ERL_INTERFACE_LIB_DIR ?= $(shell erl -eval 'io:format("~s", [code:lib_dir(erl_interface, lib)]), halt().' -noshell)

C_SRC_DIR = $(CURDIR)
C_SRC_OUTPUT ?= $(CURDIR)/../priv/$(PROJECT).so

# Compiler settings
CC = gcc
CFLAGS = -fPIC -O2 -std=c99 -finline-functions -Wall -Wmissing-prototypes
CFLAGS += -I$(ERTS_INCLUDE_DIR) -I$(ERL_INTERFACE_INCLUDE_DIR) -I$(LMDB_LIB_DIR)

# Platform detection
UNAME_SYS := $(shell uname -s)
UNAME_ARCH := $(shell uname -m)

# Platform-specific settings
ifeq ($(UNAME_SYS), Darwin)
    # macOS settings
    LDFLAGS = -bundle -flat_namespace -undefined suppress
    # Handle both Intel and Apple Silicon
    ifeq ($(UNAME_ARCH), arm64)
        CFLAGS += -arch arm64
        LDFLAGS += -arch arm64
    else
        CFLAGS += -arch x86_64
        LDFLAGS += -arch x86_64
    endif
    # macOS specific compiler flags
    CFLAGS += -mmacosx-version-min=10.14
    # Use Homebrew paths if available
    ifneq ($(shell command -v brew 2> /dev/null),)
        BREW_PREFIX := $(shell brew --prefix)
        CFLAGS += -I$(BREW_PREFIX)/include
        LDFLAGS += -L$(BREW_PREFIX)/lib
    endif
else ifeq ($(UNAME_SYS), FreeBSD)
    LDFLAGS = -shared -fPIC
    CFLAGS += -fPIC
else ifeq ($(UNAME_SYS), OpenBSD)
    LDFLAGS = -shared -fPIC
    CFLAGS += -fPIC
else ifeq ($(UNAME_SYS), NetBSD)
    LDFLAGS = -shared -fPIC
    CFLAGS += -fPIC
else
    # Linux and other Unix-like systems
    LDFLAGS = -shared -fPIC
    CFLAGS += -fPIC
endif

# Add LMDB library path
LMDB_LIB = $(LMDB_LIB_DIR)/liblmdb.a

# Verbosity.

c_verbose_0 = @echo " C     " $(?F);
c_verbose = $(c_verbose_$(V))

cpp_verbose_0 = @echo " CPP   " $(?F);
cpp_verbose = $(cpp_verbose_$(V))

link_verbose_0 = @echo " LD    " $(@F);
link_verbose = $(link_verbose_$(V))

# Only compile elmdb_nif.c, not the LMDB sources
SOURCES := elmdb_nif.c
OBJECTS = $(SOURCES:.c=.o)

COMPILE_C = $(c_verbose) $(CC) $(CFLAGS) $(CPPFLAGS) -c
COMPILE_CPP = $(cpp_verbose) $(CXX) $(CXXFLAGS) $(CPPFLAGS) -c

.PHONY: all clean

all: $(C_SRC_OUTPUT)

$(C_SRC_OUTPUT): $(OBJECTS) $(LMDB_LIB)
	@mkdir -p $(BASEDIR)/priv/
	$(link_verbose) $(CC) $(OBJECTS) $(LMDB_LIB) $(LDFLAGS) $(LDLIBS) -o $(C_SRC_OUTPUT)

# Download LMDB
$(LMDB_ARCHIVE):
	@echo "Downloading LMDB $(LMDB_VERSION)..."
	@mkdir -p $(LMDB_BASE_DIR)
	@if command -v curl >/dev/null 2>&1; then \
		curl -L -o $@ $(LMDB_URL); \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O $@ $(LMDB_URL); \
	else \
		echo "Error: Neither curl nor wget found. Please install one of them."; \
		exit 1; \
	fi

# Extract LMDB
$(LMDB_EXTRACTED_DIR): $(LMDB_ARCHIVE)
	@echo "Extracting LMDB..."
	@cd $(LMDB_BASE_DIR) && tar -xzf $(notdir $(LMDB_ARCHIVE))
	@touch $@

# Build LMDB
$(LMDB_LIB): $(LMDB_EXTRACTED_DIR)
	@echo "Building LMDB for $(UNAME_SYS) $(UNAME_ARCH)..."
	$(MAKE) -C $(LMDB_LIB_DIR) liblmdb.a CC=$(CC) \
		CFLAGS="$(CFLAGS) -DMDB_USE_ROBUST=0" \
		AR="$(AR)" RANLIB="$(RANLIB)"
	@if [ -f $(LMDB_LIB) ]; then \
		echo "✓ LMDB library built successfully: $(LMDB_LIB)"; \
	else \
		echo "✗ LMDB library not found at: $(LMDB_LIB)"; \
		exit 1; \
	fi

%.o: %.c
	$(COMPILE_C) $(OUTPUT_OPTION) $<

%.o: %.cc
	$(COMPILE_CPP) $(OUTPUT_OPTION) $<

%.o: %.C
	$(COMPILE_CPP) $(OUTPUT_OPTION) $<

%.o: %.cpp
	$(COMPILE_CPP) $(OUTPUT_OPTION) $<

clean:
	@rm -f $(C_SRC_OUTPUT) $(OBJECTS)
	@rm -rf $(LMDB_BASE_DIR)
