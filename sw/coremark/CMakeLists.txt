cmake_minimum_required(VERSION 3.10)
project(Benchmark C)

# --- Source files ---
set(SOURCES
    ee_printf.c
    core_portme.c
    core_main.c
    core_list_join.c
    core_matrix.c
    core_state.c
    core_util.c
)

# --- Startup assembly file ---
set(STARTUP_ASM startup.S)

include_directories(${CMAKE_SOURCE_DIR})

# --- Step 0: Detect linker script automatically ---
file(GLOB LINKER_SCRIPTS "${CMAKE_SOURCE_DIR}/*.ld")
if(LINKER_SCRIPTS)
    list(GET LINKER_SCRIPTS 0 LINKER_SCRIPT)
    message(STATUS "Using linker script: ${LINKER_SCRIPT}")
else()
    message(FATAL_ERROR "No linker script (.ld) found in source directory!")
endif()

# --- Step 1: Compiler, Assembler, Linker tools ---
set(GCC     riscv64-unknown-elf-gcc)
set(AS      riscv32-unknown-elf-as)
set(LD      riscv32-unknown-elf-ld)
set(OBJDUMP riscv32-unknown-elf-objdump)
set(OBJCOPY riscv32-unknown-elf-objcopy)


# --- Step 2: Assemble startup.S → startup.o (FIRST) ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/startup.o
    COMMAND ${AS}
            -march=rv32im
            -mabi=ilp32
            -o ${CMAKE_BINARY_DIR}/startup.o
            ${CMAKE_SOURCE_DIR}/${STARTUP_ASM}
    DEPENDS ${CMAKE_SOURCE_DIR}/${STARTUP_ASM}
    COMMENT "Assembling ${STARTUP_ASM} -> startup.o"
)

# --- Step 3: Compile each .c → .s ---
set(ASM_FILES "")
foreach(src ${SOURCES})
    get_filename_component(name ${src} NAME_WE)
    add_custom_command(
        OUTPUT ${CMAKE_BINARY_DIR}/${name}.s
        COMMAND ${GCC}
                -march=rv32im -mabi=ilp32 -O1
                -malign-data=xlen
                #  -fno-schedule-insns -fno-schedule-insns2
                # -fno-reorder-blocks
                # -fno-reorder-functions
                -fverbose-asm
                -nostdlib -nostartfiles -fno-builtin -fno-pic -fno-pie
                -S ${CMAKE_SOURCE_DIR}/${src}
                -o ${CMAKE_BINARY_DIR}/${name}.s
        DEPENDS ${CMAKE_SOURCE_DIR}/${src}
        COMMENT "Compiling ${src} -> ${name}.s"
    )
    list(APPEND ASM_FILES ${CMAKE_BINARY_DIR}/${name}.s)
endforeach()

# --- Step 4: Assemble .s → .o ---
set(OBJ_FILES ${CMAKE_BINARY_DIR}/startup.o)  # startup.o FIRST
foreach(asm ${ASM_FILES})
    get_filename_component(name ${asm} NAME_WE)
    add_custom_command(
        OUTPUT ${CMAKE_BINARY_DIR}/${name}.o
        COMMAND ${AS}
                -march=rv32im
                -mabi=ilp32
                -o ${CMAKE_BINARY_DIR}/${name}.o
                ${asm}
        DEPENDS ${asm}
        COMMENT "Assembling ${asm} -> ${name}.o"
    )
    list(APPEND OBJ_FILES ${CMAKE_BINARY_DIR}/${name}.o)
endforeach()

# --- Step 5: Link .o → ELF (startup.o MUST BE FIRST!) ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/benchmark.elf
    COMMAND ${LD}
            -T ${LINKER_SCRIPT}
            -o ${CMAKE_BINARY_DIR}/benchmark.elf
            ${OBJ_FILES}
    DEPENDS ${OBJ_FILES} ${LINKER_SCRIPT}
    COMMENT "Linking all objects -> benchmark.elf (startup.o first)"
)

