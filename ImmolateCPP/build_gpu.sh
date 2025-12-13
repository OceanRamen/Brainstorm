#!/bin/bash

# Build script for GPU-accelerated Brainstorm DLL
# Supports both CPU-only and GPU+CPU builds

echo "======================================="
echo "  Brainstorm GPU Build Script v1.0 (experimental)"
echo "======================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for CUDA
CUDA_AVAILABLE=0
NVCC_PATH=""

if command -v nvcc &> /dev/null; then
    NVCC_PATH=$(which nvcc)
    CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $6}' | cut -c2-)
    echo -e "${GREEN}✓ CUDA found:${NC} version $CUDA_VERSION at $NVCC_PATH"
    CUDA_AVAILABLE=1
elif [ -f "/usr/local/cuda/bin/nvcc" ]; then
    NVCC_PATH="/usr/local/cuda/bin/nvcc"
    CUDA_VERSION=$($NVCC_PATH --version | grep "release" | awk '{print $6}' | cut -c2-)
    echo -e "${GREEN}✓ CUDA found:${NC} version $CUDA_VERSION at $NVCC_PATH"
    CUDA_AVAILABLE=1
elif [ -f "/usr/local/cuda-12.6/bin/nvcc" ]; then
    NVCC_PATH="/usr/local/cuda-12.6/bin/nvcc"
    CUDA_VERSION=$($NVCC_PATH --version | grep "release" | awk '{print $6}' | cut -c2-)
    echo -e "${GREEN}✓ CUDA found:${NC} version $CUDA_VERSION at $NVCC_PATH"
    CUDA_AVAILABLE=1
else
    echo -e "${YELLOW}⚠ CUDA not found. Building CPU-only version.${NC}"
fi

# Detect CUDA include path
CUDA_INC=""
if [ $CUDA_AVAILABLE -eq 1 ]; then
    if [ -d "/usr/local/cuda/include" ]; then
        CUDA_INC="/usr/local/cuda/include"
    elif [ -d "/usr/local/cuda-12.6/include" ]; then
        CUDA_INC="/usr/local/cuda-12.6/include"
    elif [ -d "/usr/include/cuda" ]; then
        CUDA_INC="/usr/include/cuda"
    fi
    
    if [ -n "$CUDA_INC" ]; then
        echo -e "${GREEN}✓ CUDA headers found:${NC} $CUDA_INC"
    else
        echo -e "${YELLOW}⚠ CUDA headers not found, using minimal definitions${NC}"
    fi
fi

# Check for MinGW
if ! command -v x86_64-w64-mingw32-g++ &> /dev/null; then
    echo -e "${RED}✗ MinGW not found. Please install mingw-w64${NC}"
    echo "  sudo apt-get install mingw-w64"
    exit 1
fi

echo -e "${GREEN}✓ MinGW found${NC}"

# Create build directory
mkdir -p build
cd build

# Build configuration
if [ "$1" == "--cpu-only" ] || [ $CUDA_AVAILABLE -eq 0 ]; then
    echo -e "\n${YELLOW}Building CPU-only version...${NC}"
    
    # Compile CPU-only version
    x86_64-w64-mingw32-g++ \
        -shared \
        -O3 \
        -std=c++17 \
        -DBUILDING_DLL \
        -o ../ImmolateCUDA.dll \
        ../src/gpu_experimental/brainstorm_cuda.cpp \
        ../src/items.cpp \
        ../src/rng.cpp \
        ../src/seed.cpp \
        ../src/util.cpp \
        ../src/functions.cpp \
        -I ../src/ \
        -I ../src/gpu_experimental \
        -static-libgcc \
        -static-libstdc++ \
        -Wl,--export-all-symbols \
        2>&1 | tee build_cpu.log
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ CPU build successful${NC}"
        DLL_SIZE=$(du -h ../ImmolateCUDA.dll | cut -f1)
        echo -e "  DLL size: ${DLL_SIZE}"
    else
        echo -e "${RED}✗ CPU build failed. Check build_cpu.log${NC}"
        exit 1
    fi
    
