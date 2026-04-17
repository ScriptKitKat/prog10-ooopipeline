---
noteId: "22ef2af039fb11f1833589bfd73f6e80"
tags: []

---

# Design Spec: Pipelined Out-of-Order Tinker Processor

## 1. Overview

Replace the existing multi-cycle FSM `tinker_core` with a pipelined, dual-issue, out-of-order superscalar processor based on Tomasulo's algorithm. The module interface remains unchanged:

```systemverilog
module tinker_core(
    input clk,
    input reset,
    output logic hlt
);
```

All 30 ISA instructions produce identical architectural results as the original. The implementation lives in `tinker.sv`, reusing existing `memory`, `reg_file`, and FPU modules.

## 2. Pipeline Stages

```
Fetch -> Decode/Rename -> Dispatch -> Issue -> Execute -> Complete (CDB) -> Commit
```

Cycle-by-cycle (ALU example, 2-stage execute):
```
Cycle:    1    2    3    4    5    6    7    8
Inst A:  FE   DR   DI   IS   EX1  EX2  CDB  COM
Inst B:  FE   DR   DI   IS   EX1  EX2  CDB  COM
```

FPU instructions have EX1-EX4 (4 stages) instead of EX1-EX2.

## 3. Module Hierarchy

```
tinker_core
├── fetch_unit          (fetch buffer + branch predictor)
├── decode_rename_unit  (2x decoder + RAT + free list)
├── dispatch_unit       (routes to reservation stations)
├── rs_alu [x2]         (4 entries each, 8 total)
├── rs_fpu [x2]         (4 entries each, 8 total)
├── rs_lsu_load         (8 entries)
├── rs_lsu_store        (8 entries)
├── alu_pipe [x2]       (2-stage pipelined ALU)
├── fpu_pipe [x2]       (4-stage pipelined FPU, wraps existing fpu_add/mul/div)
├── load_store_unit     (2 L/S units, address compute + memory access)
├── cdb_arbiter         (2 CDB buses)
├── rob                 (32 entries, circular buffer)
├── phys_reg_file       (128x64-bit, 4R/2W, ready bits)
├── rat                 (32->128 mapping + snapshot checkpoints)
├── free_list           (FIFO of physical reg indices)
├── reg_file            (32x64-bit architectural, existing module)
└── memory              (512KB, existing module, extended for 64B fetch)
```

## 4. Key Parameters

| Parameter | Value |
|-----------|-------|
| Physical registers | 128 (7-bit tags) |
| Architectural registers | 32 (5-bit) |
| ROB entries | 32 (5-bit index) |
| BHT entries | 256 (indexed by PC[9:2]), 1-bit |
| Fetch buffer | 16 instructions |
| CDB buses | 2 |
| RAT snapshots | 4 (max in-flight branches) |
| Free list initial | P32-P127 (96 entries) |
| ALU RS | 4 per ALU, 8 total |
| FPU RS | 4 per FPU, 8 total |
| Load queue | 8 entries |
| Store queue | 8 entries |

## 5. Fetch Unit

- Fetch up to 64 bytes (16 instructions) from memory starting at PC each cycle into a fetch buffer.
- Supply 2 instructions per cycle to decode stage from the fetch buffer.
- Each instruction in the fetch buffer carries its PC.
- **Branch predictor**: 256-entry 1-bit BHT indexed by `PC[9:2]`.
  - Predicted-taken: redirect PC to predicted target next cycle.
  - Predicted-not-taken: continue sequential fetch.
  - Update: flip bit when actual outcome differs from prediction.
- On misprediction: flush the entire fetch buffer and redirect PC to correct target.

## 6. Decode/Rename Unit

- Dual decode: 2 instances of instruction decoder, one per instruction from fetch buffer.
- **Register renaming per instruction**:
  1. Read source mappings (rs, rt) from RAT -> physical register tags.
  2. Dequeue a free physical register from FIFO free list for rd destination.
  3. Update RAT: map architectural rd -> new physical register.
  4. Record old physical mapping (for recovery/free on commit).
- **Intra-group dependency**: If instruction 2's source reads a register that instruction 1 is renaming in the same cycle, instruction 2 gets instruction 1's new physical register.
- **ROB allocation**: Each decoded instruction gets a ROB entry in program order.
- **Stall conditions**:
  - ROB is full (fewer than 2 free entries).
  - Free list has fewer than 2 entries.
  - Target reservation stations are full.
- **Branch snapshot**: When a branch is decoded, snapshot the RAT and free list head pointer into a checkpoint buffer, tagged with the ROB index.

## 7. Dispatch & Reservation Stations

### Dispatch routing by opcode:

| Opcode category | Target RS |
|-----------------|-----------|
| Integer arith/logic/shift (ADD, ADDI, SUB, SUBI, MUL, DIV, AND, OR, XOR, NOT, SHFTR, SHFTRI, SHFTL, SHFTLI) | ALU RS (round-robin) |
| Branch (BR, BRR, BRR_L, BRNZ, BRGT) | ALU RS |
| MOV rd,rs / MOVI | ALU RS |
| CALL | ALU RS (for branch + r31 update) + Store queue (push PC+4) |
| RETURN | Load queue (read return address) |
| FP (FADD, FSUB, FMUL, FDIV) | FPU RS (round-robin) |
| LOAD / MOV rd,(rs)(L) | Load queue |
| STORE / MOV (rd)(L),rs | Store queue |

### Reservation station entry format:

| Field | Width | Description |
|-------|-------|-------------|
| valid | 1 | Entry occupied |
| opcode | 5 | Operation |
| src1_value | 64 | Operand 1 value (if ready) |
| src1_tag | 7 | Physical reg tag (if not ready) |
| src1_ready | 1 | Operand 1 available |
| src2_value | 64 | Operand 2 value (if ready) |
| src2_tag | 7 | Physical reg tag (if not ready) |
| src2_ready | 1 | Operand 2 available |
| dest_tag | 7 | Destination physical register |
| rob_idx | 5 | ROB entry index |
| imm | 64 | Sign-extended L field |
| pc | 64 | Instruction PC (for branches) |

### Issue logic:
- Each cycle, for each functional unit: select the oldest ready entry (both operands ready) and send to execution.
- **CDB snoop**: Every cycle, RS entries listen on both CDB buses. If a broadcast tag matches a pending source tag, capture value and mark ready.

### Operand read at dispatch:
- Check physical register file ready bit for each source. If ready, read value directly. If not, store physical reg tag and wait for CDB.

## 8. Functional Units

### 8.1 ALU (x2, 2-stage pipeline each)

- **Stage 1**: Compute result. Integer arithmetic, logic, shifts, branch resolution. Each ALU has its own compute logic.
- **Stage 2**: Result available, write to CDB.
- **Branch resolution**: Compare actual taken/target against prediction in ROB. If mismatch, signal misprediction.
- **Pipelined**: New instruction enters stage 1 every cycle. 2-cycle latency, 1-cycle throughput per ALU.
- Handles: ADD, ADDI, SUB, SUBI, MUL, DIV, AND, OR, XOR, NOT, SHFTR, SHFTRI, SHFTL, SHFTLI, MOV, MOVI, BR, BRR, BRR_L, BRNZ, BRGT, CALL, RETURN.

### 8.2 FPU (x2, 4-stage pipeline each)

- **Stage 1**: Latch inputs, operand classification (wraps `fpu_class`).
- **Stage 2**: Core computation (feeds through existing combinational `fpu_add`, `fpu_mul`, `fpu_div`).
- **Stage 3**: Latch output (normalization covered by combinational logic).
- **Stage 4**: Present result to CDB.
- Existing combinational FPU modules are wrapped with pipeline registers, not rewritten.
- **Pipelined**: New instruction enters stage 1 every cycle. 4-cycle latency, 1-cycle throughput per FPU.
- Handles: FADD, FSUB, FMUL, FDIV.

### 8.3 Load/Store Units (x2)

- **Address compute** (1 cycle): `base_register + sign_extend(L)`.
- **Memory access** (1 cycle): Read from memory (loads). Stores buffer data and wait for commit.
- **Store-to-load forwarding**: When a load computes its address, search the store queue for older stores with matching address. If found with valid data, forward directly instead of reading memory.
- **Memory ordering**: Loads check against older stores. Stores commit to memory only when at ROB head (in-order commit).
- Two L/S units can operate in parallel, but only 1 store commits to memory per cycle (single write port).

## 9. Common Data Bus (2 buses)

- Each bus carries: `{valid[0:0], dest_phys_tag[6:0], value[63:0], rob_idx[4:0]}`.
- **Arbitration** (split priority):
  - CDB bus 0: ALU0 > FPU0 > LSU0
  - CDB bus 1: ALU1 > FPU1 > LSU1
  - Losing units stall one cycle, holding result in final pipeline stage.
- **Listeners** (snoop both buses every cycle):
  - Reservation stations: resolve pending operand tags.
  - ROB: mark instructions complete.
  - Physical register file: write value and set ready bit.

## 10. Reorder Buffer (32 entries)

- Circular buffer. Head = oldest, tail = newest.
- Allocated in program order at decode.

### Entry fields:

| Field | Width | Description |
|-------|-------|-------------|
| valid | 1 | Entry occupied |
| complete | 1 | Execution finished (CDB received) |
| type | 3 | ALU/FPU/LOAD/STORE/BRANCH/OTHER |
| arch_rd | 5 | Destination architectural register |
| old_phys | 7 | Previous physical reg mapping |
| new_phys | 7 | New physical reg mapping |
| pc | 64 | Instruction PC |
| branch_pred | 1 | Predicted taken/not-taken |
| branch_target | 64 | Predicted target |
| store_addr | 64 | Computed store address |
| store_data | 64 | Store data |
| store_addr_ready | 1 | Address computed |
| store_data_ready | 1 | Data available |

### Commit logic (up to 2 per cycle from head):
- **ALU/FPU**: Write physical reg value -> architectural reg file. Return old_phys to free list.
- **STORE**: Write store data to memory (max 1 store per cycle). Return old_phys if applicable.
- **BRANCH**: No action if correctly predicted. Misprediction already handled at resolution.
- **HALT**: When HALT is at ROB head, assert `hlt = 1`.

### Misprediction flush:
1. Flush all ROB entries after the mispredicted branch.
2. Restore RAT from snapshot checkpoint.
3. Return physical regs from flushed entries to free list.
4. Redirect PC to correct target.
5. Flush fetch buffer, all reservation stations, and in-flight pipeline stages.
6. If two branches mispredict same cycle, older one (closer to ROB head) takes priority.

## 11. Physical Register File

- 128 registers, each 64 bits wide.
- **4 read ports**: 2 instructions x 2 sources at dispatch.
- **2 write ports**: Matches 2 CDB buses.
- **Ready bit array** (128 bits): Set when CDB writes value. Cleared when instruction renames to that register at decode. Checked by dispatch.
- P0-P31 initialized to match architectural registers on reset. P32-P127 start on free list.

## 12. RAT & Free List

### RAT:
- 32 entries, each 7-bit physical register index.
- Initialized: R0->P0, R1->P1, ..., R31->P31.
- Updated at decode when instruction renames rd.
- **Snapshots** (up to 4):
  - Full 32-entry RAT copy (32 x 7 bits).
  - Free list head pointer.
  - Tagged with ROB index of the branch.
  - Allocated when branch is decoded.
  - Freed on correct branch commit or consumed on misprediction restore.

### Free List (FIFO):
- Circular buffer holding P32-P127 (96 entries initially).
- **2 dequeue ports**: For dual-issue rename.
- **2 enqueue ports**: For dual-commit (return old_phys from committed ROB entries).
- Stall decode if fewer than 2 entries available.

## 13. Special Instruction Handling

### MOVI (opcode 0x12):
- `result = {L, rd_data[51:0]}` — writes L (12 bits) into rd[63:52], preserves rd[51:0].
- Read-modify-write: rd is both source (to read old value for bits [51:0]) and destination (gets new physical reg).

### CALL (opcode 0x0c):
- Computes `r31 - 8` for store address.
- Stores `PC + 4` to `mem[r31 - 8]`.
- Updates r31 to `r31 - 8`.
- Branches to rd.
- Single ROB entry. Store goes to store queue. Branch resolved in ALU. r31 update is the ALU result.

### RETURN (opcode 0x0d):
- Computes `r31 - 8` for load address.
- Loads saved PC from `mem[r31 - 8]`.
- Writes `r31 - 8` back to r31.
- Dispatched to load queue. Branch target comes from loaded value. Single ROB entry.

### HALT (opcode 0x0f, L=0):
- Enters ROB like any instruction.
- When HALT commits from ROB head (oldest instruction), assert `hlt = 1`.

## 14. Forwarding

Forwarding is implemented entirely through the CDB broadcast mechanism:
1. A functional unit completes and broadcasts `{dest_tag, value}` on a CDB bus.
2. That same cycle, all reservation stations snoop both CDB buses. Any RS entry waiting on that tag captures the value and marks the operand ready.
3. That same cycle, the physical register file writes the value and sets the ready bit.
4. A dependent instruction can issue the next cycle after the producer broadcasts.

There is no separate bypass mux. The CDB replaces traditional forwarding and is more general: it forwards to all consumers simultaneously.

## 15. Existing Module Reuse

- **memory**: Extend interface to support 64-byte fetch (16 instructions). Keep existing data read/write ports.
- **reg_file**: Extend to 4 read ports and 2 write ports for dual-commit. Keep R31 init to MEM_SIZE.
- **fpu_add, fpu_mul, fpu_div, fpu_class**: Wrap inside FPU pipeline stages with registers. Do not rewrite internals.
- **instruction_decoder**: Reuse as-is, instantiate 2 copies for dual decode.

## 16. Compilation

All modules must compile with `iverilog -g2012`. The existing testbench (`tinker_tb.sv`) should produce identical results after the transformation.