# --- Step 6: Disassemble ELF → readable .s ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/benchmark_disasm.s
    COMMAND ${OBJDUMP} -d -M no-aliases,numeric --show-raw-insn --disassemble-all ${CMAKE_BINARY_DIR}/benchmark.elf > ${CMAKE_BINARY_DIR}/benchmark_disasm.s
    DEPENDS ${CMAKE_BINARY_DIR}/benchmark.elf
    COMMENT "Disassembling benchmark.elf -> benchmark_disasm.s"
)

# --- Step 7a: Extract ONLY .rodata section (Read-Only Data) ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/RODATA.bin
    COMMAND ${OBJCOPY} 
            -O binary 
            --only-section=.rodata
            ${CMAKE_BINARY_DIR}/benchmark.elf 
            ${CMAKE_BINARY_DIR}/RODATA.bin
    DEPENDS ${CMAKE_BINARY_DIR}/benchmark.elf
    COMMENT "Extracting .rodata section -> RODATA.bin"
)

# --- Step 7b: Extract ONLY .data section (Data Memory) ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/DATA.bin
    COMMAND ${OBJCOPY} 
            -O binary 
            --only-section=.data
            ${CMAKE_BINARY_DIR}/benchmark.elf 
            ${CMAKE_BINARY_DIR}/DATA.bin
    DEPENDS ${CMAKE_BINARY_DIR}/benchmark.elf
    COMMENT "Extracting .data section -> DATA.bin"
)

# --- Step 7c: Combine RODATA + DATA into DMEM.bin ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/DMEM.bin
    COMMAND cat ${CMAKE_BINARY_DIR}/RODATA.bin ${CMAKE_BINARY_DIR}/DATA.bin > ${CMAKE_BINARY_DIR}/DMEM.bin
    DEPENDS ${CMAKE_BINARY_DIR}/RODATA.bin ${CMAKE_BINARY_DIR}/DATA.bin
    COMMENT "Combining RODATA.bin + DATA.bin -> DMEM.bin"
)

# --- Step 8: Convert Data Binary → Hex ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/DMEM_full.hex
    COMMAND od -An -tx4 -w4 -v ${CMAKE_BINARY_DIR}/DMEM.bin > ${CMAKE_BINARY_DIR}/DMEM_full.hex
    DEPENDS ${CMAKE_BINARY_DIR}/DMEM.bin
    COMMENT "Converting DMEM.bin -> DMEM_full.hex"
)

# --- Step 9: Limit to first N words ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/DMEM.hex
    COMMAND head -n 8192 ${CMAKE_BINARY_DIR}/DMEM_full.hex > ${CMAKE_BINARY_DIR}/DMEM.hex
    DEPENDS ${CMAKE_BINARY_DIR}/DMEM_full.hex
    COMMENT "Limiting to first 8192 words"
)

# --- Step 10: Extract code section separately ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/IMEM.bin
    COMMAND ${OBJCOPY} 
            -O binary 
            --only-section=.text
            ${CMAKE_BINARY_DIR}/benchmark.elf 
            ${CMAKE_BINARY_DIR}/IMEM.bin
    DEPENDS ${CMAKE_BINARY_DIR}/benchmark.elf
    COMMENT "Extracting .text section -> IMEM.bin"
)

# --- Step 11: Convert code to hex ---
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/IMEM.hex
    COMMAND od -An -tx4 -w4 -v ${CMAKE_BINARY_DIR}/IMEM.bin > ${CMAKE_BINARY_DIR}/IMEM.hex
    DEPENDS ${CMAKE_BINARY_DIR}/IMEM.bin
    COMMENT "Converting IMEM.bin -> IMEM.hex"
)

# --- Final target ---
add_custom_target(benchmark ALL 
    DEPENDS 
        ${CMAKE_BINARY_DIR}/benchmark_disasm.s
        ${CMAKE_BINARY_DIR}/DMEM.hex
        ${CMAKE_BINARY_DIR}/IMEM.hex
)