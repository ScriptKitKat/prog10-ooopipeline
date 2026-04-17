---
noteId: "e8469e4039fc11f1833589bfd73f6e80"
tags: []

---

# OOO Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace multi-cycle FSM tinker_core with a dual-issue OOO superscalar processor using Tomasulo's algorithm.

**Architecture:** Bottom-up build. Extend existing modules first, then build new infrastructure (phys regs, free list, RAT), then functional units (ALU/FPU pipes, LSU), then control structures (RS, CDB, ROB), then top-level wiring. All in `tinker.sv`.

**Tech Stack:** SystemVerilog 2012, iverilog -g2012

---

### Task 1: Extend memory module for 64-byte fetch

**Files:**
- Modify: `tinker.sv` (memory module, lines 211-246)

- [ ] **Step 1: Add fetch_addr input and fetch_data output to memory module**

Add a 64-byte (16-instruction) fetch port alongside existing data ports:

```systemverilog
module memory(
    input clk,
    input reset,
    input [63:0] PC,
    output [31:0] instruction,
    // New: 64-byte fetch port
    input [63:0] fetch_addr,
    output [511:0] fetch_data,
    input [63:0] data_address,
    output [63:0] data_out,
    output data_ready,
    input write_enable,
    input [63:0] write_address,
    input [63:0] write_data
);
    reg [7:0] bytes [0:`MEM_SIZE-1];

    assign instruction = {bytes[PC + 3], bytes[PC + 2], bytes[PC + 1], bytes[PC]};

    // 64-byte fetch: 16 instructions, little-endian
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : fetch_gen
            assign fetch_data[gi*32 +: 32] = {
                bytes[fetch_addr + gi*4 + 3],
                bytes[fetch_addr + gi*4 + 2],
                bytes[fetch_addr + gi*4 + 1],
                bytes[fetch_addr + gi*4 + 0]
            };
        end
    endgenerate

    assign data_out = {bytes[data_address + 7], bytes[data_address + 6],
                       bytes[data_address + 5], bytes[data_address + 4],
                       bytes[data_address + 3], bytes[data_address + 2],
                       bytes[data_address + 1], bytes[data_address]};

    assign data_ready = 1'b1;

    always @(posedge clk) begin
        if (write_enable) begin
            bytes[write_address]     <= write_data[7:0];
            bytes[write_address + 1] <= write_data[15:8];
            bytes[write_address + 2] <= write_data[23:16];
            bytes[write_address + 3] <= write_data[31:24];
            bytes[write_address + 4] <= write_data[39:32];
            bytes[write_address + 5] <= write_data[47:40];
            bytes[write_address + 6] <= write_data[55:48];
            bytes[write_address + 7] <= write_data[63:56];
        end
    end
endmodule
```

- [ ] **Step 2: Compile to verify no errors**

Run: `iverilog -g2012 -o /dev/null tinker.sv`
Expected: Clean compile (warnings OK, no errors)

---

### Task 2: Extend reg_file for 4 read / 2 write ports

**Files:**
- Modify: `tinker.sv` (reg_file module, lines 248-280)

- [ ] **Step 1: Rewrite reg_file with 4R/2W ports**

```systemverilog
module reg_file(
    input clk,
    input reset,
    // Write port 1
    input write_en1,
    input [63:0] write_data1,
    input [4:0] write_sel1,
    // Write port 2
    input write_en2,
    input [63:0] write_data2,
    input [4:0] write_sel2,
    // Read ports
    input [4:0] read_sel1,
    input [4:0] read_sel2,
    input [4:0] read_sel3,
    input [4:0] read_sel4,
    output [63:0] read_data1,
    output [63:0] read_data2,
    output [63:0] read_data3,
    output [63:0] read_data4
);
    reg [63:0] registers [0:31];

    assign read_data1 = registers[read_sel1];
    assign read_data2 = registers[read_sel2];
    assign read_data3 = registers[read_sel3];
    assign read_data4 = registers[read_sel4];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 31; i = i + 1)
                registers[i] <= 64'b0;
            registers[31] <= `MEM_SIZE;
        end else begin
            if (write_en1) registers[write_sel1] <= write_data1;
            if (write_en2) registers[write_sel2] <= write_data2;
        end
    end
endmodule
```

- [ ] **Step 2: Compile check**

Run: `iverilog -g2012 -o /dev/null tinker.sv`

---

### Task 3: Physical register file (128x64, 4R/2W, ready bits)

**Files:**
- Modify: `tinker.sv` (add new module after reg_file)

- [ ] **Step 1: Add phys_reg_file module**

```systemverilog
module phys_reg_file(
    input clk,
    input reset,
    // Read ports (combinational)
    input [6:0] read_sel1, read_sel2, read_sel3, read_sel4,
    output [63:0] read_data1, read_data2, read_data3, read_data4,
    output read_ready1, read_ready2, read_ready3, read_ready4,
    // Write ports (from CDB)
    input wr_en1,
    input [6:0] wr_sel1,
    input [63:0] wr_data1,
    input wr_en2,
    input [6:0] wr_sel2,
    input [63:0] wr_data2,
    // Clear ready bit (on rename/allocate)
    input clear_ready_en1,
    input [6:0] clear_ready_sel1,
    input clear_ready_en2,
    input [6:0] clear_ready_sel2,
    // Flush: bulk set ready bits for returned regs
    input flush_en,
    input [6:0] flush_sel,
    input flush_ready_val
);
    reg [63:0] regs [0:127];
    reg ready [0:127];

    assign read_data1 = regs[read_sel1];
    assign read_data2 = regs[read_sel2];
    assign read_data3 = regs[read_sel3];
    assign read_data4 = regs[read_sel4];
    assign read_ready1 = ready[read_sel1];
    assign read_ready2 = ready[read_sel2];
    assign read_ready3 = ready[read_sel3];
    assign read_ready4 = ready[read_sel4];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 128; i = i + 1) begin
                regs[i] <= 64'b0;
                ready[i] <= (i < 32) ? 1'b1 : 1'b0;
            end
            regs[31] <= `MEM_SIZE;
        end else begin
            // CDB writes set value and ready
            if (wr_en1) begin
                regs[wr_sel1] <= wr_data1;
                ready[wr_sel1] <= 1'b1;
            end
            if (wr_en2) begin
                regs[wr_sel2] <= wr_data2;
                ready[wr_sel2] <= 1'b1;
            end
            // Rename clears ready
            if (clear_ready_en1) ready[clear_ready_sel1] <= 1'b0;
            if (clear_ready_en2) ready[clear_ready_sel2] <= 1'b0;
        end
    end
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 4: Free list (FIFO, 2 dequeue / 2 enqueue)

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add free_list module**

```systemverilog
module free_list(
    input clk,
    input reset,
    // Dequeue (rename): up to 2 per cycle
    input deq_en1,
    output [6:0] deq_tag1,
    input deq_en2,
    output [6:0] deq_tag2,
    // Enqueue (commit): up to 2 per cycle
    input enq_en1,
    input [6:0] enq_tag1,
    input enq_en2,
    input [6:0] enq_tag2,
    // Status
    output [6:0] count,
    output can_alloc2,  // at least 2 free
    // Snapshot restore
    input restore_en,
    input [6:0] restore_head
);
    reg [6:0] fifo [0:127];
    reg [6:0] head, tail;
    reg [6:0] cnt;

    assign count = cnt;
    assign can_alloc2 = (cnt >= 7'd2);
    assign deq_tag1 = fifo[head];
    assign deq_tag2 = fifo[head + 7'd1];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 96; i = i + 1)
                fifo[i] <= 7'd32 + i[6:0];
            head <= 7'd0;
            tail <= 7'd96;
            cnt  <= 7'd96;
        end else if (restore_en) begin
            head <= restore_head;
            // cnt recalculated after flush via enqueue
            cnt <= (tail >= restore_head) ? (tail - restore_head) : (7'd128 - restore_head + tail);
        end else begin
            // Dequeue
            if (deq_en1 && deq_en2) begin
                head <= head + 7'd2;
                cnt  <= cnt - 7'd2;
            end else if (deq_en1) begin
                head <= head + 7'd1;
                cnt  <= cnt - 7'd1;
            end

            // Enqueue (happens simultaneously, adjust cnt)
            if (enq_en1 && enq_en2) begin
                fifo[tail]        <= enq_tag1;
                fifo[tail + 7'd1] <= enq_tag2;
                tail <= tail + 7'd2;
                cnt  <= cnt + 7'd2;
            end else if (enq_en1) begin
                fifo[tail] <= enq_tag1;
                tail <= tail + 7'd1;
                cnt  <= cnt + 7'd1;
            end else if (enq_en2) begin
                fifo[tail] <= enq_tag2;
                tail <= tail + 7'd1;
                cnt  <= cnt + 7'd1;
            end

            // Net adjustment when both deq and enq happen
            // The above separate cnt updates will cause double-counting.
            // Fix: combine into single cnt update
        end
    end
endmodule
```