else
    echo -e "\n${YELLOW}Building GPU+CPU unified version...${NC}"
    
    # Step 1: Compile CUDA kernels to object file for linking
    echo "Step 1: Compiling CUDA kernels to object file..."
    
    # Compile to relocatable device code
    $NVCC_PATH \
        -dc \
        -O3 \
        -arch=sm_70 \
        -ccbin gcc-13 \
        -Xcompiler -fPIC \
        -o seed_filter.o \
        ../src/gpu_experimental/gpu/seed_filter.cu \
        2>&1 | tee build_cuda.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${RED}✗ CUDA compilation to object failed${NC}"
        exit 1
    fi
    
    # Also compile to PTX for runtime loading (optional)
    echo "Also creating PTX for runtime loading..."
    $NVCC_PATH \
        -ptx \
        -O3 \
        -arch=sm_70 \
        -ccbin gcc-13 \
        -o seed_filter.ptx \
        ../src/gpu_experimental/gpu/seed_filter.cu \
        2>&1 | tee -a build_cuda.log
    
    # Also create a fatbin with all architectures for embedding
    echo "Creating fatbin for multiple architectures..."
    $NVCC_PATH \
        -fatbin \
        -O3 \
        -arch=sm_70 \
        -ccbin gcc-13 \
        -gencode=arch=compute_70,code=sm_70 \
        -gencode=arch=compute_75,code=sm_75 \
        -gencode=arch=compute_80,code=sm_80 \
        -gencode=arch=compute_86,code=sm_86 \
        -gencode=arch=compute_89,code=sm_89 \
        -o seed_filter.fatbin \
        ../src/gpu_experimental/gpu/seed_filter.cu \
        2>&1 | tee -a build_cuda.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${RED}✗ CUDA compilation failed. Check build_cuda.log${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ CUDA kernels compiled${NC}"
    
    # Step 2: Compile GPU searcher with dynamic loading
    echo "Step 2: Compiling GPU searcher with dynamic CUDA loading..."
    
    INCLUDE_FLAGS="-I ../src/ -I ../src/gpu_experimental"
    if [ -n "$CUDA_INC" ]; then
        INCLUDE_FLAGS="$INCLUDE_FLAGS -I $CUDA_INC"
    fi
    
    x86_64-w64-mingw32-g++ \
        -c \
        -O3 \
        -std=c++17 \
        -DGPU_ENABLED \
        -DBRAINSTORM_DEBUG \
        $INCLUDE_FLAGS \
        -o gpu_searcher.o \
        ../src/gpu_experimental/gpu/gpu_searcher_dynamic.cpp \
        2>&1 | tee -a build_cuda.log
    
    # Step 2b: Compile GPU kernel wrapper
    echo "Step 2b: Compiling GPU kernel wrapper..."
    x86_64-w64-mingw32-g++ \
        -c \
        -O3 \
        -std=c++17 \
        -DGPU_ENABLED \
        -DBRAINSTORM_DEBUG \
        $INCLUDE_FLAGS \
        -o gpu_kernel.o \
        ../src/gpu_experimental/gpu/gpu_searcher_kernel.cpp \
        2>&1 | tee -a build_cuda.log
    
    # Step 3: Compile unified brainstorm
    echo "Step 3: Compiling unified brainstorm..."
    
    x86_64-w64-mingw32-g++ \
        -c \
        -O3 \
        -std=c++17 \
        -DBUILDING_DLL \
        -DGPU_ENABLED \
        -DGPU_DYNAMIC_LOAD \
        $INCLUDE_FLAGS \
        -o brainstorm.o \
        ../src/gpu_experimental/brainstorm_cuda.cpp \
        2>&1 | tee -a build_cuda.log
    
    # Step 4: Link everything into DLL with CUDA kernel
    echo "Step 4: Linking unified DLL with CUDA kernel..."
    
    # Link with the CUDA object file for actual GPU kernel
    x86_64-w64-mingw32-g++ \
        -shared \
        -o ../ImmolateCUDA.dll \
        brainstorm.o \
        gpu_searcher.o \
        gpu_kernel.o \
        seed_filter.o \
        ../src/items.cpp \
        ../src/rng.cpp \
        ../src/seed.cpp \
        ../src/util.cpp \
        ../src/functions.cpp \
        -static-libgcc \
        -static-libstdc++ \
        -Wl,--export-all-symbols \
        2>&1 | tee -a build_cuda.log
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ GPU+CPU build successful${NC}"
        DLL_SIZE=$(du -h ../ImmolateCUDA.dll | cut -f1)
        echo -e "  DLL size: ${DLL_SIZE}"
        
        # Export PTX/fatbin alongside the DLL for packaging/deployment
        [ -f seed_filter.ptx ] && cp seed_filter.ptx ../seed_filter.ptx
        [ -f seed_filter.fatbin ] && cp seed_filter.fatbin ../seed_filter.fatbin
        
        if [ "$DLL_SIZE" == "2.4M" ]; then
            echo -e "${YELLOW}  Note: Size suggests CPU-only. GPU code may not be linked.${NC}"
        elif [[ "$DLL_SIZE" > "5M" ]]; then
            echo -e "${GREEN}  Size suggests GPU code included successfully.${NC}"
        fi
    else
        echo -e "${RED}✗ Linking failed. Check build_cuda.log${NC}"
        exit 1
    fi
fi

# Step 6: Build standalone test executable (optional)
if [ "$2" == "--with-tests" ]; then
    echo -e "\n${YELLOW}Building test executable...${NC}"
    
    x86_64-w64-mingw32-g++ \
        -O3 \
        -std=c++17 \
        -DGPU_ENABLED \
        -o ../test_cuda.exe \
        ../src/gpu_experimental/gpu/test_cuda.cpp \
        -I ../src/ \
        -I ../src/gpu_experimental \
        -static-libgcc \
        -static-libstdc++ \
        2>&1 | tee build_test.log
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}✓ Test executable built${NC}"
    else
        echo -e "${YELLOW}⚠ Test build failed (non-critical)${NC}"
    fi
fi

echo -e "\n======================================="
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "To test: Copy ImmolateCUDA.dll to your Brainstorm mod folder"
echo "To verify GPU: Check console output when mod loads"
echo ""
echo "Build options:"
echo "  ./build_gpu.sh              - Build with GPU if available"
echo "  ./build_gpu.sh --cpu-only   - Force CPU-only build"
echo "  ./build_gpu.sh --with-tests - Also build test executable"
echo "======================================="
