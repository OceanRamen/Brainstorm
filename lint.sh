#!/bin/bash

# Lint script for Brainstorm - runs all code quality checks
# This should be run before committing code or building releases

echo "======================================="
echo "  Brainstorm Code Quality Check"
echo "======================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

# Check for required tools
echo -e "\n${YELLOW}Checking for required tools...${NC}"

# Check stylua
if command -v stylua &> /dev/null; then
    echo -e "${GREEN}✓ stylua found${NC}"
else
    echo -e "${RED}✗ stylua not found${NC} - Install with: cargo install stylua"
    ERRORS=$((ERRORS + 1))
fi

# Check luacheck
if command -v luacheck &> /dev/null; then
    echo -e "${GREEN}✓ luacheck found${NC}"
else
    echo -e "${YELLOW}⚠ luacheck not found${NC} - Install with: sudo luarocks install luacheck"
fi

# Check clang-format
if command -v clang-format &> /dev/null; then
    echo -e "${GREEN}✓ clang-format found${NC}"
else
    echo -e "${YELLOW}⚠ clang-format not found${NC} - Install with: sudo apt-get install clang-format"
fi

# Check clang-tidy
if command -v clang-tidy &> /dev/null; then
    echo -e "${GREEN}✓ clang-tidy found${NC}"
else
    echo -e "${YELLOW}⚠ clang-tidy not found${NC} - Install with: sudo apt-get install clang-tidy"
fi

# Run Lua formatting
echo -e "\n${YELLOW}Running Lua formatting...${NC}"
if command -v stylua &> /dev/null; then
    stylua --check . 2>&1 | grep -v "^Diff" | head -20
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ Lua formatting check passed${NC}"
    else
        echo -e "${RED}✗ Lua formatting issues found${NC}"
        echo "  Run 'stylua .' to fix"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ Skipping - stylua not installed${NC}"
fi

# Run Lua linting
echo -e "\n${YELLOW}Running Lua linting...${NC}"
if command -v luacheck &> /dev/null; then
    luacheck . --codes --ranges --no-color 2>&1 | head -20
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ Lua linting passed${NC}"
    else
        echo -e "${YELLOW}⚠ Lua linting warnings found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Skipping - luacheck not installed${NC}"
fi

# Run C++ formatting check
echo -e "\n${YELLOW}Checking C++ formatting...${NC}"
if command -v clang-format &> /dev/null; then
    NEEDS_FORMAT=0
    for file in $(find ImmolateCPP/src -name "*.cpp" -o -name "*.hpp" | head -50); do
        if ! clang-format --dry-run -Werror "$file" 2>/dev/null; then
            NEEDS_FORMAT=1
        fi
    done
    
    if [ $NEEDS_FORMAT -eq 0 ]; then
        echo -e "${GREEN}✓ C++ formatting check passed${NC}"
    else
        echo -e "${RED}✗ C++ formatting issues found${NC}"
        echo "  Run: find ImmolateCPP/src -name '*.cpp' -o -name '*.hpp' | xargs clang-format -i"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ Skipping - clang-format not installed${NC}"
fi

# Optional clang-tidy (informational)
echo -e "\n${YELLOW}Checking clang-tidy (informational)...${NC}"
if command -v clang-tidy &> /dev/null; then
    if [ -f "ImmolateCPP/compile_commands.json" ]; then
        TARGET_FILE=$(find ImmolateCPP/src -name "brainstorm_cpu.cpp" | head -1)
        if [ -n "$TARGET_FILE" ]; then
            if clang-tidy "$TARGET_FILE" --quiet 2>/dev/null; then
                echo -e "${GREEN}✓ clang-tidy completed (no blockers)${NC}"
            else
                echo -e "${YELLOW}⚠ clang-tidy reported findings (see output above)${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ No target file for clang-tidy${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ compile_commands.json not found, skipping clang-tidy${NC}"
    fi
else
    echo -e "${YELLOW}⚠ clang-tidy not installed${NC}"
fi

# Run tests
echo -e "\n${YELLOW}Running basic tests...${NC}"
if [ -f "basic_test.lua" ]; then
    lua basic_test.lua > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Basic tests passed${NC}"
    else
        echo -e "${RED}✗ Basic tests failed${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ basic_test.lua not found${NC}"
fi

# Summary
echo -e "\n${YELLOW}=======================================${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo -e "${YELLOW}=======================================${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS error(s) that must be fixed${NC}"
    echo -e "${YELLOW}=======================================${NC}"
    exit 1
fi