**Note:** The cnt update logic above has a bug with simultaneous enq/deq. The actual implementation must compute a single net delta:

```systemverilog
            // Combined count update
            cnt <= cnt
                - (deq_en1 ? 7'd1 : 7'd0)
                - (deq_en2 ? 7'd1 : 7'd0)
                + (enq_en1 ? 7'd1 : 7'd0)
                + (enq_en2 ? 7'd1 : 7'd0);
```

- [ ] **Step 2: Compile check**

---

### Task 5: RAT with snapshot checkpoints

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add rat module**

```systemverilog
module rat(
    input clk,
    input reset,
    // Read (combinational): 4 arch regs -> phys tags
    input [4:0] read_ar1, read_ar2, read_ar3, read_ar4,
    output [6:0] read_phys1, read_phys2, read_phys3, read_phys4,
    // Write (rename): up to 2 per cycle
    input wr_en1,
    input [4:0] wr_ar1,
    input [6:0] wr_phys1,
    input wr_en2,
    input [4:0] wr_ar2,
    input [6:0] wr_phys2,
    // Snapshot: save checkpoint
    input snap_en,
    input [1:0] snap_id,
    // Restore: load checkpoint
    input restore_en,
    input [1:0] restore_id
);
    reg [6:0] table [0:31];
    reg [6:0] snapshots [0:3][0:31]; // 4 checkpoints

    assign read_phys1 = table[read_ar1];
    assign read_phys2 = table[read_ar2];
    assign read_phys3 = table[read_ar3];
    assign read_phys4 = table[read_ar4];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                table[i] <= i[6:0]; // identity: R0->P0, ..., R31->P31
        end else if (restore_en) begin
            for (i = 0; i < 32; i = i + 1)
                table[i] <= snapshots[restore_id][i];
        end else begin
            if (wr_en1) table[wr_ar1] <= wr_phys1;
            if (wr_en2) table[wr_ar2] <= wr_phys2;
            // Snapshot
            if (snap_en) begin
                for (i = 0; i < 32; i = i + 1)
                    snapshots[snap_id][i] <= table[i];
            end
        end
    end
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 6: Reservation station module (parameterized)

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add reservation_station module**

```systemverilog
module reservation_station #(
    parameter NUM_ENTRIES = 4
)(
    input clk,
    input reset,
    // Dispatch: write new entry
    input dispatch_en,
    input [4:0] dispatch_opcode,
    input [63:0] dispatch_src1_val,
    input [6:0] dispatch_src1_tag,
    input dispatch_src1_ready,
    input [63:0] dispatch_src2_val,
    input [6:0] dispatch_src2_tag,
    input dispatch_src2_ready,
    input [6:0] dispatch_dest_tag,
    input [4:0] dispatch_rob_idx,
    input [63:0] dispatch_imm,
    input [63:0] dispatch_pc,
    // CDB snoop (2 buses)
    input cdb0_valid,
    input [6:0] cdb0_tag,
    input [63:0] cdb0_value,
    input cdb1_valid,
    input [6:0] cdb1_tag,
    input [63:0] cdb1_value,
    // Issue: oldest ready entry
    output issue_valid,
    output [4:0] issue_opcode,
    output [63:0] issue_src1_val,
    output [63:0] issue_src2_val,
    output [6:0] issue_dest_tag,
    output [4:0] issue_rob_idx,
    output [63:0] issue_imm,
    output [63:0] issue_pc,
    input issue_ack, // FU accepted the issue
    // Status
    output full,
    // Flush
    input flush
);
    reg valid [0:NUM_ENTRIES-1];
    reg [4:0] opcode [0:NUM_ENTRIES-1];
    reg [63:0] src1_val [0:NUM_ENTRIES-1];
    reg [6:0] src1_tag [0:NUM_ENTRIES-1];
    reg src1_rdy [0:NUM_ENTRIES-1];
    reg [63:0] src2_val [0:NUM_ENTRIES-1];
    reg [6:0] src2_tag [0:NUM_ENTRIES-1];
    reg src2_rdy [0:NUM_ENTRIES-1];
    reg [6:0] dest_tag [0:NUM_ENTRIES-1];
    reg [4:0] rob_idx [0:NUM_ENTRIES-1];
    reg [63:0] imm [0:NUM_ENTRIES-1];
    reg [63:0] pc [0:NUM_ENTRIES-1];
    reg [4:0] age [0:NUM_ENTRIES-1]; // for oldest-first selection

    // Count valid entries
    integer ci;
    reg [3:0] valid_count;
    always @(*) begin
        valid_count = 0;
        for (ci = 0; ci < NUM_ENTRIES; ci = ci + 1)
            if (valid[ci]) valid_count = valid_count + 1;
    end
    assign full = (valid_count == NUM_ENTRIES[3:0]);

    // Find oldest ready entry
    integer fi;
    reg found_issue;
    reg [$clog2(NUM_ENTRIES)-1:0] issue_idx;
    reg [4:0] best_age;
    always @(*) begin
        found_issue = 0;
        issue_idx = 0;
        best_age = 5'h1f;
        for (fi = 0; fi < NUM_ENTRIES; fi = fi + 1) begin
            if (valid[fi] && src1_rdy[fi] && src2_rdy[fi]) begin
                if (!found_issue || age[fi] < best_age) begin
                    found_issue = 1;
                    issue_idx = fi[$clog2(NUM_ENTRIES)-1:0];
                    best_age = age[fi];
                end
            end
        end
    end

    assign issue_valid = found_issue;
    assign issue_opcode = opcode[issue_idx];
    assign issue_src1_val = src1_val[issue_idx];
    assign issue_src2_val = src2_val[issue_idx];
    assign issue_dest_tag = dest_tag[issue_idx];
    assign issue_rob_idx = rob_idx[issue_idx];
    assign issue_imm = issue_valid ? imm[issue_idx] : 64'd0;
    assign issue_pc = issue_valid ? pc[issue_idx] : 64'd0;

    // Find free slot for dispatch
    integer di;
    reg [$clog2(NUM_ENTRIES)-1:0] free_idx;
    reg has_free;
    always @(*) begin
        has_free = 0;
        free_idx = 0;
        for (di = 0; di < NUM_ENTRIES; di = di + 1) begin
            if (!valid[di] && !has_free) begin
                has_free = 1;
                free_idx = di[$clog2(NUM_ENTRIES)-1:0];
            end
        end
    end

    // Age counter
    reg [4:0] age_counter;

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1)
                valid[i] <= 1'b0;
            age_counter <= 5'd0;
        end else begin
            // CDB snoop: capture values
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (valid[i]) begin
                    if (!src1_rdy[i]) begin
                        if (cdb0_valid && cdb0_tag == src1_tag[i]) begin
                            src1_val[i] <= cdb0_value;
                            src1_rdy[i] <= 1'b1;
                        end else if (cdb1_valid && cdb1_tag == src1_tag[i]) begin
                            src1_val[i] <= cdb1_value;
                            src1_rdy[i] <= 1'b1;
                        end
                    end
                    if (!src2_rdy[i]) begin
                        if (cdb0_valid && cdb0_tag == src2_tag[i]) begin
                            src2_val[i] <= cdb0_value;
                            src2_rdy[i] <= 1'b1;
                        end else if (cdb1_valid && cdb1_tag == src2_tag[i]) begin
                            src2_val[i] <= cdb1_value;
                            src2_rdy[i] <= 1'b1;
                        end
                    end
                end
            end

            // Issue: clear the issued entry
            if (issue_valid && issue_ack)
                valid[issue_idx] <= 1'b0;

            // Dispatch: write new entry
            if (dispatch_en && has_free) begin
                valid[free_idx]    <= 1'b1;
                opcode[free_idx]   <= dispatch_opcode;
                src1_val[free_idx] <= dispatch_src1_val;
                src1_tag[free_idx] <= dispatch_src1_tag;
                src1_rdy[free_idx] <= dispatch_src1_ready;
                src2_val[free_idx] <= dispatch_src2_val;
                src2_tag[free_idx] <= dispatch_src2_tag;
                src2_rdy[free_idx] <= dispatch_src2_ready;
                dest_tag[free_idx] <= dispatch_dest_tag;
                rob_idx[free_idx]  <= dispatch_rob_idx;
                imm[free_idx]      <= dispatch_imm;
                pc[free_idx]       <= dispatch_pc;
                age[free_idx]      <= age_counter;
                age_counter        <= age_counter + 1;
            end
        end
    end
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 7: ALU pipe (2-stage pipelined)

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add alu_pipe module**

