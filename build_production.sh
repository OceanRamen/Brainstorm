#!/bin/bash

# Production build script for Brainstorm
# Runs all quality checks, tests, and builds optimized release

echo "╔════════════════════════════════════════╗"
echo "║   Brainstorm Production Build v3.0    ║"
echo "╚════════════════════════════════════════╝"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Track if we should continue
CONTINUE=true

# Step 1: Code Quality Checks
echo -e "\n${BLUE}━━━ Step 1: Code Quality ━━━${NC}"

# Format Lua code
echo "Formatting Lua code..."
if command -v stylua &> /dev/null; then
    stylua .
    echo -e "${GREEN}✓ Lua code formatted${NC}"
else
    echo -e "${YELLOW}⚠ stylua not found, skipping Lua formatting${NC}"
fi

# Format C++ code
echo "Formatting C++ code..."
if command -v clang-format &> /dev/null; then
    find ImmolateCPP/src -name "*.cpp" -o -name "*.hpp" | xargs clang-format -i
    echo -e "${GREEN}✓ C++ code formatted${NC}"
else
    echo -e "${YELLOW}⚠ clang-format not found, skipping C++ formatting${NC}"
fi

# Run lint checks
echo "Running lint checks..."
if [ -f "lint.sh" ]; then
    ./lint.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Lint checks failed${NC}"
        CONTINUE=false
    fi
else
    echo -e "${YELLOW}⚠ lint.sh not found${NC}"
fi

# Step 2: Run Tests
echo -e "\n${BLUE}━━━ Step 2: Testing ━━━${NC}"

# Basic tests
echo "Running basic tests..."
if [ -f "basic_test.lua" ]; then
    lua basic_test.lua
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Basic tests failed${NC}"
        CONTINUE=false
    else
        echo -e "${GREEN}✓ Basic tests passed${NC}"
    fi
fi

# Comprehensive tests
echo "Running comprehensive tests..."
if [ -f "test_suite.lua" ]; then
    lua test_suite.lua > test_results.txt 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Comprehensive tests passed${NC}"
    else
        echo -e "${YELLOW}⚠ Some tests failed (see test_results.txt)${NC}"
    fi
fi

# Step 3: Build DLL
echo -e "\n${BLUE}━━━ Step 3: Building DLL ━━━${NC}"

if [ "$CONTINUE" = true ]; then
    cd ImmolateCPP
    
    # Clean previous builds
    rm -f ../ImmolateCPU.dll build/*.o
    
    echo "Building CPU-only version..."
    if [ -f "build_cpu.sh" ]; then
        ./build_cpu.sh
        BUILD_RESULT=$?
    else
        echo "build_cpu.sh not found, falling back to build_simple.sh"
        ./build_simple.sh
        BUILD_RESULT=$?
    fi
    
    cd ..
    
    if [ $BUILD_RESULT -eq 0 ]; then
        echo -e "${GREEN}✓ DLL build successful${NC}"
        ls -lh ImmolateCPU.dll
    else
        echo -e "${RED}✗ DLL build failed${NC}"
        CONTINUE=false
    fi
else
    echo -e "${YELLOW}⚠ Skipping build due to previous errors${NC}"
fi

# Step 4: Verify Build
echo -e "\n${BLUE}━━━ Step 4: Build Verification ━━━${NC}"

if [ "$CONTINUE" = true ]; then
    # Check DLL size
    if [ -f "Immolate.dll" ]; then
        DLL_SIZE=$(stat -c%s "Immolate.dll" 2>/dev/null || stat -f%z "Immolate.dll" 2>/dev/null)
        if [ "$DLL_SIZE" -gt 2000000 ] && [ "$DLL_SIZE" -lt 10000000 ]; then
            echo -e "${GREEN}✓ DLL size OK: $(($DLL_SIZE / 1048576))MB${NC}"
        else
            echo -e "${RED}✗ DLL size suspicious: $(($DLL_SIZE / 1048576))MB${NC}"
        fi
    fi
    
    # Check all required files exist
    REQUIRED_FILES=(
        "Core/Brainstorm.lua"
        "Core/logger.lua"
        "UI/ui.lua"
        "config.lua"
        "Immolate.dll"
        "README.md"
        "CLAUDE.md"
    )
    
    MISSING=0
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$file" ]; then
            echo -e "${RED}✗ Missing: $file${NC}"
            MISSING=$((MISSING + 1))
        fi
    done
    
    if [ $MISSING -eq 0 ]; then
        echo -e "${GREEN}✓ All required files present${NC}"
    else
        echo -e "${RED}✗ Missing $MISSING required files${NC}"
        CONTINUE=false
    fi
fi

# Step 5: Create Release Package
echo -e "\n${BLUE}━━━ Step 5: Release Package ━━━${NC}"

if [ "$CONTINUE" = true ]; then
    RELEASE_DIR="release/Brainstorm_v3.0"
    INCLUDE_GPU=${INCLUDE_GPU:-0}
    echo "Creating release package..."
    
    # Clean and create release directory
    rm -rf release
    mkdir -p "$RELEASE_DIR"
    
    # Copy files
    cp -r Core "$RELEASE_DIR/"
    cp -r UI "$RELEASE_DIR/"
    cp config.lua "$RELEASE_DIR/"
    cp ImmolateCPU.dll "$RELEASE_DIR/"
    cp README.md "$RELEASE_DIR/"
    cp lovely.toml "$RELEASE_DIR/" 2>/dev/null
    cp nativefs.lua "$RELEASE_DIR/" 2>/dev/null
    cp steamodded_compat.lua "$RELEASE_DIR/" 2>/dev/null

    if [ "$INCLUDE_GPU" = "1" ]; then
        if [ -f "ImmolateCUDA.dll" ]; then
            cp ImmolateCUDA.dll "$RELEASE_DIR/"
        fi
        if ls seed_filter.* > /dev/null 2>&1; then
            cp seed_filter.* "$RELEASE_DIR/" 2>/dev/null
        fi
        if [ -f "gpu_worker.exe" ]; then
            cp gpu_worker.exe "$RELEASE_DIR/" 2>/dev/null
        fi
    fi
    
    # Create version file
    echo "3.0.0" > "$RELEASE_DIR/VERSION"
    date >> "$RELEASE_DIR/VERSION"
    
    # Create zip
    cd release
    zip -r Brainstorm_v3.0.zip Brainstorm_v3.0 > /dev/null
    cd ..
    
    echo -e "${GREEN}✓ Release package created: release/Brainstorm_v3.0.zip${NC}"
    ls -lh release/Brainstorm_v3.0.zip
fi

# Final Summary
echo -e "\n${BLUE}━━━ Build Summary ━━━${NC}"

if [ "$CONTINUE" = true ]; then
    echo -e "${GREEN}✅ Production build successful!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Test the release package"
    echo "  2. Deploy with: ./deploy.sh"
    echo "  3. Upload release/Brainstorm_v3.0.zip to GitHub"
    exit 0
else
    echo -e "${RED}❌ Build failed - please fix errors above${NC}"
    exit 1
fi
