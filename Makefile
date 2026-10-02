# ==============================================================================
# Skyra - 2D Jetpack Arena Shooter Makefile
# ==============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT_DIR := $(shell pwd)
TOOLS_DIR := $(ROOT_DIR)/tools
BIN_DIR := $(TOOLS_DIR)/bin
GODOT_BIN := $(BIN_DIR)/godot
BUILD_DIR := $(ROOT_DIR)/build
LINUX_BUILD_DIR := $(BUILD_DIR)/linux
STANDALONE_BIN := $(LINUX_BUILD_DIR)/Skyra.x86_64
DIST_DIR := $(BUILD_DIR)/dist
VERSION_FILE := $(TOOLS_DIR)/godot_version.txt
GODOT_VER := $(shell tr -d '[:space:]' < $(VERSION_FILE) 2>/dev/null || echo "4.4.1")
TEMPLATES_DIR := $(HOME)/.local/share/godot/export_templates/$(GODOT_VER).stable
TEMPLATE_RELEASE := $(TEMPLATES_DIR)/linux_release.x86_64

.PHONY: all help setup godot templates build binary dist package run run-windowed run-bin test appimage clean distclean

# ------------------------------------------------------------------------------
# Default / Help
# ------------------------------------------------------------------------------

all: build

help:
	@echo "========================================================================"
	@echo " Skyra - Build & Execution Targets"
	@echo "========================================================================"
	@echo "  make setup         Download engine & Linux export templates if missing"
	@echo "  make build         Build the standalone Linux binary (Skyra.x86_64)"
	@echo "  make dist          Package standalone binary into .tar.gz & .zip for sharing"
	@echo "  make run           Run game from source in fullscreen"
	@echo "  make run-windowed  Run game from source in a 1600x900 window"
	@echo "  make run-bin       Run the compiled standalone binary"
	@echo "  make test          Run the headless test suite (117 self-tests)"
	@echo "  make appimage      Build AppImage package (requires appimagetool)"
	@echo "  make clean         Remove build/ directory"
	@echo "  make distclean     Remove build/ and tools/bin/ directories"
	@echo "========================================================================"

# ------------------------------------------------------------------------------
# Dependencies & Setup
# ------------------------------------------------------------------------------

$(GODOT_BIN):
	@echo "==> Setting up Godot $(GODOT_VER)..."
	@chmod +x $(TOOLS_DIR)/setup_godot.sh
	@$(TOOLS_DIR)/setup_godot.sh

godot: $(GODOT_BIN)

$(TEMPLATE_RELEASE):
	@echo "==> Setting up Linux export templates ($(GODOT_VER))..."
	@chmod +x $(TOOLS_DIR)/install_export_templates.sh
	@$(TOOLS_DIR)/install_export_templates.sh

templates: $(TEMPLATE_RELEASE)

setup: $(GODOT_BIN) $(TEMPLATE_RELEASE)
	@echo "==> All engine and template dependencies are ready."

# ------------------------------------------------------------------------------
# Standalone Binary Build
# ------------------------------------------------------------------------------

build: setup
	@echo "==> Building standalone Linux binary..."
	@mkdir -p $(LINUX_BUILD_DIR)
	@chmod +x $(TOOLS_DIR)/build_linux.sh
	@$(TOOLS_DIR)/build_linux.sh
	@chmod +x $(STANDALONE_BIN)
	@echo ""
	@echo "========================================================================"
	@echo " BUILD SUCCESSFUL!"
	@echo " Standalone binary location:"
	@echo "   $(STANDALONE_BIN)"
	@echo ""
	@echo " To share with a friend on Ubuntu/Linux:"
	@echo "   1. Send them $(STANDALONE_BIN) directly (or run 'make dist' for an archive)."
	@echo "   2. On their Ubuntu machine, they simply run:"
	@echo "        chmod +x Skyra.x86_64"
	@echo "        ./Skyra.x86_64"
	@echo "      No dependencies, engine, or assets needed!"
	@echo "========================================================================"

binary: build

# ------------------------------------------------------------------------------
# Distribution Packaging
# ------------------------------------------------------------------------------

dist: build
	@echo "==> Packaging standalone game for distribution..."
	@mkdir -p $(DIST_DIR)
	@rm -rf $(DIST_DIR)/Skyra-linux-x86_64 $(DIST_DIR)/*.tar.gz $(DIST_DIR)/*.zip
	@mkdir -p $(DIST_DIR)/Skyra-linux-x86_64
	@cp $(STANDALONE_BIN) $(DIST_DIR)/Skyra-linux-x86_64/
	@cp $(ROOT_DIR)/icon.svg $(DIST_DIR)/Skyra-linux-x86_64/
	@echo "Skyra - Standalone Linux Game" > $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "=============================" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "To play on any Ubuntu / Linux system:" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  1. Open a terminal in this folder." >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  2. Ensure execute permissions:" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "       chmod +x Skyra.x86_64" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  3. Launch the game:" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "       ./Skyra.x86_64" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "Default Controls:" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Move: A / D" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Jump / Jetpack: W or Space" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Crouch / Drop down: S" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Aim: Mouse" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Fire: Left Mouse Button" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Grenade: Right Mouse Button or G" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Reload: R" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Switch Weapon: Q or 1 / 2" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Pick up / Swap: E" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Drop Weapon: X" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Pause: Esc / P" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@echo "  - Fullscreen: F11" >> $(DIST_DIR)/Skyra-linux-x86_64/HOW_TO_PLAY.txt
	@cd $(DIST_DIR) && tar -czf Skyra-linux-x86_64.tar.gz Skyra-linux-x86_64
	@cd $(DIST_DIR) && zip -q -r Skyra-linux-x86_64.zip Skyra-linux-x86_64
	@echo "========================================================================"
	@echo " Distribution archives created in $(DIST_DIR):"
	@echo "   - Skyra-linux-x86_64.tar.gz ($$(ls -lh $(DIST_DIR)/Skyra-linux-x86_64.tar.gz | awk '{print $$5}'))"
	@echo "   - Skyra-linux-x86_64.zip    ($$(ls -lh $(DIST_DIR)/Skyra-linux-x86_64.zip | awk '{print $$5}'))"
	@echo " Send either archive to your friend. They just extract and run!"
	@echo "========================================================================"

package: dist

# ------------------------------------------------------------------------------
# Run Targets
# ------------------------------------------------------------------------------

run: $(GODOT_BIN)
	@$(GODOT_BIN) --path $(ROOT_DIR)

run-windowed: $(GODOT_BIN)
	@$(GODOT_BIN) --path $(ROOT_DIR) -- --windowed

run-bin: $(STANDALONE_BIN)
	@$(STANDALONE_BIN)

# ------------------------------------------------------------------------------
# Testing & Packaging Extras
# ------------------------------------------------------------------------------

test: $(GODOT_BIN)
	@$(GODOT_BIN) --headless --path $(ROOT_DIR) -- --selftest

appimage: build
	@chmod +x $(TOOLS_DIR)/make_appimage.sh
	@$(TOOLS_DIR)/make_appimage.sh

# ------------------------------------------------------------------------------
# Cleaning
# ------------------------------------------------------------------------------

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned $(BUILD_DIR)"

distclean: clean
	@rm -rf $(BIN_DIR) .godot/ .sfx_cache/
	@echo "Cleaned build, tools/bin, and caches"
