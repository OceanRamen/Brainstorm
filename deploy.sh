#!/bin/bash

# Deploy Brainstorm mod to Balatro folder
# Target: C:\Users\Krish\AppData\Roaming\Balatro\Mods\Brainstorm

# Convert Windows path to WSL path
TARGET="/mnt/c/Users/Krish/AppData/Roaming/Balatro/Mods/Brainstorm"
TARGET="${TARGET%/}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Brainstorm v3.0 Deployment Script${NC}"
echo -e "${YELLOW}========================================${NC}"

# Check if we're in the right directory
if [ ! -f "lovely.toml" ]; then
    echo -e "${RED}✗${NC} Error: Not in Brainstorm directory"
    echo "Please run from the root of the Brainstorm repository"
    exit 1
fi

# Create target directory structure
echo -e "\n${YELLOW}Creating directory structure...${NC}"
mkdir -p "$TARGET"
mkdir -p "$TARGET/Core"
mkdir -p "$TARGET/UI"

DEPLOY_GPU=${DEPLOY_GPU:-0}
CLEAN_TARGET=${CLEAN_TARGET:-0}

if [ "$CLEAN_TARGET" = "1" ]; then
    echo -e "\n${YELLOW}Cleaning existing Brainstorm files in target...${NC}"
    rm -rf "$TARGET/Core" "$TARGET/UI"
    rm -f "$TARGET"/Immolate*.dll "$TARGET/config.lua" \
          "$TARGET/lovely.toml" "$TARGET/nativefs.lua" "$TARGET/steamodded_compat.lua" \
          "$TARGET/seed_filter.ptx" "$TARGET/seed_filter.fatbin" "$TARGET/gpu_worker.exe" \
          "$TARGET/gpu_driver.log" "$TARGET/brainstorm.log"
    mkdir -p "$TARGET/Core" "$TARGET/UI"
fi

# Always rebuild CPU DLL before deploy
echo -e "\n${YELLOW}Building CPU DLL...${NC}"
if (cd ImmolateCPP && ./build_cpu.sh); then
    echo -e "${GREEN}✓${NC} CPU build complete"
else
    echo -e "${RED}✗${NC} CPU build failed"
    exit 1
fi

# Deploy CPU DLL (default)
echo -e "\n${YELLOW}Deploying CPU DLL...${NC}"
if [ -f "ImmolateCPU.dll" ]; then
    DLL_SIZE=$(du -h "ImmolateCPU.dll" | cut -f1)
    if cp "ImmolateCPU.dll" "$TARGET/ImmolateCPU.dll"; then
        echo -e "${GREEN}✓${NC} Deployed CPU DLL (${DLL_SIZE})"
    else
        echo -e "${RED}✗${NC} Failed to copy CPU DLL (permission denied?)"
        echo "Ensure WSL can write to $TARGET (may require elevated shell or mount options)."
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Error: ImmolateCPU.dll not found!"
    echo "Build it with: cd ImmolateCPP && ./build_cpu.sh"
    echo "Or fallback: cd ImmolateCPP && ./build_simple.sh"
    exit 1
fi

# Optional: deploy experimental GPU build when requested
if [ "$DEPLOY_GPU" = "1" ]; then
    echo -e "\n${YELLOW}Deploying experimental GPU DLL...${NC}"
    if [ -f "ImmolateCUDA.dll" ]; then
        CUDA_SIZE=$(du -h "ImmolateCUDA.dll" | cut -f1)
        if cp "ImmolateCUDA.dll" "$TARGET/ImmolateCUDA.dll"; then
            echo -e "${GREEN}✓${NC} Deployed GPU DLL (${CUDA_SIZE})"
        else
            echo -e "${YELLOW}⚠${NC} Could not copy ImmolateCUDA.dll (permission denied?)"
        fi

        if [ -f "seed_filter.ptx" ]; then
            if cp "seed_filter.ptx" "$TARGET/seed_filter.ptx"; then
                echo -e "${GREEN}✓${NC} Deployed CUDA kernel (PTX)"
            fi
        fi
        if [ -f "seed_filter.fatbin" ]; then
            if cp "seed_filter.fatbin" "$TARGET/seed_filter.fatbin"; then
                echo -e "${GREEN}✓${NC} Deployed CUDA kernel (fatbin)"
            fi
        fi
        if [ -f "gpu_worker.exe" ]; then
            if cp "gpu_worker.exe" "$TARGET/gpu_worker.exe"; then
                echo -e "${GREEN}✓${NC} Deployed GPU worker process"
            fi
        fi
    else
        echo -e "${YELLOW}⚠${NC} Skipping GPU deploy: ImmolateCUDA.dll not found"
        echo "Build with: cd ImmolateCPP && ./build_gpu.sh"
    fi
else
    if [ -f "ImmolateCUDA.dll" ]; then
        echo -e "${YELLOW}ℹ${NC} GPU build present but not deployed (set DEPLOY_GPU=1 to include)"
    fi
fi

