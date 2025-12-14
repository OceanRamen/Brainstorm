#!/bin/bash

# CPU-only build for Brainstorm (primary, stable path)
echo "======================================="
echo "  Brainstorm CPU Build (ImmolateCPU.dll)"
echo "======================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! command -v x86_64-w64-mingw32-g++ &> /dev/null; then
    echo -e "${RED}✗ MinGW (x86_64-w64-mingw32-g++) not found.${NC}"
    echo "  Install with: sudo apt-get install mingw-w64"
    exit 1
fi

echo -e "${GREEN}✓ MinGW found${NC}"

rm -rf build
mkdir -p build
cd build

set -e

echo -e "\n${YELLOW}Compiling CPU DLL...${NC}"
x86_64-w64-mingw32-g++ \
    -shared \
    -O3 \
    -std=c++17 \
    -DBUILDING_DLL \
    -o ../ImmolateCPU.dll \
    ../src/brainstorm_cpu.cpp \
    ../src/functions.cpp \
    ../src/items.cpp \
    ../src/rng.cpp \
    ../src/seed.cpp \
    ../src/util.cpp \
    -I ../src \
    -static-libgcc \
    -static-libstdc++ \
    -Wl,--export-all-symbols \
    2>&1 | tee build_cpu.log

echo -e "${GREEN}✓ CPU DLL built:${NC} ../ImmolateCPU.dll"

DLL_SIZE=$(du -h ../ImmolateCPU.dll | cut -f1)
echo "  Size: ${DLL_SIZE}"

echo -e "\n${GREEN}CPU build complete.${NC}"
