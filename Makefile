# Makefile for claudelegram

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/claudelegram

BUILD_DIR = build/exec
EXECUTABLE = claudelegram
APP_DIR = claudelegram_app

.PHONY: all build install uninstall clean

all: build

build:
	pack build claudelegram

install: build
	@echo "Installing claudelegram to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@mkdir -p $(LIBDIR)
	@# Copy the app directory with all shared libraries
	@cp -r $(BUILD_DIR)/$(APP_DIR)/* $(LIBDIR)/
	@# Create wrapper script that points to installed location
	@echo '#!/bin/sh' > $(BINDIR)/$(EXECUTABLE)
	@echo 'set -e' >> $(BINDIR)/$(EXECUTABLE)
	@echo 'export LD_LIBRARY_PATH="$(LIBDIR):$$LD_LIBRARY_PATH"' >> $(BINDIR)/$(EXECUTABLE)
	@echo 'export DYLD_LIBRARY_PATH="$(LIBDIR):$$DYLD_LIBRARY_PATH"' >> $(BINDIR)/$(EXECUTABLE)
	@echo 'export IDRIS2_INC_SRC="$(LIBDIR)"' >> $(BINDIR)/$(EXECUTABLE)
	@echo '"$(LIBDIR)/claudelegram.so" "$$@"' >> $(BINDIR)/$(EXECUTABLE)
	@chmod +x $(BINDIR)/$(EXECUTABLE)
	@echo "Done. claudelegram installed to $(BINDIR)/$(EXECUTABLE)"

uninstall:
	@echo "Uninstalling claudelegram..."
	@rm -f $(BINDIR)/$(EXECUTABLE)
	@rm -rf $(LIBDIR)
	@echo "Done."

clean:
	@rm -rf build
	@echo "Build artifacts cleaned."
