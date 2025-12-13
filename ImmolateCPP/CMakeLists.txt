cmake_minimum_required(VERSION 3.10)
project(BrainstormTests)

# C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Compiler flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -O0")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")

# Sanitizer options
option(USE_ASAN "Use AddressSanitizer" OFF)
option(USE_TSAN "Use ThreadSanitizer" OFF)
option(USE_UBSAN "Use UndefinedBehaviorSanitizer" OFF)

if(USE_ASAN)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address -fno-omit-frame-pointer")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=address")
endif()

if(USE_TSAN)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=thread")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=thread")
endif()

if(USE_UBSAN)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=undefined")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fsanitize=undefined")
endif()

# Include directories
include_directories(src)

# Source files
set(CORE_SOURCES
    src/brainstorm_cpu.cpp
    src/items.cpp
    src/rng.cpp
    src/seed.cpp
    src/util.cpp
    src/functions.cpp
)

# Test executable
add_executable(run_tests
    src/tests/test_critical_functions.cpp
    src/tests/test_memory_safety.cpp
    ${CORE_SOURCES}
)

# Enable testing
enable_testing()

# Add tests
add_test(NAME CriticalFunctions COMMAND run_tests --test-critical)
add_test(NAME MemorySafety COMMAND run_tests --test-memory)
add_test(NAME Performance COMMAND run_tests --test-performance)

# Custom target for running tests with sanitizers
add_custom_target(test_with_sanitizers
    COMMAND ${CMAKE_COMMAND} -DUSE_ASAN=ON ${CMAKE_SOURCE_DIR}
    COMMAND ${CMAKE_COMMAND} --build .
    COMMAND ${CMAKE_CTEST_COMMAND} --verbose
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
)

# Coverage target (requires gcov)
if(CMAKE_COMPILER_IS_GNUCXX)
    option(ENABLE_COVERAGE "Enable coverage reporting" OFF)
    if(ENABLE_COVERAGE)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -O0 --coverage")
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --coverage")
        
        add_custom_target(coverage
            COMMAND ${CMAKE_CTEST_COMMAND}
            COMMAND lcov --capture --directory . --output-file coverage.info
            COMMAND lcov --remove coverage.info '/usr/*' --output-file coverage.info
            COMMAND lcov --list coverage.info
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        )
    endif()
endif()