This is a 2-stage pipelined ALU. Stage 1 computes, stage 2 presents to CDB. It reuses the combinational logic from the original ALU but operates on physical register values passed from the reservation station.

```systemverilog
module alu_pipe(
    input clk,
    input reset,
    // Issue interface
    input issue_valid,
    input [4:0] issue_opcode,
    input [63:0] issue_src1,  // resolved operand 1
    input [63:0] issue_src2,  // resolved operand 2
    input [6:0] issue_dest_tag,
    input [4:0] issue_rob_idx,
    input [63:0] issue_imm,
    input [63:0] issue_pc,
    output issue_ready, // can accept new instruction
    // CDB output (from stage 2)
    output reg cdb_valid,
    output reg [6:0] cdb_tag,
    output reg [63:0] cdb_value,
    output reg [4:0] cdb_rob_idx,
    // Branch resolution
    output reg br_resolved,
    output reg br_taken,
    output reg [63:0] br_target,
    output reg [4:0] br_rob_idx_out,
    // Flush
    input flush
);
    // Stage 1 registers
    reg s1_valid;
    reg [4:0] s1_opcode;
    reg [63:0] s1_src1, s1_src2, s1_imm, s1_pc;
    reg [6:0] s1_dest_tag;
    reg [4:0] s1_rob_idx;

    // Stage 1 compute (combinational)
    reg [63:0] s1_result;
    reg s1_branch_taken;
    reg [63:0] s1_branch_target;
    wire [63:0] s1_extended_L = s1_imm; // already sign-extended at dispatch

    always @(*) begin
        s1_result = 64'b0;
        s1_branch_taken = 1'b0;
        s1_branch_target = s1_pc + 64'd4;
        case (s1_opcode)
            5'h18: s1_result = s1_src1 + s1_src2;       // ADD
            5'h19: s1_result = s1_src1 + s1_imm;        // ADDI (src1=rd_old)
            5'h1a: s1_result = s1_src1 - s1_src2;       // SUB
            5'h1b: s1_result = s1_src1 - s1_imm;        // SUBI (src1=rd_old)
            5'h1c: s1_result = s1_src1 * s1_src2;       // MUL
            5'h1d: s1_result = s1_src1 / s1_src2;       // DIV
            5'h00: s1_result = s1_src1 & s1_src2;       // AND
            5'h01: s1_result = s1_src1 | s1_src2;       // OR
            5'h02: s1_result = s1_src1 ^ s1_src2;       // XOR
            5'h03: s1_result = ~s1_src1;                 // NOT
            5'h04: s1_result = s1_src1 >> s1_src2;       // SHFTR
            5'h05: s1_result = s1_src1 >> s1_imm;        // SHFTRI (src1=rd_old)
            5'h06: s1_result = s1_src1 << s1_src2;       // SHFTL
            5'h07: s1_result = s1_src1 << s1_imm;        // SHFTLI (src1=rd_old)
            5'h08: begin // BR rd
                s1_branch_target = s1_src1; // src1 = rd_data
                s1_branch_taken = 1'b1;
            end
            5'h09: begin // BRR rd
                s1_branch_target = s1_src1 + s1_pc;
                s1_branch_taken = 1'b1;
            end
            5'h0a: begin // BRR L
                s1_branch_target = s1_imm + s1_pc;
                s1_branch_taken = 1'b1;
            end
            5'h0b: begin // BRNZ rd, rs
                s1_branch_target = s1_src1; // src1 = rd_data
                if (s1_src2 != 64'b0) s1_branch_taken = 1'b1; // src2 = rs_data
            end
            5'h0c: begin // CALL
                s1_result = s1_src2 - 64'd8; // src2 = r31_data, result = new r31
                s1_branch_target = s1_src1;  // src1 = rd_data
                s1_branch_taken = 1'b1;
            end
            5'h0d: begin // RETURN - result = r31-8 (address), branch target from load
                s1_result = s1_src1 - 64'd8; // src1 = r31_data
                s1_branch_taken = 1'b1;
                s1_branch_target = 64'd0; // placeholder, actual target from load unit
            end
            5'h0e: begin // BRGT rd, rs, rt
                s1_branch_target = s1_src1; // src1 = rd_data
                if (s1_src2 > s1_imm) s1_branch_taken = 1'b1; // overloaded: src2=rs, imm holds rt val
                // Note: BRGT needs 3 source operands. In the RS, we pack:
                // src1=rd, src2=rs. For rt comparison, dispatch stores rt_val in imm field
                // when rt is ready at dispatch time. This is a simplification.
            end
            5'h11: s1_result = s1_src1;                  // MOV rd, rs
            5'h12: s1_result = {s1_imm[11:0], s1_src1[51:0]}; // MOVI: L into [63:52]
            default: s1_result = 64'b0;
        endcase
    end

    assign issue_ready = !s1_valid || flush;

    // Pipeline registers
    // Stage 2 registers
    reg s2_valid;
    reg [63:0] s2_result;
    reg [6:0] s2_dest_tag;
    reg [4:0] s2_rob_idx;
    reg s2_branch_taken;
    reg [63:0] s2_branch_target;
    reg [4:0] s2_opcode;

    wire is_branch_op = (s1_opcode >= 5'h08 && s1_opcode <= 5'h0e);

    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
            cdb_valid <= 1'b0;
            br_resolved <= 1'b0;
        end else begin
            // Stage 1 latch
            if (issue_valid && issue_ready) begin
                s1_valid   <= 1'b1;
                s1_opcode  <= issue_opcode;
                s1_src1    <= issue_src1;
                s1_src2    <= issue_src2;
                s1_dest_tag <= issue_dest_tag;
                s1_rob_idx <= issue_rob_idx;
                s1_imm     <= issue_imm;
                s1_pc      <= issue_pc;
            end else begin
                s1_valid <= 1'b0;
            end

            // Stage 1 -> Stage 2
            s2_valid         <= s1_valid;
            s2_result        <= s1_result;
            s2_dest_tag      <= s1_dest_tag;
            s2_rob_idx       <= s1_rob_idx;
            s2_branch_taken  <= s1_branch_taken;
            s2_branch_target <= s1_branch_target;
            s2_opcode        <= s1_opcode;

            // Stage 2 -> CDB output
            cdb_valid   <= s2_valid;
            cdb_tag     <= s2_dest_tag;
            cdb_value   <= s2_result;
            cdb_rob_idx <= s2_rob_idx;

            // Branch resolution output
            br_resolved     <= s2_valid && (s2_opcode >= 5'h08 && s2_opcode <= 5'h0e);
            br_taken        <= s2_branch_taken;
            br_target       <= s2_branch_target;
            br_rob_idx_out  <= s2_rob_idx;
        end
    end
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 8: FPU pipe (4-stage pipelined, wraps existing FPU)

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add fpu_pipe module**

```systemverilog
module fpu_pipe(
    input clk,
    input reset,
    // Issue interface
    input issue_valid,
    input [4:0] issue_opcode,
    input [63:0] issue_src1,
    input [63:0] issue_src2,
    input [6:0] issue_dest_tag,
    input [4:0] issue_rob_idx,
    output issue_ready,
    // CDB output (from stage 4)
    output reg cdb_valid,
    output reg [6:0] cdb_tag,
    output reg [63:0] cdb_value,
    output reg [4:0] cdb_rob_idx,
    // Flush
    input flush
);
    // Combinational FPU results
    wire [63:0] fpu_add_result, fpu_sub_result, fpu_mul_result, fpu_div_result;
    wire [63:0] negated_src2 = {~issue_src2[63], issue_src2[62:0]};

    fpu_add fadd_unit(.a(issue_src1), .b(issue_src2), .result(fpu_add_result));
    fpu_add fsub_unit(.a(issue_src1), .b(negated_src2), .result(fpu_sub_result));
    fpu_mul fmul_unit(.a(issue_src1), .b(issue_src2), .result(fpu_mul_result));
    fpu_div fdiv_unit(.a(issue_src1), .b(issue_src2), .result(fpu_div_result));

    // Select result based on opcode
    reg [63:0] fpu_result;
    always @(*) begin
        case (issue_opcode)
            5'h14: fpu_result = fpu_add_result;
            5'h15: fpu_result = fpu_sub_result;
            5'h16: fpu_result = fpu_mul_result;
            5'h17: fpu_result = fpu_div_result;
            default: fpu_result = 64'b0;
        endcase
    end

    // Pipeline stages (4 stages of registers)
    reg s1_valid, s2_valid, s3_valid, s4_valid;
    reg [63:0] s1_result, s2_result, s3_result, s4_result;
    reg [6:0] s1_dest, s2_dest, s3_dest, s4_dest;
    reg [4:0] s1_rob, s2_rob, s3_rob, s4_rob;

    assign issue_ready = !s1_valid || flush;

    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            s1_valid <= 0; s2_valid <= 0; s3_valid <= 0; s4_valid <= 0;
            cdb_valid <= 0;
        end else begin
            // Stage 1: latch inputs and compute (combinational FPU feeds s1_result)
            s1_valid  <= issue_valid && issue_ready;
            s1_result <= fpu_result;
            s1_dest   <= issue_dest_tag;
            s1_rob    <= issue_rob_idx;

            // Stage 2
            s2_valid  <= s1_valid;
            s2_result <= s1_result;
            s2_dest   <= s1_dest;
            s2_rob    <= s1_rob;

            // Stage 3
            s3_valid  <= s2_valid;
            s3_result <= s2_result;
            s3_dest   <= s2_dest;
            s3_rob    <= s2_rob;

            // Stage 4
            s4_valid  <= s3_valid;
            s4_result <= s3_result;
            s4_dest   <= s3_dest;
            s4_rob    <= s3_rob;

            // CDB output
            cdb_valid   <= s4_valid;
            cdb_tag     <= s4_dest;
            cdb_value   <= s4_result;
            cdb_rob_idx <= s4_rob;
        end
    end
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 9: Load/Store queue and unit

