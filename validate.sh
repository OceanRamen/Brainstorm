#!/bin/bash
# Pre-deployment validation script
# Run this BEFORE deploying to catch issues early

set -e  # Exit on any error

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "  Brainstorm Pre-Deployment Validation"
echo "========================================"

ERRORS=0
WARNINGS=0
VALIDATE_GPU=${VALIDATE_GPU:-0}

# Check if DLL exists
echo -e "\n[1/7] Checking DLL..."
if [ -f "Immolate.dll" ]; then
    SIZE=$(stat -c%s "Immolate.dll" 2>/dev/null || stat -f%z "Immolate.dll" 2>/dev/null || echo 0)
    SIZE_MB=$(echo "scale=2; $SIZE/1048576" | bc)
    echo -e "${GREEN}✓${NC} DLL found (${SIZE_MB} MB)"
    
    if (( $(echo "$SIZE_MB < 2.0" | bc -l) )); then
        echo -e "${YELLOW}⚠${NC} Warning: DLL seems small, might be missing features"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${RED}✗${NC} DLL not found! Build it first."
    ERRORS=$((ERRORS + 1))
fi

if [ "$VALIDATE_GPU" = "1" ]; then
    echo -e "\n[1b/7] Checking GPU DLL (experimental)..."
    if [ -f "ImmolateCUDA.dll" ]; then
        CUDA_SIZE=$(stat -c%s "ImmolateCUDA.dll" 2>/dev/null || stat -f%z "ImmolateCUDA.dll" 2>/dev/null || echo 0)
        CUDA_MB=$(echo "scale=2; $CUDA_SIZE/1048576" | bc)
        echo -e "${GREEN}✓${NC} GPU DLL found (${CUDA_MB} MB)"
    else
        echo -e "${YELLOW}⚠${NC} ImmolateCUDA.dll not found (GPU checks skipped)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi

# Run Lua syntax checks
echo -e "\n[2/7] Checking Lua syntax..."
for file in Core/*.lua UI/*.lua *.lua; do
    if [ -f "$file" ]; then
        if lua -l ${file%%.lua} 2>/dev/null || lua5.1 -l ${file%%.lua} 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $file"
        else
            # Try just parsing
            if luac -p "$file" 2>/dev/null || luac5.1 -p "$file" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} $file (syntax OK)"
            else
                echo -e "${RED}✗${NC} $file has syntax errors!"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    fi
done

# Run stylua check
echo -e "\n[3/7] Checking code formatting..."
if command -v stylua &> /dev/null; then
    if stylua --check . 2>/dev/null; then
        echo -e "${GREEN}✓${NC} All Lua files properly formatted"
    else
        echo -e "${YELLOW}⚠${NC} Some files need formatting (run: stylua .)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${YELLOW}⚠${NC} stylua not installed, skipping format check"
    WARNINGS=$((WARNINGS + 1))
fi

# Compile and run C++ DLL test if possible
echo -e "\n[4/7] Testing DLL with C++ harness..."
if command -v x86_64-w64-mingw32-g++ &> /dev/null && [ -f "test_dll.cpp" ]; then
    echo "Compiling test harness..."
    if x86_64-w64-mingw32-g++ -o test_dll.exe test_dll.cpp -static 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Test harness compiled"
        
        # Run under Wine if available
        if command -v wine &> /dev/null; then
            echo "Running DLL tests under Wine..."
            if timeout 10 wine test_dll.exe Immolate.dll 2>/dev/null | grep -q "SUCCESS"; then
                echo -e "${GREEN}✓${NC} DLL tests passed"
            else
                echo -e "${RED}✗${NC} DLL tests failed or crashed!"
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo -e "${YELLOW}⚠${NC} Wine not installed, can't run Windows exe"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo -e "${YELLOW}⚠${NC} Could not compile test harness"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "${YELLOW}⚠${NC} MinGW compiler not found, skipping C++ test"
    WARNINGS=$((WARNINGS + 1))
fi

# Run LuaJIT FFI test if available
echo -e "\n[5/7] Testing DLL with LuaJIT FFI..."
if command -v luajit &> /dev/null && [ -f "test_ffi.lua" ]; then
    if timeout 10 luajit test_ffi.lua 2>/dev/null | grep -q "SUCCESS"; then
        echo -e "${GREEN}✓${NC} FFI tests passed"
    else
        echo -e "${RED}✗${NC} FFI tests failed!"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠${NC} LuaJIT not installed, skipping FFI test"
    echo "  (This is the same FFI that Balatro uses!)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for GPU driver log issues
echo -e "\n[6/7] Checking for known issues..."
if [ -f "gpu_driver.log" ]; then
    if grep -q "invalid device context\|CUDA_ERROR" gpu_driver.log 2>/dev/null; then
        echo -e "${RED}✗${NC} GPU driver log contains errors!"
        tail -5 gpu_driver.log
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}✓${NC} No errors in GPU driver log"
    fi
fi

# Run basic Lua tests
echo -e "\n[7/7] Running basic tests..."
if lua basic_test.lua 2>/dev/null | grep -q "Tests Complete"; then
    echo -e "${GREEN}✓${NC} Basic tests passed"
else
    echo -e "${RED}✗${NC} Basic tests failed!"
    ERRORS=$((ERRORS + 1))
fi

# Summary
echo -e "\n========================================"
echo "  VALIDATION SUMMARY"
echo "========================================"

if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}[READY]${NC} All checks passed! Safe to deploy."
        echo -e "\nRun: ${GREEN}./deploy.sh${NC}"
    else
        echo -e "${YELLOW}[READY WITH WARNINGS]${NC} $WARNINGS warnings found."
        echo "The mod should work but consider fixing warnings."
        echo -e "\nRun: ${GREEN}./deploy.sh${NC}"
    fi
    exit 0
else
    echo -e "${RED}[NOT READY]${NC} $ERRORS errors found!"
    echo "Fix these issues before deploying to avoid crashes."
    
    # Suggest fixes
    echo -e "\nSuggested fixes:"
    echo "1. Rebuild CPU DLL: cd ImmolateCPP && ./build_cpu.sh"
    echo "   (Optional GPU rebuild: ./build_gpu.sh)"
    echo "2. Format code: stylua ."
    echo "3. Check logs: tail -20 gpu_driver.log"
    echo "4. Run tests: lua basic_test.lua"
    
    exit 1
fi