# Core mod files
echo -e "\n${YELLOW}Deploying core files...${NC}"
CORE_FILES=(
    "Core/Brainstorm.lua"
    "Core/logger.lua"
    "UI/ui.lua"
    "config.lua"
    "lovely.toml"
    "nativefs.lua"
    "steamodded_compat.lua"
)

for file in "${CORE_FILES[@]}"; do
    if [ -f "$file" ]; then
        dir=$(dirname "$file")
        if [ "$dir" != "." ]; then
            mkdir -p "$TARGET/$dir"
        fi
        if cp "$file" "$TARGET/$file"; then
            echo -e "${GREEN}✓${NC} Deployed: $file"
        else
            echo -e "${RED}✗${NC} Failed to copy $file (permission denied?)"
            echo "Ensure WSL can write to $TARGET."
            exit 1
        fi
    else
        echo -e "${RED}✗${NC} Missing required file: $file"
        exit 1
    fi
done

# Documentation files
echo -e "\n${YELLOW}Deploying documentation...${NC}"
DOC_FILES=(
    "README.md"
    "CLAUDE.md"
)

for file in "${DOC_FILES[@]}"; do
    if [ -f "$file" ]; then
        if cp "$file" "$TARGET/$file"; then
            echo -e "${GREEN}✓${NC} Deployed: $file"
        else
            echo -e "${YELLOW}⚠${NC} Could not copy $file (permission denied?)"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Documentation missing: $file"
    fi
done

# Optional utility files (not required for runtime)
echo -e "\n${YELLOW}Checking optional utilities...${NC}"
OPTIONAL_FILES=(
    "analyze_logs.lua"
    "run_tests.lua"
)

for file in "${OPTIONAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${YELLOW}ℹ${NC} Available but not deployed: $file"
    fi
done

# Check if tests directory exists
if [ -d "tests" ]; then
    echo -e "${YELLOW}ℹ${NC} Test suite available in tests/ (not deployed)"
fi

# Verify deployment
echo -e "\n${YELLOW}Verifying deployment...${NC}"
REQUIRED_COUNT=0
DEPLOYED_COUNT=0

for file in "${CORE_FILES[@]}"; do
    REQUIRED_COUNT=$((REQUIRED_COUNT + 1))
    if [ -f "$TARGET/$file" ]; then
        DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1))
    fi
done

if [ $DEPLOYED_COUNT -eq $REQUIRED_COUNT ]; then
    echo -e "${GREEN}✓${NC} All core files deployed successfully ($DEPLOYED_COUNT/$REQUIRED_COUNT)"
else
    echo -e "${RED}✗${NC} Deployment incomplete ($DEPLOYED_COUNT/$REQUIRED_COUNT)"
    exit 1
fi

# Configuration check
echo -e "\n${YELLOW}Configuration status:${NC}"
if [ -f "$TARGET/config.lua" ]; then
    # Check if debug is enabled
    if grep -q "debug_enabled.*true" "$TARGET/config.lua"; then
        echo -e "${YELLOW}ℹ${NC} Debug mode is ENABLED (logs will be written to brainstorm.log)"
    else
        echo -e "${GREEN}✓${NC} Debug mode is disabled (production mode)"
    fi
    
    # Check if experimental GPU is enabled
    if grep -q "use_gpu_experimental.*true" "$TARGET/config.lua"; then
        echo -e "${YELLOW}ℹ${NC} Experimental GPU is ENABLED (ImmolateCUDA.dll expected)"
    else
        echo -e "${YELLOW}ℹ${NC} Experimental GPU is disabled (CPU-only mode)"
    fi
fi

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Mod installed at: ${YELLOW}C:\\Users\\Krish\\AppData\\Roaming\\Balatro\\Mods\\Brainstorm${NC}"
echo ""
echo "In-game controls:"
echo "  Ctrl+T - Open Brainstorm settings"
echo "  Ctrl+R - Manual reroll"
echo "  Ctrl+A - Toggle auto-reroll"
echo "  Z+1-5  - Save state to slot"
echo "  X+1-5  - Load state from slot"
echo ""

# Check for updates that might be needed
if [ -f "ImmolateCPP/src/brainstorm_unified.cpp" ]; then
    if [ "ImmolateCPP/src/brainstorm_unified.cpp" -nt "Immolate.dll" ]; then
        echo -e "${YELLOW}⚠ Note:${NC} DLL source is newer than compiled DLL"
        echo "  Consider rebuilding: cd ImmolateCPP && ./build_gpu.sh"
    fi
fi

# Development tips
if [ -f "$TARGET/Core/logger.lua" ]; then
    echo "Debug tips:"
    echo "  - Enable debug mode in settings for detailed logging"
    echo "  - Logs are saved to: %AppData%\\Roaming\\Balatro\\Mods\\Brainstorm\\brainstorm.log"
    echo "  - Analyze logs with: lua analyze_logs.lua brainstorm.log"
fi

echo ""
echo -e "${GREEN}Happy seed hunting!${NC} 🎰"