**Files:**
- Modify: `tinker.sv` (add new modules)

- [ ] **Step 1: Add load_queue module**

```systemverilog
module load_queue(
    input clk,
    input reset,
    // Dispatch
    input dispatch_en,
    input [63:0] dispatch_base_val,
    input [6:0] dispatch_base_tag,
    input dispatch_base_ready,
    input [63:0] dispatch_imm,
    input [6:0] dispatch_dest_tag,
    input [4:0] dispatch_rob_idx,
    input [4:0] dispatch_opcode,
    // CDB snoop
    input cdb0_valid, input [6:0] cdb0_tag, input [63:0] cdb0_value,
    input cdb1_valid, input [6:0] cdb1_tag, input [63:0] cdb1_value,
    // Store queue forwarding check
    input sq_fwd_valid,
    input [63:0] sq_fwd_data,
    // Memory read port
    output reg mem_read_en,
    output reg [63:0] mem_read_addr,
    input [63:0] mem_read_data,
    // CDB output
    output reg cdb_valid,
    output reg [6:0] cdb_tag,
    output reg [63:0] cdb_value,
    output reg [4:0] cdb_rob_idx,
    // Status
    output full,
    // Flush
    input flush
);
    localparam LQ_SIZE = 8;

    reg valid [0:LQ_SIZE-1];
    reg [63:0] base_val [0:LQ_SIZE-1];
    reg [6:0] base_tag [0:LQ_SIZE-1];
    reg base_ready [0:LQ_SIZE-1];
    reg [63:0] imm [0:LQ_SIZE-1];
    reg [6:0] dest_tag [0:LQ_SIZE-1];
    reg [4:0] rob_idx [0:LQ_SIZE-1];
    reg [4:0] opcode [0:LQ_SIZE-1];
    reg addr_computed [0:LQ_SIZE-1];
    reg [63:0] addr [0:LQ_SIZE-1];
    reg done [0:LQ_SIZE-1];
    reg [4:0] age [0:LQ_SIZE-1];
    reg [4:0] age_counter;

    // Count
    integer ci;
    reg [3:0] cnt;
    always @(*) begin
        cnt = 0;
        for (ci = 0; ci < LQ_SIZE; ci = ci + 1)
            if (valid[ci]) cnt = cnt + 1;
    end
    assign full = (cnt == LQ_SIZE[3:0]);

    // Find entry ready for address computation (base ready, addr not computed)
    integer ai;
    reg found_addr;
    reg [2:0] addr_idx;
    reg [4:0] addr_best_age;
    always @(*) begin
        found_addr = 0;
        addr_idx = 0;
        addr_best_age = 5'h1f;
        for (ai = 0; ai < LQ_SIZE; ai = ai + 1) begin
            if (valid[ai] && base_ready[ai] && !addr_computed[ai] && !done[ai]) begin
                if (!found_addr || age[ai] < addr_best_age) begin
                    found_addr = 1;
                    addr_idx = ai[2:0];
                    addr_best_age = age[ai];
                end
            end
        end
    end

    // Find entry ready for memory read (addr computed, not done)
    integer mi;
    reg found_mem;
    reg [2:0] mem_idx;
    reg [4:0] mem_best_age;
    always @(*) begin
        found_mem = 0;
        mem_idx = 0;
        mem_best_age = 5'h1f;
        for (mi = 0; mi < LQ_SIZE; mi = mi + 1) begin
            if (valid[mi] && addr_computed[mi] && !done[mi]) begin
                if (!found_mem || age[mi] < mem_best_age) begin
                    found_mem = 1;
                    mem_idx = mi[2:0];
                    mem_best_age = age[mi];
                end
            end
        end
    end

    // Free slot
    integer di;
    reg has_free;
    reg [2:0] free_idx;
    always @(*) begin
        has_free = 0;
        free_idx = 0;
        for (di = 0; di < LQ_SIZE; di = di + 1) begin
            if (!valid[di] && !has_free) begin
                has_free = 1;
                free_idx = di[2:0];
            end
        end
    end

    always @(*) begin
        mem_read_en = 0;
        mem_read_addr = 64'd0;
        if (found_mem) begin
            mem_read_en = 1;
            mem_read_addr = addr[mem_idx];
        end
    end

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            for (i = 0; i < LQ_SIZE; i = i + 1)
                valid[i] <= 0;
            age_counter <= 0;
            cdb_valid <= 0;
        end else begin
            cdb_valid <= 0;

            // CDB snoop for base register
            for (i = 0; i < LQ_SIZE; i = i + 1) begin
                if (valid[i] && !base_ready[i]) begin
                    if (cdb0_valid && cdb0_tag == base_tag[i]) begin
                        base_val[i] <= cdb0_value;
                        base_ready[i] <= 1'b1;
                    end else if (cdb1_valid && cdb1_tag == base_tag[i]) begin
                        base_val[i] <= cdb1_value;
                        base_ready[i] <= 1'b1;
                    end
                end
            end

            // Address computation
            if (found_addr) begin
                addr[addr_idx] <= base_val[addr_idx] + imm[addr_idx];
                addr_computed[addr_idx] <= 1'b1;
            end

            // Memory read -> CDB
            if (found_mem) begin
                cdb_valid <= 1'b1;
                cdb_tag <= dest_tag[mem_idx];
                if (sq_fwd_valid)
                    cdb_value <= sq_fwd_data;
                else
                    cdb_value <= mem_read_data;
                cdb_rob_idx <= rob_idx[mem_idx];
                done[mem_idx] <= 1'b1;
                valid[mem_idx] <= 1'b0; // free the entry
            end

            // Dispatch
            if (dispatch_en && has_free) begin
                valid[free_idx]         <= 1'b1;
                base_val[free_idx]      <= dispatch_base_val;
                base_tag[free_idx]      <= dispatch_base_tag;
                base_ready[free_idx]    <= dispatch_base_ready;
                imm[free_idx]           <= dispatch_imm;
                dest_tag[free_idx]      <= dispatch_dest_tag;
                rob_idx[free_idx]       <= dispatch_rob_idx;
                opcode[free_idx]        <= dispatch_opcode;
                addr_computed[free_idx] <= 1'b0;
                done[free_idx]          <= 1'b0;
                age[free_idx]           <= age_counter;
                age_counter             <= age_counter + 1;
            end
        end
    end
endmodule
```

- [ ] **Step 2: Add store_queue module**

```systemverilog
module store_queue(
    input clk,
    input reset,
    // Dispatch
    input dispatch_en,
    input [63:0] dispatch_addr_val,
    input [6:0] dispatch_addr_tag,
    input dispatch_addr_ready,
    input [63:0] dispatch_data_val,
    input [6:0] dispatch_data_tag,
    input dispatch_data_ready,
    input [63:0] dispatch_imm,
    input [4:0] dispatch_rob_idx,
    input [4:0] dispatch_opcode,
    // CDB snoop
    input cdb0_valid, input [6:0] cdb0_tag, input [63:0] cdb0_value,
    input cdb1_valid, input [6:0] cdb1_tag, input [63:0] cdb1_value,
    // Commit (from ROB): oldest store writes to memory
    input commit_en,
    input [4:0] commit_rob_idx,
    output reg mem_write_en,
    output reg [63:0] mem_write_addr,
    output reg [63:0] mem_write_data,
    // Store-to-load forwarding
    input [63:0] fwd_check_addr,
    input fwd_check_en,
    output reg fwd_hit,
    output reg [63:0] fwd_data,
    // Status
    output full,
    // ROB notification: address and data ready
    output reg rob_store_addr_ready,
    output reg [4:0] rob_store_addr_rob_idx,
    output reg [63:0] rob_store_addr_val,
    output reg rob_store_data_ready,
    output reg [4:0] rob_store_data_rob_idx,
    output reg [63:0] rob_store_data_val,
    // Flush
    input flush
);
    localparam SQ_SIZE = 8;

    reg valid [0:SQ_SIZE-1];
    reg [63:0] addr_base_val [0:SQ_SIZE-1];
    reg [6:0] addr_base_tag [0:SQ_SIZE-1];
    reg addr_base_ready [0:SQ_SIZE-1];
    reg [63:0] data_val [0:SQ_SIZE-1];
    reg [6:0] data_tag [0:SQ_SIZE-1];
    reg data_ready [0:SQ_SIZE-1];
    reg [63:0] imm [0:SQ_SIZE-1];
    reg [4:0] rob_idx [0:SQ_SIZE-1];
    reg [4:0] opcode [0:SQ_SIZE-1];
    reg addr_computed [0:SQ_SIZE-1];
    reg [63:0] addr [0:SQ_SIZE-1];
    reg [4:0] age [0:SQ_SIZE-1];
    reg [4:0] age_counter;

    // Count
    integer ci;
    reg [3:0] cnt;
    always @(*) begin
        cnt = 0;
        for (ci = 0; ci < SQ_SIZE; ci = ci + 1)
            if (valid[ci]) cnt = cnt + 1;
    end
    assign full = (cnt == SQ_SIZE[3:0]);

    // Free slot
    integer di;
    reg has_free;
    reg [2:0] free_idx;
    always @(*) begin
        has_free = 0;
        free_idx = 0;
        for (di = 0; di < SQ_SIZE; di = di + 1) begin
            if (!valid[di] && !has_free) begin
                has_free = 1;
                free_idx = di[2:0];
            end
        end
    end

    // Address computation: find oldest ready
    integer ai;
    reg found_addr;
    reg [2:0] addr_idx;
    reg [4:0] addr_best_age;
    always @(*) begin
        found_addr = 0;
        addr_idx = 0;
        addr_best_age = 5'h1f;
        for (ai = 0; ai < SQ_SIZE; ai = ai + 1) begin
            if (valid[ai] && addr_base_ready[ai] && !addr_computed[ai]) begin
                if (!found_addr || age[ai] < addr_best_age) begin
                    found_addr = 1;
                    addr_idx = ai[2:0];
                    addr_best_age = age[ai];
                end
            end
        end
    end

    // Store-to-load forwarding (combinational)
    integer fi;
    always @(*) begin
        fwd_hit = 0;
        fwd_data = 64'd0;
        if (fwd_check_en) begin
            for (fi = 0; fi < SQ_SIZE; fi = fi + 1) begin
                if (valid[fi] && addr_computed[fi] && data_ready[fi] &&
                    addr[fi] == fwd_check_addr) begin
                    fwd_hit = 1;
                    fwd_data = data_val[fi];
                end
            end
        end
    end

    // Commit: find matching store
    integer ki;
    reg found_commit;
    reg [2:0] commit_idx;
    always @(*) begin
        found_commit = 0;
        commit_idx = 0;
        mem_write_en = 0;
        mem_write_addr = 64'd0;
        mem_write_data = 64'd0;
        if (commit_en) begin
            for (ki = 0; ki < SQ_SIZE; ki = ki + 1) begin
                if (valid[ki] && rob_idx[ki] == commit_rob_idx && !found_commit) begin
                    found_commit = 1;
                    commit_idx = ki[2:0];
                    mem_write_en = 1;
                    mem_write_addr = addr[ki];
                    mem_write_data = data_val[ki];
                end
            end
        end
    end

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            for (i = 0; i < SQ_SIZE; i = i + 1)
                valid[i] <= 0;
            age_counter <= 0;
            rob_store_addr_ready <= 0;
            rob_store_data_ready <= 0;
        end else begin
            rob_store_addr_ready <= 0;
            rob_store_data_ready <= 0;

            // CDB snoop
            for (i = 0; i < SQ_SIZE; i = i + 1) begin
                if (valid[i]) begin
                    if (!addr_base_ready[i]) begin
                        if (cdb0_valid && cdb0_tag == addr_base_tag[i]) begin
                            addr_base_val[i] <= cdb0_value;
                            addr_base_ready[i] <= 1'b1;
                        end else if (cdb1_valid && cdb1_tag == addr_base_tag[i]) begin
                            addr_base_val[i] <= cdb1_value;
                            addr_base_ready[i] <= 1'b1;
                        end
                    end
                    if (!data_ready[i]) begin
                        if (cdb0_valid && cdb0_tag == data_tag[i]) begin
                            data_val[i] <= cdb0_value;
                            data_ready[i] <= 1'b1;
                            rob_store_data_ready <= 1;
                            rob_store_data_rob_idx <= rob_idx[i];
                            rob_store_data_val <= cdb0_value;
                        end else if (cdb1_valid && cdb1_tag == data_tag[i]) begin
                            data_val[i] <= cdb1_value;
                            data_ready[i] <= 1'b1;
                            rob_store_data_ready <= 1;
                            rob_store_data_rob_idx <= rob_idx[i];
                            rob_store_data_val <= cdb1_value;
                        end
                    end
                end
            end

            // Address computation
            if (found_addr) begin
                addr[addr_idx] <= addr_base_val[addr_idx] + imm[addr_idx];
                addr_computed[addr_idx] <= 1'b1;
                rob_store_addr_ready <= 1;
                rob_store_addr_rob_idx <= rob_idx[addr_idx];
                rob_store_addr_val <= addr_base_val[addr_idx] + imm[addr_idx];
            end

            // Commit: free the entry
            if (commit_en && found_commit)
                valid[commit_idx] <= 1'b0;

            // Dispatch
            if (dispatch_en && has_free) begin
                valid[free_idx]           <= 1'b1;
                addr_base_val[free_idx]   <= dispatch_addr_val;
                addr_base_tag[free_idx]   <= dispatch_addr_tag;
                addr_base_ready[free_idx] <= dispatch_addr_ready;
                data_val[free_idx]        <= dispatch_data_val;
                data_tag[free_idx]        <= dispatch_data_tag;
                data_ready[free_idx]      <= dispatch_data_ready;
                imm[free_idx]             <= dispatch_imm;
                rob_idx[free_idx]         <= dispatch_rob_idx;
                opcode[free_idx]          <= dispatch_opcode;
                addr_computed[free_idx]   <= 1'b0;
                age[free_idx]             <= age_counter;
                age_counter               <= age_counter + 1;
            end
        end
    end
endmodule
```

- [ ] **Step 3: Compile check**

---

### Task 10: Reorder buffer (32 entries)

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add rob module**

```systemverilog
module rob(
    input clk,
    input reset,
    // Allocate (from decode, up to 2 per cycle)
    input alloc_en1,
    input [2:0] alloc_type1,      // ALU=0,FPU=1,LOAD=2,STORE=3,BRANCH=4,HALT=5
    input [4:0] alloc_arch_rd1,
    input [6:0] alloc_old_phys1,
    input [6:0] alloc_new_phys1,
    input [63:0] alloc_pc1,
    input alloc_branch_pred1,
    input [63:0] alloc_branch_target1,
    output [4:0] alloc_idx1,

    input alloc_en2,
    input [2:0] alloc_type2,
    input [4:0] alloc_arch_rd2,
    input [6:0] alloc_old_phys2,
    input [6:0] alloc_new_phys2,
    input [63:0] alloc_pc2,
    input alloc_branch_pred2,
    input [63:0] alloc_branch_target2,
    output [4:0] alloc_idx2,

    // CDB completion (2 buses)
    input cdb0_valid, input [4:0] cdb0_rob_idx, input [63:0] cdb0_value,
    input cdb1_valid, input [4:0] cdb1_rob_idx, input [63:0] cdb1_value,

    // Store queue notifications
    input sq_addr_ready,
    input [4:0] sq_addr_rob_idx,
    input [63:0] sq_addr_val,
    input sq_data_ready,
    input [4:0] sq_data_rob_idx,
    input [63:0] sq_data_val,

    // Branch resolution (from ALU)
    input br_resolved,
    input br_taken,
    input [63:0] br_target,
    input [4:0] br_rob_idx,

    // Commit outputs (up to 2 per cycle)
    output reg commit_en1,
    output reg [2:0] commit_type1,
    output reg [4:0] commit_arch_rd1,
    output reg [6:0] commit_old_phys1,
    output reg [6:0] commit_new_phys1,
    output reg [4:0] commit_rob_idx1,
    output reg [63:0] commit_value1,

    output reg commit_en2,
    output reg [2:0] commit_type2,
    output reg [4:0] commit_arch_rd2,
    output reg [6:0] commit_old_phys2,
    output reg [6:0] commit_new_phys2,
    output reg [4:0] commit_rob_idx2,
    output reg [63:0] commit_value2,

    // Misprediction
    output reg mispredict,
    output reg [63:0] mispredict_target,
    output reg [4:0] mispredict_rob_idx,

    // Status
    output can_alloc2, // room for 2 entries
    output reg halt_committed,

    // Flush
    output reg flush_all
);
    localparam ROB_SIZE = 32;

    reg valid [0:ROB_SIZE-1];
    reg complete [0:ROB_SIZE-1];
    reg [2:0] itype [0:ROB_SIZE-1];
    reg [4:0] arch_rd [0:ROB_SIZE-1];
    reg [6:0] old_phys [0:ROB_SIZE-1];
    reg [6:0] new_phys [0:ROB_SIZE-1];
    reg [63:0] pc [0:ROB_SIZE-1];
    reg branch_pred [0:ROB_SIZE-1];
    reg [63:0] branch_target_pred [0:ROB_SIZE-1];
    reg branch_actual_taken [0:ROB_SIZE-1];
    reg [63:0] branch_actual_target [0:ROB_SIZE-1];
    reg branch_resolved_flag [0:ROB_SIZE-1];
    reg [63:0] store_addr [0:ROB_SIZE-1];
    reg [63:0] store_data [0:ROB_SIZE-1];
    reg store_addr_ready [0:ROB_SIZE-1];
    reg store_data_ready [0:ROB_SIZE-1];
    reg [63:0] result [0:ROB_SIZE-1];

    reg [4:0] head, tail;
    reg [5:0] count;

    assign can_alloc2 = (count <= 6'd30); // room for at least 2
    assign alloc_idx1 = tail;
    assign alloc_idx2 = tail + 5'd1;

    // Commit logic (combinational for outputs, sequential for state)
    wire head_valid = valid[head];
    wire head_complete = complete[head];
    wire head_is_store = (itype[head] == 3'd3);
    wire head_is_halt = (itype[head] == 3'd5);
    wire head_store_ready = store_addr_ready[head] && store_data_ready[head];
    wire can_commit1 = head_valid && (head_complete || (head_is_store && head_store_ready) || head_is_halt);

    wire [4:0] head_plus1 = head + 5'd1;
    wire next_valid = valid[head_plus1];
    wire next_complete = complete[head_plus1];
    wire next_is_store = (itype[head_plus1] == 3'd3);
    wire next_is_halt = (itype[head_plus1] == 3'd5);
    wire next_store_ready = store_addr_ready[head_plus1] && store_data_ready[head_plus1];
    // Only 1 store commit per cycle, so if head is store, don't commit next store
    wire can_commit2 = can_commit1 && next_valid &&
                       (next_complete || (next_is_store && next_store_ready) || next_is_halt) &&
                       !(head_is_store && next_is_store);

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            head <= 5'd0;
            tail <= 5'd0;
            count <= 6'd0;
            halt_committed <= 1'b0;
            mispredict <= 1'b0;
            flush_all <= 1'b0;
            commit_en1 <= 0;
            commit_en2 <= 0;
            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                valid[i] <= 0;
                complete[i] <= 0;
                branch_resolved_flag[i] <= 0;
                store_addr_ready[i] <= 0;
                store_data_ready[i] <= 0;
            end
        end else begin
            mispredict <= 1'b0;
            flush_all <= 1'b0;
            commit_en1 <= 1'b0;
            commit_en2 <= 1'b0;

            // CDB completion
            if (cdb0_valid && valid[cdb0_rob_idx]) begin
                complete[cdb0_rob_idx] <= 1'b1;
                result[cdb0_rob_idx] <= cdb0_value;
            end
            if (cdb1_valid && valid[cdb1_rob_idx]) begin
                complete[cdb1_rob_idx] <= 1'b1;
                result[cdb1_rob_idx] <= cdb1_value;
            end

            // Store queue notifications
            if (sq_addr_ready && valid[sq_addr_rob_idx]) begin
                store_addr_ready[sq_addr_rob_idx] <= 1'b1;
                store_addr[sq_addr_rob_idx] <= sq_addr_val;
            end
            if (sq_data_ready && valid[sq_data_rob_idx]) begin
                store_data_ready[sq_data_rob_idx] <= 1'b1;
                store_data[sq_data_rob_idx] <= sq_data_val;
            end

            // Branch resolution
            if (br_resolved && valid[br_rob_idx]) begin
                branch_resolved_flag[br_rob_idx] <= 1'b1;
                branch_actual_taken[br_rob_idx] <= br_taken;
                branch_actual_target[br_rob_idx] <= br_target;
                // Check misprediction
                if (br_taken != branch_pred[br_rob_idx] ||
                    (br_taken && br_target != branch_target_pred[br_rob_idx])) begin
                    mispredict <= 1'b1;
                    mispredict_target <= br_taken ? br_target : (pc[br_rob_idx] + 64'd4);
                    mispredict_rob_idx <= br_rob_idx;
                    flush_all <= 1'b1;
                    // Flush entries after mispredicted branch
                    for (i = 0; i < ROB_SIZE; i = i + 1) begin
                        // Entries between br_rob_idx+1 and tail are on wrong path
                        if (valid[i] && i[4:0] != br_rob_idx) begin
                            // Use age comparison via circular buffer logic
                            if (((i[4:0] > br_rob_idx) && (i[4:0] < tail)) ||
                                ((tail <= br_rob_idx) && (i[4:0] > br_rob_idx || i[4:0] < tail))) begin
                                valid[i] <= 1'b0;
                            end
                        end
                    end
                    tail <= br_rob_idx + 5'd1;
                    count <= (br_rob_idx >= head) ? (br_rob_idx - head + 5'd1) :
                             (ROB_SIZE[5:0] - {1'b0, head} + {1'b0, br_rob_idx} + 6'd1);
                end
            end

            // Commit
            if (can_commit1 && !flush_all) begin
                if (head_is_halt) begin
                    halt_committed <= 1'b1;
                    valid[head] <= 1'b0;
                    head <= head + 5'd1;
                    count <= count - 6'd1;
                end else begin
                    commit_en1 <= 1'b1;
                    commit_type1 <= itype[head];
                    commit_arch_rd1 <= arch_rd[head];
                    commit_old_phys1 <= old_phys[head];
                    commit_new_phys1 <= new_phys[head];
                    commit_rob_idx1 <= head;
                    commit_value1 <= result[head];
                    valid[head] <= 1'b0;
                    head <= head + 5'd1;
                    count <= count - 6'd1;

                    if (can_commit2) begin
                        if (next_is_halt) begin
                            halt_committed <= 1'b1;
                            valid[head_plus1] <= 1'b0;
                            head <= head + 5'd2;
                            count <= count - 6'd2;
                        end else begin
                            commit_en2 <= 1'b1;
                            commit_type2 <= itype[head_plus1];
                            commit_arch_rd2 <= arch_rd[head_plus1];
                            commit_old_phys2 <= old_phys[head_plus1];
                            commit_new_phys2 <= new_phys[head_plus1];
                            commit_rob_idx2 <= head_plus1;
                            commit_value2 <= result[head_plus1];
                            valid[head_plus1] <= 1'b0;
                            head <= head + 5'd2;
                            count <= count - 6'd2;
                        end
                    end
                end
            end

            // Allocate
            if (alloc_en1 && !flush_all) begin
                valid[tail] <= 1'b1;
                complete[tail] <= 1'b0;
                itype[tail] <= alloc_type1;
                arch_rd[tail] <= alloc_arch_rd1;
                old_phys[tail] <= alloc_old_phys1;
                new_phys[tail] <= alloc_new_phys1;
                pc[tail] <= alloc_pc1;
                branch_pred[tail] <= alloc_branch_pred1;
                branch_target_pred[tail] <= alloc_branch_target1;
                branch_resolved_flag[tail] <= 1'b0;
                store_addr_ready[tail] <= 1'b0;
                store_data_ready[tail] <= 1'b0;
                tail <= tail + 5'd1;
                count <= count + 6'd1;

                if (alloc_en2) begin
                    valid[tail + 5'd1] <= 1'b1;
                    complete[tail + 5'd1] <= 1'b0;
                    itype[tail + 5'd1] <= alloc_type2;
                    arch_rd[tail + 5'd1] <= alloc_arch_rd2;
                    old_phys[tail + 5'd1] <= alloc_old_phys2;
                    new_phys[tail + 5'd1] <= alloc_new_phys2;
                    pc[tail + 5'd1] <= alloc_pc2;
                    branch_pred[tail + 5'd1] <= alloc_branch_pred2;
                    branch_target_pred[tail + 5'd1] <= alloc_branch_target2;
                    branch_resolved_flag[tail + 5'd1] <= 1'b0;
                    store_addr_ready[tail + 5'd1] <= 1'b0;
                    store_data_ready[tail + 5'd1] <= 1'b0;
                    tail <= tail + 5'd2;
                    count <= count + 6'd2;
                end
            end
        end
    end
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 11: Fetch unit with branch predictor

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add fetch_unit module**

```systemverilog
module fetch_unit(
    input clk,
    input reset,
    // Memory fetch port
    output reg [63:0] fetch_addr,
    input [511:0] fetch_data, // 16 instructions
    // Output to decode (2 instructions per cycle)
    output reg out_valid1,
    output reg [31:0] out_instr1,
    output reg [63:0] out_pc1,
    output reg out_valid2,
    output reg [31:0] out_instr2,
    output reg [63:0] out_pc2,
    // Backpressure from decode
    input decode_stall,
    // Branch predictor update (from ALU resolution)
    input bp_update_en,
    input [63:0] bp_update_pc,
    input bp_update_taken,
    // Flush + redirect
    input flush,
    input [63:0] redirect_pc
);
    // Branch History Table: 256 entries, 1-bit
    reg bht [0:255];

    // Fetch buffer: 16-entry FIFO of {pc, instruction}
    reg [95:0] fbuf [0:15]; // {pc[63:0], instr[31:0]}
    reg [4:0] fb_head, fb_tail;
    reg [4:0] fb_count;

    reg [63:0] pc;

    wire [7:0] bht_idx = pc[9:2];
    wire fb_has2 = (fb_count >= 5'd2);
    wire fb_has1 = (fb_count >= 5'd1);
    wire fb_has_room = (fb_count <= 5'd0); // refetch when buffer is empty or low

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc <= `START;
            fb_head <= 0;
            fb_tail <= 0;
            fb_count <= 0;
            out_valid1 <= 0;
            out_valid2 <= 0;
            for (i = 0; i < 256; i = i + 1)
                bht[i] <= 1'b0; // predict not-taken initially
        end else if (flush) begin
            pc <= redirect_pc;
            fb_head <= 0;
            fb_tail <= 0;
            fb_count <= 0;
            out_valid1 <= 0;
            out_valid2 <= 0;
        end else begin
            // BHT update
            if (bp_update_en)
                bht[bp_update_pc[9:2]] <= bp_update_taken;

            // Supply up to 2 instructions to decode
            if (!decode_stall) begin
                if (fb_has2) begin
                    out_valid1 <= 1'b1;
                    out_instr1 <= fbuf[fb_head][31:0];
                    out_pc1    <= fbuf[fb_head][95:32];
                    out_valid2 <= 1'b1;
                    out_instr2 <= fbuf[fb_head + 5'd1][31:0];
                    out_pc2    <= fbuf[fb_head + 5'd1][95:32];
                    fb_head  <= fb_head + 5'd2;
                    fb_count <= fb_count - 5'd2;
                end else if (fb_has1) begin
                    out_valid1 <= 1'b1;
                    out_instr1 <= fbuf[fb_head][31:0];
                    out_pc1    <= fbuf[fb_head][95:32];
                    out_valid2 <= 1'b0;
                    fb_head  <= fb_head + 5'd1;
                    fb_count <= fb_count - 5'd1;
                end else begin
                    out_valid1 <= 1'b0;
                    out_valid2 <= 1'b0;
                end
            end else begin
                out_valid1 <= 1'b0;
                out_valid2 <= 1'b0;
            end

            // Fetch: fill buffer when there's room
            if (fb_count <= 5'd2) begin
                // Load up to 16 instructions from fetch_data
                for (i = 0; i < 16; i = i + 1) begin
                    if (fb_count + i[4:0] < 5'd16) begin
                        fbuf[fb_tail + i[4:0]] <= {pc + (i * 4), fetch_data[i*32 +: 32]};
                    end
                end
                // Determine how many we actually loaded
                if (fb_count <= 5'd0) begin
                    fb_tail <= fb_tail + 5'd16;
                    fb_count <= fb_count + 5'd16;
                    pc <= pc + 64'd64;
                end else begin
                    // Partial fill: fill what we can
                    fb_tail <= fb_tail + (5'd16 - fb_count);
                    pc <= pc + {59'd0, (5'd16 - fb_count), 2'b00};
                    fb_count <= 5'd16;
                end
            end
        end
    end

    always @(*) begin
        fetch_addr = pc;
    end
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 12: CDB arbiter

**Files:**
- Modify: `tinker.sv` (add new module)

- [ ] **Step 1: Add cdb_arbiter module**

```systemverilog
module cdb_arbiter(
    // Inputs from functional units (6 producers)
    input alu0_valid, input [6:0] alu0_tag, input [63:0] alu0_value, input [4:0] alu0_rob,
    input alu1_valid, input [6:0] alu1_tag, input [63:0] alu1_value, input [4:0] alu1_rob,
    input fpu0_valid, input [6:0] fpu0_tag, input [63:0] fpu0_value, input [4:0] fpu0_rob,
    input fpu1_valid, input [6:0] fpu1_tag, input [63:0] fpu1_value, input [4:0] fpu1_rob,
    input lsu0_valid, input [6:0] lsu0_tag, input [63:0] lsu0_value, input [4:0] lsu0_rob,
    input lsu1_valid, input [6:0] lsu1_tag, input [63:0] lsu1_value, input [4:0] lsu1_rob,

    // CDB bus 0: ALU0 > FPU0 > LSU0
    output reg cdb0_valid, output reg [6:0] cdb0_tag, output reg [63:0] cdb0_value, output reg [4:0] cdb0_rob,
    // CDB bus 1: ALU1 > FPU1 > LSU1
    output reg cdb1_valid, output reg [6:0] cdb1_tag, output reg [63:0] cdb1_value, output reg [4:0] cdb1_rob,

    // Stall signals back to producers (hold your result)
    output alu0_stall, output alu1_stall,
    output fpu0_stall, output fpu1_stall,
    output lsu0_stall, output lsu1_stall
);
    // Bus 0 priority: ALU0 > FPU0 > LSU0
    always @(*) begin
        cdb0_valid = 0; cdb0_tag = 0; cdb0_value = 0; cdb0_rob = 0;
        if (alu0_valid) begin
            cdb0_valid = 1; cdb0_tag = alu0_tag; cdb0_value = alu0_value; cdb0_rob = alu0_rob;
        end else if (fpu0_valid) begin
            cdb0_valid = 1; cdb0_tag = fpu0_tag; cdb0_value = fpu0_value; cdb0_rob = fpu0_rob;
        end else if (lsu0_valid) begin
            cdb0_valid = 1; cdb0_tag = lsu0_tag; cdb0_value = lsu0_value; cdb0_rob = lsu0_rob;
        end
    end

    // Bus 1 priority: ALU1 > FPU1 > LSU1
    always @(*) begin
        cdb1_valid = 0; cdb1_tag = 0; cdb1_value = 0; cdb1_rob = 0;
        if (alu1_valid) begin
            cdb1_valid = 1; cdb1_tag = alu1_tag; cdb1_value = alu1_value; cdb1_rob = alu1_rob;
        end else if (fpu1_valid) begin
            cdb1_valid = 1; cdb1_tag = fpu1_tag; cdb1_value = fpu1_value; cdb1_rob = fpu1_rob;
        end else if (lsu1_valid) begin
            cdb1_valid = 1; cdb1_tag = lsu1_tag; cdb1_value = lsu1_value; cdb1_rob = lsu1_rob;
        end
    end

    // Stall = you're valid but didn't win the bus
    assign alu0_stall = alu0_valid && !cdb0_valid; // ALU0 always wins bus 0 if valid
    assign fpu0_stall = fpu0_valid && alu0_valid;
    assign lsu0_stall = lsu0_valid && (alu0_valid || fpu0_valid);
    assign alu1_stall = alu1_valid && !cdb1_valid;
    assign fpu1_stall = fpu1_valid && alu1_valid;
    assign lsu1_stall = lsu1_valid && (alu1_valid || fpu1_valid);
endmodule
```

- [ ] **Step 2: Compile check**

---

### Task 13: Top-level tinker_core wiring

**Files:**
- Modify: `tinker.sv` (replace tinker_core module, lines 1-192)

- [ ] **Step 1: Write the new tinker_core top-level module**

This is the largest task. It instantiates all submodules and wires them together. It also contains the decode/rename/dispatch logic inline (since it's highly interconnected).

The full wiring module connects:
1. `fetch_unit` -> decode/rename logic -> dispatch logic
2. Dispatch -> reservation stations (rs_alu x2, rs_fpu x2, load_queue, store_queue)
3. Reservation stations -> functional units (alu_pipe x2, fpu_pipe x2)
4. Functional units -> cdb_arbiter -> CDB buses
5. CDB -> reservation stations, ROB, phys_reg_file
6. ROB commit -> reg_file, free_list, store_queue (memory write)
7. ROB mispredict -> flush signals, RAT restore, PC redirect

This task will be implemented as a single large module with inline decode/rename/dispatch logic and submodule instantiations.

- [ ] **Step 2: Compile check**

Run: `iverilog -g2012 -o /dev/null tinker.sv`

- [ ] **Step 3: Run existing testbench**

Run: `iverilog -g2012 -o tinker_tb tinker_tb.sv && vvp tinker_tb`
Expected: `r1 = 8`, `hlt = 1`, `PASS`

---

### Task 14: Update testbench for new internals

**Files:**
- Modify: `tinker_tb.sv`

The testbench accesses `dut.memory.bytes` and `dut.reg_file.registers` by hierarchical path. These paths must still work with the new module hierarchy. Verify and fix if needed.

- [ ] **Step 1: Update hierarchical paths if module names changed**
- [ ] **Step 2: Increase simulation cycles (OOO pipeline may need more cycles to drain)**
- [ ] **Step 3: Run and verify PASS**

---

### Task 15: Additional test programs

**Files:**
- Create: `tinker_ooo_tb.sv`

- [ ] **Step 1: Write test for independent instructions (should exploit ILP)**

```
addi r1, #1
addi r2, #2
addi r3, #3
addi r4, #4
halt
```

- [ ] **Step 2: Write test for data dependency chain**

```
addi r1, #5
addi r1, #3   (depends on r1)
halt
```

- [ ] **Step 3: Write test for branch**

```
movi r1, #1
brnz r2, r1   (r1 != 0, should branch to r2=0... but r2=0, so branch to addr 0)
```

- [ ] **Step 4: Write test for load/store**

```
movi r1, #100
store r1, r2   (store r2 to mem[r1+0])
load r3, r1    (load from mem[r1+0] into r3)
halt
```

- [ ] **Step 5: Compile and run all tests**

Run: `iverilog -g2012 -o tinker_ooo_tb tinker_ooo_tb.sv && vvp tinker_ooo_tb`
