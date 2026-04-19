`define MEM_SIZE (1024*512)
`define START 64'h2000

module tinker_core(
    input clk,
    input reset,
    output logic hlt
);

    // ================================================================
    // ROB type constants
    // ================================================================
    localparam ITYPE_ALU    = 3'd0;
    localparam ITYPE_FPU    = 3'd1;
    localparam ITYPE_LOAD   = 3'd2;
    localparam ITYPE_STORE  = 3'd3;
    localparam ITYPE_BRANCH = 3'd4;
    localparam ITYPE_HALT   = 3'd5;

    // ================================================================
    // Wires: Fetch Unit <-> Memory
    // ================================================================
    wire [63:0]  fu_fetch_addr;
    wire [511:0] fu_fetch_data;
    wire         fu_out_valid1, fu_out_valid2;
    wire [31:0]  fu_out_instr1, fu_out_instr2;
    wire [63:0]  fu_out_pc1, fu_out_pc2;

    // ================================================================
    // Wires: Decode (2 instruction decoders)
    // ================================================================
    wire [4:0]  opcode1, rd1, rs1, rt1;
    wire [11:0] L1;
    wire [4:0]  opcode2, rd2, rs2, rt2;
    wire [11:0] L2;

    // ================================================================
    // Wires: CDB buses (2)
    // ================================================================
    wire        cdb0_valid, cdb1_valid;
    wire [6:0]  cdb0_tag, cdb1_tag;
    wire [63:0] cdb0_value, cdb1_value;
    wire [4:0]  cdb0_rob, cdb1_rob;

    // ================================================================
    // Wires: ROB
    // ================================================================
    wire [4:0]  rob_alloc_idx1, rob_alloc_idx2;
    wire        rob_can_alloc2;
    wire        rob_mispredict, rob_flush_all;
    wire [63:0] rob_mispredict_target;
    wire [4:0]  rob_mispredict_rob_idx;
    wire [1:0]  rob_mispredict_snap_id;
    wire        rob_has_unresolved_branch;
    wire        rob_commit_en1, rob_commit_en2;
    wire [2:0]  rob_commit_type1, rob_commit_type2;
    wire [4:0]  rob_commit_arch_rd1, rob_commit_arch_rd2;
    wire [6:0]  rob_commit_old_phys1, rob_commit_old_phys2;
    wire [6:0]  rob_commit_new_phys1, rob_commit_new_phys2;
    wire [4:0]  rob_commit_rob_idx1, rob_commit_rob_idx2;
    wire [63:0] rob_commit_value1, rob_commit_value2;
    wire        rob_halt_committed;

    // ================================================================
    // Wires: Free List
    // ================================================================
    wire [6:0]  fl_deq_preg1, fl_deq_preg2;
    wire        fl_can_alloc2;

    // ================================================================
    // Wires: RAT read ports
    // ================================================================
    wire [6:0]  rat_read_preg1, rat_read_preg2, rat_read_preg3, rat_read_preg4;

    // ================================================================
    // Wires: Physical Register File read ports
    // ================================================================
    wire [63:0] prf_read_data1, prf_read_data2, prf_read_data3, prf_read_data4;
    wire        prf_read_ready1, prf_read_ready2, prf_read_ready3, prf_read_ready4;

    // ================================================================
    // Wires: Reservation Stations (4: 2 ALU, 2 FPU)
    // ================================================================
    wire        rs_alu0_full, rs_alu1_full, rs_fpu0_full, rs_fpu1_full;
    wire        rs_alu0_issue_valid, rs_alu1_issue_valid;
    wire        rs_fpu0_issue_valid, rs_fpu1_issue_valid;
    wire [4:0]  rs_alu0_issue_opcode, rs_alu1_issue_opcode;
    wire [4:0]  rs_fpu0_issue_opcode, rs_fpu1_issue_opcode;
    wire [63:0] rs_alu0_issue_src1, rs_alu1_issue_src1;
    wire [63:0] rs_fpu0_issue_src1, rs_fpu1_issue_src1;
    wire [63:0] rs_alu0_issue_src2, rs_alu1_issue_src2;
    wire [63:0] rs_fpu0_issue_src2, rs_fpu1_issue_src2;
    wire [6:0]  rs_alu0_issue_dest, rs_alu1_issue_dest;
    wire [6:0]  rs_fpu0_issue_dest, rs_fpu1_issue_dest;
    wire [4:0]  rs_alu0_issue_rob, rs_alu1_issue_rob;
    wire [4:0]  rs_fpu0_issue_rob, rs_fpu1_issue_rob;
    wire [63:0] rs_alu0_issue_imm, rs_alu1_issue_imm;
    wire [63:0] rs_fpu0_issue_imm, rs_fpu1_issue_imm;
    wire [63:0] rs_alu0_issue_pc, rs_alu1_issue_pc;
    wire [63:0] rs_fpu0_issue_pc, rs_fpu1_issue_pc;

    // ================================================================
    // Wires: ALU Pipes (2)
    // ================================================================
    wire        alu0_cdb_valid, alu1_cdb_valid;
    wire [6:0]  alu0_cdb_tag, alu1_cdb_tag;
    wire [63:0] alu0_cdb_value, alu1_cdb_value;
    wire [4:0]  alu0_cdb_rob, alu1_cdb_rob;
    wire        alu0_issue_ready, alu1_issue_ready;
    wire        alu0_br_resolved, alu1_br_resolved;
    wire        alu0_br_taken, alu1_br_taken;
    wire [63:0] alu0_br_target, alu1_br_target;
    wire [4:0]  alu0_br_rob_idx, alu1_br_rob_idx;

    // ================================================================
    // Wires: FPU Pipes (2)
    // ================================================================
    wire        fpu0_cdb_valid, fpu1_cdb_valid;
    wire [6:0]  fpu0_cdb_tag, fpu1_cdb_tag;
    wire [63:0] fpu0_cdb_value, fpu1_cdb_value;
    wire [4:0]  fpu0_cdb_rob, fpu1_cdb_rob;
    wire        fpu0_issue_ready, fpu1_issue_ready;

    // ================================================================
    // Wires: Load Queue
    // ================================================================
    wire        lq_full;
    wire        lq_mem_read_en;
    wire [63:0] lq_mem_read_addr;
    wire [63:0] lq_mem_read_data;
    wire        lq_cdb_valid;
    wire [6:0]  lq_cdb_tag;
    wire [63:0] lq_cdb_value;
    wire [4:0]  lq_cdb_rob;
    wire        lq_br_resolved;
    wire        lq_br_taken;
    wire [63:0] lq_br_target;
    wire [4:0]  lq_br_rob_idx;

    // ================================================================
    // Wires: Store Queue
    // ================================================================
    wire        sq_full;
    wire        sq_mem_write_en;
    wire [63:0] sq_mem_write_addr;
    wire [63:0] sq_mem_write_data;
    wire        sq_fwd_hit;
    wire [63:0] sq_fwd_data;
    wire        sq_rob_store_addr_ready, sq_rob_store_data_ready;
    wire [4:0]  sq_rob_store_addr_ready_idx;
    wire [4:0]  sq_rob_store_data_ready_idx;
    wire [63:0] sq_rob_store_addr_value;
    wire [63:0] sq_rob_store_ready_value;

    // ================================================================
    // Wires: CDB Arbiter stalls
    // ================================================================
    wire cdb_alu0_stall, cdb_fpu0_stall, cdb_lsu0_stall;
    wire cdb_alu1_stall, cdb_fpu1_stall, cdb_lsu1_stall;

    // ================================================================
    // Flush signal (from ROB misprediction)
    // ================================================================
    wire flush = rob_flush_all;
    // Branch redirects should only flush the frontend/rename state. Older in-flight backend
    // work must survive so it can still complete and retire ahead of the branch.
    wire pipe_kill = rob_halt_committed || hlt;

    // ================================================================
    // Branch resolution: combine from ALU pipes + LQ with overflow queue
    // When multiple branches resolve simultaneously, one is deferred to next cycle
    // ================================================================
    reg        br_deferred_valid;
    reg        br_deferred_taken;
    reg [63:0] br_deferred_target;
    reg [4:0]  br_deferred_rob_idx;

    // Count how many new sources are resolving this cycle
    wire [1:0] br_resolve_count = {1'b0, alu0_br_resolved} + {1'b0, alu1_br_resolved} + {1'b0, lq_br_resolved};

    // If a branch resolution was deferred from last cycle, service it first so it can't be
    // overwritten by a newer branch resolving in the same cycle.
    wire        br_resolved_combined = br_deferred_valid || alu0_br_resolved || alu1_br_resolved || lq_br_resolved;
    wire        br_taken_combined    = br_deferred_valid ? br_deferred_taken :
                                       alu0_br_resolved ? alu0_br_taken :
                                       alu1_br_resolved ? alu1_br_taken :
                                       lq_br_resolved   ? lq_br_taken : 1'b0;
    wire [63:0] br_target_combined   = br_deferred_valid ? br_deferred_target :
                                       alu0_br_resolved ? alu0_br_target :
                                       alu1_br_resolved ? alu1_br_target :
                                       lq_br_resolved   ? lq_br_target : 64'd0;
    wire [4:0]  br_rob_idx_combined  = br_deferred_valid ? br_deferred_rob_idx :
                                       alu0_br_resolved ? alu0_br_rob_idx :
                                       alu1_br_resolved ? alu1_br_rob_idx :
                                       lq_br_resolved   ? lq_br_rob_idx : 5'd0;

    // If we're servicing a deferred branch, defer the oldest new resolution (if any).
    // Otherwise, if multiple new resolutions arrive together, defer the second one.
    wire br_second_valid = br_deferred_valid ? (alu0_br_resolved || alu1_br_resolved || lq_br_resolved) :
                                             (br_resolve_count > 2'd1);
    wire        br_second_taken  = br_deferred_valid ? (alu0_br_resolved ? alu0_br_taken :
                                                        alu1_br_resolved ? alu1_br_taken :
                                                        lq_br_taken) :
                                   alu0_br_resolved && alu1_br_resolved ? alu1_br_taken :
                                   alu0_br_resolved && lq_br_resolved   ? lq_br_taken :
                                   alu1_br_resolved && lq_br_resolved   ? lq_br_taken : 1'b0;
    wire [63:0] br_second_target = br_deferred_valid ? (alu0_br_resolved ? alu0_br_target :
                                                         alu1_br_resolved ? alu1_br_target :
                                                         lq_br_target) :
                                   alu0_br_resolved && alu1_br_resolved ? alu1_br_target :
                                   alu0_br_resolved && lq_br_resolved   ? lq_br_target :
                                   alu1_br_resolved && lq_br_resolved   ? lq_br_target : 64'd0;
    wire [4:0]  br_second_rob    = br_deferred_valid ? (alu0_br_resolved ? alu0_br_rob_idx :
                                                         alu1_br_resolved ? alu1_br_rob_idx :
                                                         lq_br_rob_idx) :
                                   alu0_br_resolved && alu1_br_resolved ? alu1_br_rob_idx :
                                   alu0_br_resolved && lq_br_resolved   ? lq_br_rob_idx :
                                   alu1_br_resolved && lq_br_resolved   ? lq_br_rob_idx : 5'd0;

    always @(posedge clk or posedge reset) begin
        if (reset || pipe_kill) begin
            br_deferred_valid <= 1'b0;
        end else if (br_second_valid) begin
            // A second branch resolved this cycle; defer it to next cycle
            br_deferred_valid     <= 1'b1;
            br_deferred_taken     <= br_second_taken;
            br_deferred_target    <= br_second_target;
            br_deferred_rob_idx   <= br_second_rob;
        end else begin
            br_deferred_valid <= 1'b0;
        end
    end

    // ================================================================
    // Round-robin state for RS assignment
    // ================================================================
    reg alu_rr, fpu_rr; // 0=pipe0, 1=pipe1

    // ================================================================
    // DECODE / RENAME / DISPATCH logic
    // ================================================================

    // Sign-extend 12-bit L to 64 bits
    wire [63:0] imm1 = {{52{L1[11]}}, L1};
    wire [63:0] imm2 = {{52{L2[11]}}, L2};

    // Instruction classification for slot 1
    wire is_alu1  = (opcode1 >= 5'h18 && opcode1 <= 5'h1d) ||
                    (opcode1 >= 5'h00 && opcode1 <= 5'h07) ||
                    (opcode1 >= 5'h08 && opcode1 <= 5'h0e && opcode1 != 5'h0d) ||
                    (opcode1 == 5'h11) || (opcode1 == 5'h12);
    wire is_fpu1  = (opcode1 >= 5'h14 && opcode1 <= 5'h17);
    wire is_load1 = (opcode1 == 5'h10);
    wire is_store1= (opcode1 == 5'h13);
    wire is_halt1 = (opcode1 == 5'h0f);
    wire is_branch1 = (opcode1 >= 5'h08 && opcode1 <= 5'h0e) && (opcode1 != 5'h0d);
    wire is_call1 = (opcode1 == 5'h0c);
    wire is_return1 = (opcode1 == 5'h0d);

    // Instruction classification for slot 2
    wire is_alu2  = (opcode2 >= 5'h18 && opcode2 <= 5'h1d) ||
                    (opcode2 >= 5'h00 && opcode2 <= 5'h07) ||
                    (opcode2 >= 5'h08 && opcode2 <= 5'h0e && opcode2 != 5'h0d) ||
                    (opcode2 == 5'h11) || (opcode2 == 5'h12);
    wire is_fpu2  = (opcode2 >= 5'h14 && opcode2 <= 5'h17);
    wire is_load2 = (opcode2 == 5'h10);
    wire is_store2= (opcode2 == 5'h13);
    wire is_halt2 = (opcode2 == 5'h0f);
    wire is_branch2 = (opcode2 >= 5'h08 && opcode2 <= 5'h0e) && (opcode2 != 5'h0d);
    wire is_call2 = (opcode2 == 5'h0c);
    wire is_return2 = (opcode2 == 5'h0d);

    // Store-only: stores don't write a register destination
    wire is_store1_only = is_store1 && !is_call1;
    wire is_store2_only = is_store2 && !is_call2;

    // Forward declarations needed before use
    wire decode_stall;
    wire alu_rr_after1;
    wire fpu_rr_after1;

    // Does instruction write to rd? (need to allocate phys reg)
    // Branches (including CALL and RETURN) do not write a destination register.
    wire is_branch_no_write1 = is_branch1;
    wire is_branch_no_write2 = is_branch2;
    wire alloc_preg1 = fu_out_valid1 && !is_halt1 && !is_store1_only && !is_branch_no_write1 && !is_return1;
    wire alloc_preg2 = fu_out_valid2 && !is_halt2 && !is_store2_only && !is_branch_no_write2 && !is_return2;

    // Determine which arch register to read for each source
    // src1 mapping for instruction 1
    wire [4:0] src1_areg1 = (opcode1 == 5'h0d) ? 5'd31 : // RETURN reads r31
                            (opcode1 == 5'h19 || opcode1 == 5'h1b ||
                             opcode1 == 5'h05 || opcode1 == 5'h07 ||
                             opcode1 == 5'h12) ? rd1 :   // ADDI,SUBI,SHFTRI,SHFTLI,MOVI read rd
                            (opcode1 == 5'h08 || opcode1 == 5'h09 ||
                             opcode1 == 5'h0b || opcode1 == 5'h0c) ? rd1 :   // BR,BRR,BRNZ,CALL read rd as target
                            rs1;                          // default: rs (also BRGT: src1=rs)
    // src2 mapping for instruction 1
    wire [4:0] src2_areg1 = (opcode1 == 5'h0b) ? rs1 :  // BRNZ: src2=rs (condition)
                            (opcode1 == 5'h0c) ? 5'd31 : // CALL: src2=r31
                            rt1;                          // default: rt (also BRGT: src2=rt)

    // src1 mapping for instruction 2
    wire [4:0] src1_areg2 = (opcode2 == 5'h0d) ? 5'd31 :
                            (opcode2 == 5'h19 || opcode2 == 5'h1b ||
                             opcode2 == 5'h05 || opcode2 == 5'h07 ||
                             opcode2 == 5'h12) ? rd2 :
                            (opcode2 == 5'h08 || opcode2 == 5'h09 ||
                             opcode2 == 5'h0b || opcode2 == 5'h0c) ? rd2 :
                            rs2;  // default: rs (also BRGT: src1=rs)
    wire [4:0] src2_areg2 = (opcode2 == 5'h0b) ? rs2 :
                            (opcode2 == 5'h0c) ? 5'd31 :
                            rt2;  // default: rt (also BRGT: src2=rt)

    // For stores: addr_base is rd, data is rs
    wire [4:0] store_addr_areg1 = rd1;
    wire [4:0] store_data_areg1 = rs1;
    wire [4:0] store_addr_areg2 = rd2;
    wire [4:0] store_data_areg2 = rs2;

    // For loads: base is rs
    wire [4:0] load_base_areg1 = rs1;
    wire [4:0] load_base_areg2 = rs2;

    // Destination arch register
    wire [4:0] dest_areg1 = (is_call1 || is_return1) ? 5'd31 : rd1;
    wire [4:0] dest_areg2 = (is_call2 || is_return2) ? 5'd31 : rd2;

    // RAT read: we use 4 read ports for both instructions
    // For instr1: read src1_areg1 and src2_areg1
    // For instr2: read src1_areg2 and src2_areg2
    // But we also need rd mappings for stores, loads, etc.
    // We'll use the 4 RAT read ports for the primary source lookups
    // and handle special cases with forwarding logic

    // RAT reads for instruction 1 sources
    wire [6:0] phys_src1_1, phys_src2_1;
    // RAT reads for instruction 2 sources
    wire [6:0] phys_src1_2, phys_src2_2;

    // For stores we need separate RAT lookups for addr_base and data
    // We'll multiplex the RAT read ports:
    // Port 1: instr1 src1 (or store1 addr_base or load1 base)
    // Port 2: instr1 src2 (or store1 data)
    // Port 3: instr2 src1 (or store2 addr_base or load2 base)
    // Port 4: instr2 src2 (or store2 data)

    wire [4:0] rat_rd_sel1 = is_store1_only ? store_addr_areg1 : is_load1 ? load_base_areg1 : src1_areg1;
    wire [4:0] rat_rd_sel2 = is_store1_only ? store_data_areg1 : src2_areg1;
    wire [4:0] rat_rd_sel3 = is_store2_only ? store_addr_areg2 : is_load2 ? load_base_areg2 : src1_areg2;
    wire [4:0] rat_rd_sel4 = is_store2_only ? store_data_areg2 : src2_areg2;

    assign phys_src1_1 = rat_read_preg1;
    assign phys_src2_1 = rat_read_preg2;
    assign phys_src1_2 = rat_read_preg3;
    assign phys_src2_2 = rat_read_preg4;

    // Intra-group dependency: if instr2 reads an areg that instr1 writes
    wire intra_dep_src1_2 = alloc_preg1 && (rat_rd_sel3 == dest_areg1);
    wire intra_dep_src2_2 = alloc_preg1 && (rat_rd_sel4 == dest_areg1);

    // After rename: physical registers for sources
    wire [6:0] ren_phys_src1_1 = phys_src1_1;
    wire [6:0] ren_phys_src2_1 = phys_src2_1;
    wire [6:0] ren_phys_src1_2 = intra_dep_src1_2 ? fl_deq_preg1 : phys_src1_2;
    wire [6:0] ren_phys_src2_2 = intra_dep_src2_2 ? fl_deq_preg1 : phys_src2_2;

    // New physical destination registers (from free list)
    wire [6:0] new_phys_rd1 = fl_deq_preg1;
    wire [6:0] new_phys_rd2 = fl_deq_preg2;

    // Forward declarations for old_phys lookups (from rat_extra)
    wire [6:0] old_phys1_raw, old_phys2_raw;

    // Extra RAT instance for old_phys and src2 lookups
    wire [6:0] rat_extra_preg1, rat_extra_preg2, rat_extra_preg3, rat_extra_preg4;

    // old_phys with intra-dep handling
    wire [6:0] old_phys1 = old_phys1_raw;
    wire [6:0] old_phys2 = (dest_areg2 == dest_areg1 && alloc_preg1) ? new_phys_rd1 : old_phys2_raw;

    // Determine src2 phys tag from rat_extra
    wire [6:0] ren_phys_src2_1_final;
    wire [6:0] ren_phys_src2_2_final;

    // Decode stall conditions
    wire target_full1 = (is_alu1 && ((!alu_rr && rs_alu0_full) || (alu_rr && rs_alu1_full))) ||
                        (is_fpu1 && ((!fpu_rr && rs_fpu0_full) || (fpu_rr && rs_fpu1_full))) ||
                        ((is_load1 || is_return1) && lq_full) ||
                        ((is_store1 || is_call1) && sq_full);
    wire target_full2 = (is_alu2 && ((!alu_rr_after1 && rs_alu0_full) || (alu_rr_after1 && rs_alu1_full))) ||
                        (is_fpu2 && ((!fpu_rr_after1 && rs_fpu0_full) || (fpu_rr_after1 && rs_fpu1_full))) ||
                        ((is_load2 || is_return2) && lq_full) ||
                        ((is_store2 || is_call2) && sq_full);

    // After instr1 dispatches to an ALU/FPU RS, toggle RR for instr2
    assign alu_rr_after1 = (is_alu1 || is_branch1 || opcode1 == 5'h11 || opcode1 == 5'h12) ? ~alu_rr : alu_rr;
    assign fpu_rr_after1 = is_fpu1 ? ~fpu_rr : fpu_rr;

    // Slot 1 must be able to make progress on its own. Slot 2 can be deferred and retried
    // next cycle when both fetched instructions target a single-dispatch structure.
    wire slot2_singleq_conflict =
        ((is_load1 || is_return1) && (is_load2 || is_return2)) ||
        ((is_store1_only || is_call1) && (is_store2_only || is_call2));
    wire slot2_branch_conflict = fu_out_valid1 && fu_out_valid2 && (is_branch1 || is_return1);
    wire slot2_blocked = target_full2 || slot2_singleq_conflict || slot2_branch_conflict;

    assign decode_stall = !rob_can_alloc2 || !fl_can_alloc2 || rob_has_unresolved_branch ||
                        hlt || rob_halt_committed ||
                        (fu_out_valid1 && target_full1);

    // Valid dispatch signals
    wire dispatch_valid1 = fu_out_valid1 && !decode_stall && !flush;
    wire dispatch_valid2 = fu_out_valid2 && !decode_stall && !flush && !slot2_blocked;

    // ================================================================
    // RS dispatch signals (directly wired based on opcode and RR)
    // ================================================================
    // Instruction 1 dispatch enables
    wire disp1_to_alu0 = dispatch_valid1 && (is_alu1) && !alu_rr;
    wire disp1_to_alu1 = dispatch_valid1 && (is_alu1) && alu_rr;
    wire disp1_to_fpu0 = dispatch_valid1 && is_fpu1 && !fpu_rr;
    wire disp1_to_fpu1 = dispatch_valid1 && is_fpu1 && fpu_rr;
    wire disp1_to_lq   = dispatch_valid1 && (is_load1 || is_return1);
    wire disp1_to_sq   = dispatch_valid1 && (is_store1_only || is_call1);

    // Instruction 2 dispatch enables
    wire disp2_to_alu0 = dispatch_valid2 && (is_alu2) && !alu_rr_after1;
    wire disp2_to_alu1 = dispatch_valid2 && (is_alu2) && alu_rr_after1;
    wire disp2_to_fpu0 = dispatch_valid2 && is_fpu2 && !fpu_rr_after1;
    wire disp2_to_fpu1 = dispatch_valid2 && is_fpu2 && fpu_rr_after1;
    wire disp2_to_lq   = dispatch_valid2 && (is_load2 || is_return2);
    wire disp2_to_sq   = dispatch_valid2 && (is_store2_only || is_call2);

    // Combine: each RS gets dispatch from either instr1 or instr2 (not both in same RS)
    wire rs_alu0_dispatch = disp1_to_alu0 || disp2_to_alu0;
    wire rs_alu1_dispatch = disp1_to_alu1 || disp2_to_alu1;
    wire rs_fpu0_dispatch = disp1_to_fpu0 || disp2_to_fpu0;
    wire rs_fpu1_dispatch = disp1_to_fpu1 || disp2_to_fpu1;
    wire lq_dispatch      = disp1_to_lq   || disp2_to_lq;
    wire sq_dispatch      = disp1_to_sq   || disp2_to_sq;

    // ================================================================
    // Source operand preparation (values and ready bits from PRF)
    // ================================================================
    // PRF read ports: 4 ports
    // Port 1: instr1 src1 phys
    // Port 2: instr1 src2 phys
    // Port 3: instr2 src1 phys
    // Port 4: instr2 src2 phys

    // Determine src1/src2 "don't care" (mark ready) for each instruction
    wire src1_dc1 = (opcode1 == 5'h0a); // BRR L: both don't care
    wire src2_dc1 = (opcode1 == 5'h03) || // NOT
                    (opcode1 == 5'h11) || // MOV rd,rs
                    (opcode1 == 5'h12) || // MOVI
                    (opcode1 == 5'h08) || // BR
                    (opcode1 == 5'h09) || // BRR
                    (opcode1 == 5'h0a) || // BRR L
                    (opcode1 == 5'h0c) || // CALL
                    (opcode1 == 5'h19) || // ADDI
                    (opcode1 == 5'h1b) || // SUBI
                    (opcode1 == 5'h05) || // SHFTRI
                    (opcode1 == 5'h07);   // SHFTLI

    wire src1_dc2 = (opcode2 == 5'h0a);
    wire src2_dc2 = (opcode2 == 5'h03) || (opcode2 == 5'h11) || (opcode2 == 5'h12) ||
                    (opcode2 == 5'h08) || (opcode2 == 5'h09) || (opcode2 == 5'h0a) ||
                    (opcode2 == 5'h0c) || // CALL
                    (opcode2 == 5'h19) || (opcode2 == 5'h1b) || (opcode2 == 5'h05) ||
                    (opcode2 == 5'h07);

    // PRF read port selectors (physical register IDs)
    wire [6:0] prf_rd1 = ren_phys_src1_1;
    wire [6:0] prf_rd2 = ren_phys_src2_1_final;
    wire [6:0] prf_rd3 = ren_phys_src1_2;
    wire [6:0] prf_rd4 = ren_phys_src2_2_final;

    // Source ready and value for RS dispatch (combining PRF read + CDB bypass)
    // CDB bypass: if the tag matches a current CDB broadcast, use CDB value
    wire src1_rdy1 = src1_dc1 || prf_read_ready1 ||
                     (cdb0_valid && cdb0_tag == prf_rd1) ||
                     (cdb1_valid && cdb1_tag == prf_rd1);
    wire [63:0] src1_val1 = (cdb0_valid && cdb0_tag == prf_rd1 && !prf_read_ready1) ? cdb0_value :
                            (cdb1_valid && cdb1_tag == prf_rd1 && !prf_read_ready1) ? cdb1_value :
                            prf_read_data1;

    wire src2_rdy1 = src2_dc1 || prf_read_ready2 ||
                     (cdb0_valid && cdb0_tag == prf_rd2) ||
                     (cdb1_valid && cdb1_tag == prf_rd2);
    wire [63:0] src2_val1 = (cdb0_valid && cdb0_tag == prf_rd2 && !prf_read_ready2) ? cdb0_value :
                            (cdb1_valid && cdb1_tag == prf_rd2 && !prf_read_ready2) ? cdb1_value :
                            prf_read_data2;

    // A same-cycle dependency on slot 1's freshly allocated destination must wait for the
    // later CDB broadcast. The recycled physreg may still hold stale data/ready state in the PRF.
    wire src1_rdy2 = src1_dc2 || (!intra_dep_src1_2 && prf_read_ready3) ||
                     (cdb0_valid && cdb0_tag == prf_rd3) ||
                     (cdb1_valid && cdb1_tag == prf_rd3);
    wire [63:0] src1_val2 = (cdb0_valid && cdb0_tag == prf_rd3 && (!prf_read_ready3 || intra_dep_src1_2)) ? cdb0_value :
                            (cdb1_valid && cdb1_tag == prf_rd3 && (!prf_read_ready3 || intra_dep_src1_2)) ? cdb1_value :
                            prf_read_data3;

    wire src2_rdy2 = src2_dc2 || (!intra_dep_src2_2 && prf_read_ready4) ||
                     (cdb0_valid && cdb0_tag == prf_rd4) ||
                     (cdb1_valid && cdb1_tag == prf_rd4);
    wire [63:0] src2_val2 = (cdb0_valid && cdb0_tag == prf_rd4 && (!prf_read_ready4 || intra_dep_src2_2)) ? cdb0_value :
                            (cdb1_valid && cdb1_tag == prf_rd4 && (!prf_read_ready4 || intra_dep_src2_2)) ? cdb1_value :
                            prf_read_data4;

    // IMM field for dispatch
    // BRGT uses rd as the branch target register in the ISA tests.
    // We overload the RS imm field with that already-committed architectural value.
    wire [63:0] dispatch_imm1 = (opcode1 == 5'h0e) ? reg_file.registers[rd1] : imm1;
    wire [63:0] dispatch_imm2 = (opcode2 == 5'h0e) ? reg_file.registers[rd2] : imm2;


    // ================================================================
    // RS dispatch data muxes
    // ================================================================
    // For ALU RS: select between instr1 and instr2 data
    wire [4:0]  alu0_disp_opcode = disp1_to_alu0 ? opcode1 : opcode2;
    wire [63:0] alu0_disp_src1_val = disp1_to_alu0 ? src1_val1 : src1_val2;
    wire [6:0]  alu0_disp_src1_tag = disp1_to_alu0 ? prf_rd1 : prf_rd3;
    wire        alu0_disp_src1_rdy = disp1_to_alu0 ? src1_rdy1 : src1_rdy2;
    wire [63:0] alu0_disp_src2_val = disp1_to_alu0 ? src2_val1 : src2_val2;
    wire [6:0]  alu0_disp_src2_tag = disp1_to_alu0 ? prf_rd2 : prf_rd4;
    wire        alu0_disp_src2_rdy = disp1_to_alu0 ? src2_rdy1 : src2_rdy2;
    wire [6:0]  alu0_disp_dest     = disp1_to_alu0 ? new_phys_rd1 : new_phys_rd2;
    wire [4:0]  alu0_disp_rob_idx  = disp1_to_alu0 ? rob_alloc_idx1 : rob_alloc_idx2;
    wire [63:0] alu0_disp_imm      = disp1_to_alu0 ? dispatch_imm1 : dispatch_imm2;
    wire [63:0] alu0_disp_pc       = disp1_to_alu0 ? fu_out_pc1 : fu_out_pc2;

    wire [4:0]  alu1_disp_opcode = disp1_to_alu1 ? opcode1 : opcode2;
    wire [63:0] alu1_disp_src1_val = disp1_to_alu1 ? src1_val1 : src1_val2;
    wire [6:0]  alu1_disp_src1_tag = disp1_to_alu1 ? prf_rd1 : prf_rd3;
    wire        alu1_disp_src1_rdy = disp1_to_alu1 ? src1_rdy1 : src1_rdy2;
    wire [63:0] alu1_disp_src2_val = disp1_to_alu1 ? src2_val1 : src2_val2;
    wire [6:0]  alu1_disp_src2_tag = disp1_to_alu1 ? prf_rd2 : prf_rd4;
    wire        alu1_disp_src2_rdy = disp1_to_alu1 ? src2_rdy1 : src2_rdy2;
    wire [6:0]  alu1_disp_dest     = disp1_to_alu1 ? new_phys_rd1 : new_phys_rd2;
    wire [4:0]  alu1_disp_rob_idx  = disp1_to_alu1 ? rob_alloc_idx1 : rob_alloc_idx2;
    wire [63:0] alu1_disp_imm      = disp1_to_alu1 ? dispatch_imm1 : dispatch_imm2;
    wire [63:0] alu1_disp_pc       = disp1_to_alu1 ? fu_out_pc1 : fu_out_pc2;

    wire [4:0]  fpu0_disp_opcode = disp1_to_fpu0 ? opcode1 : opcode2;
    wire [63:0] fpu0_disp_src1_val = disp1_to_fpu0 ? src1_val1 : src1_val2;
    wire [6:0]  fpu0_disp_src1_tag = disp1_to_fpu0 ? prf_rd1 : prf_rd3;
    wire        fpu0_disp_src1_rdy = disp1_to_fpu0 ? src1_rdy1 : src1_rdy2;
    wire [63:0] fpu0_disp_src2_val = disp1_to_fpu0 ? src2_val1 : src2_val2;
    wire [6:0]  fpu0_disp_src2_tag = disp1_to_fpu0 ? prf_rd2 : prf_rd4;
    wire        fpu0_disp_src2_rdy = disp1_to_fpu0 ? src2_rdy1 : src2_rdy2;
    wire [6:0]  fpu0_disp_dest     = disp1_to_fpu0 ? new_phys_rd1 : new_phys_rd2;
    wire [4:0]  fpu0_disp_rob_idx  = disp1_to_fpu0 ? rob_alloc_idx1 : rob_alloc_idx2;
    wire [63:0] fpu0_disp_imm      = disp1_to_fpu0 ? dispatch_imm1 : dispatch_imm2;
    wire [63:0] fpu0_disp_pc       = disp1_to_fpu0 ? fu_out_pc1 : fu_out_pc2;

    wire [4:0]  fpu1_disp_opcode = disp1_to_fpu1 ? opcode1 : opcode2;
    wire [63:0] fpu1_disp_src1_val = disp1_to_fpu1 ? src1_val1 : src1_val2;
    wire [6:0]  fpu1_disp_src1_tag = disp1_to_fpu1 ? prf_rd1 : prf_rd3;
    wire        fpu1_disp_src1_rdy = disp1_to_fpu1 ? src1_rdy1 : src1_rdy2;
    wire [63:0] fpu1_disp_src2_val = disp1_to_fpu1 ? src2_val1 : src2_val2;
    wire [6:0]  fpu1_disp_src2_tag = disp1_to_fpu1 ? prf_rd2 : prf_rd4;
    wire        fpu1_disp_src2_rdy = disp1_to_fpu1 ? src2_rdy1 : src2_rdy2;
    wire [6:0]  fpu1_disp_dest     = disp1_to_fpu1 ? new_phys_rd1 : new_phys_rd2;
    wire [4:0]  fpu1_disp_rob_idx  = disp1_to_fpu1 ? rob_alloc_idx1 : rob_alloc_idx2;
    wire [63:0] fpu1_disp_imm      = disp1_to_fpu1 ? dispatch_imm1 : dispatch_imm2;
    wire [63:0] fpu1_disp_pc       = disp1_to_fpu1 ? fu_out_pc1 : fu_out_pc2;

    // Load queue dispatch data
    wire        lq_disp_from1 = disp1_to_lq;
    wire [63:0] lq_disp_base_val = lq_disp_from1 ? src1_val1 : src1_val2;
    wire [6:0]  lq_disp_base_tag = lq_disp_from1 ? prf_rd1 : prf_rd3;
    wire        lq_disp_base_rdy = lq_disp_from1 ? src1_rdy1 : src1_rdy2;
    wire [63:0] lq_disp_imm      = lq_disp_from1 ?
                                    (is_return1 ? -64'sd8 : dispatch_imm1) :
                                    (is_return2 ? -64'sd8 : dispatch_imm2);
    wire [6:0]  lq_disp_dest_tag = lq_disp_from1 ? new_phys_rd1 : new_phys_rd2;
    wire [4:0]  lq_disp_rob_idx  = lq_disp_from1 ? rob_alloc_idx1 : rob_alloc_idx2;
    wire [4:0]  lq_disp_opcode   = lq_disp_from1 ? opcode1 : opcode2;
    // For RETURN: base = r31's phys mapping
    // We handle this by having src1_areg for RETURN be r31 in the earlier mux

    // Store queue dispatch data
    wire        sq_disp_from1 = disp1_to_sq;
    // For normal STORE: addr_base = rd's phys, data = rs's phys
    // For CALL: addr_base = r31's phys, data = PC+4 (immediate, mark ready)
    // For CALL: addr_base = r31 (src2), not rd (src1)
    wire [63:0] sq_disp_addr_base_val = sq_disp_from1 ?
                                        (is_call1 ? src2_val1 : src1_val1) :
                                        (is_call2 ? src2_val2 : src1_val2);
    wire [6:0]  sq_disp_addr_base_tag = sq_disp_from1 ?
                                        (is_call1 ? prf_rd2 : prf_rd1) :
                                        (is_call2 ? prf_rd4 : prf_rd3);
    wire        sq_disp_addr_base_rdy = sq_disp_from1 ?
                                        (is_call1 ? src2_rdy1 : src1_rdy1) :
                                        (is_call2 ? src2_rdy2 : src1_rdy2);
    wire [63:0] sq_disp_data_val = sq_disp_from1 ?
                                   (is_call1 ? (fu_out_pc1 + 64'd4) : src2_val1) :
                                   (is_call2 ? (fu_out_pc2 + 64'd4) : src2_val2);
    wire [6:0]  sq_disp_data_tag = sq_disp_from1 ?
                                   (is_call1 ? 7'd0 : prf_rd2) :
                                   (is_call2 ? 7'd0 : prf_rd4);
    wire        sq_disp_data_rdy = sq_disp_from1 ?
                                   (is_call1 ? 1'b1 : src2_rdy1) :
                                   (is_call2 ? 1'b1 : src2_rdy2);
    wire [63:0] sq_disp_imm = sq_disp_from1 ?
                               (is_call1 ? -64'sd8 : dispatch_imm1) :
                               (is_call2 ? -64'sd8 : dispatch_imm2);
    wire [4:0]  sq_disp_rob_idx = sq_disp_from1 ? rob_alloc_idx1 : rob_alloc_idx2;
    wire [4:0]  sq_disp_opcode  = sq_disp_from1 ? opcode1 : opcode2;

    // ================================================================
    // ROB allocation data
    // ================================================================
    wire [2:0] rob_type1 = (is_branch1 || is_return1) ? ITYPE_BRANCH :
                           is_fpu1    ? ITYPE_FPU :
                           is_load1   ? ITYPE_LOAD :
                           (is_store1_only || is_call1) ? (is_call1 ? ITYPE_BRANCH : ITYPE_STORE) :
                           is_halt1   ? ITYPE_HALT :
                           ITYPE_ALU;
    wire [2:0] rob_type2 = (is_branch2 || is_return2) ? ITYPE_BRANCH :
                           is_fpu2    ? ITYPE_FPU :
                           is_load2   ? ITYPE_LOAD :
                           (is_store2_only || is_call2) ? (is_call2 ? ITYPE_BRANCH : ITYPE_STORE) :
                           is_halt2   ? ITYPE_HALT :
                           ITYPE_ALU;

    // The current fetch unit always fetches sequentially and only redirects after resolution.
    // Until the frontend actually speculates, the ROB's recorded prediction must remain
    // "not taken" so recovery matches what fetch really did.
    wire branch_pred1 = 1'b0;
    wire branch_pred2 = 1'b0;

    // ================================================================
    // Snapshot ID management for branch RAT checkpoints
    // ================================================================
    reg [1:0] snap_id_counter;
    wire [1:0] snap_id1 = snap_id_counter;
    wire [1:0] snap_id2 = snap_id_counter + 2'd1;
    wire take_snap1 = dispatch_valid1 && (is_branch1 || is_return1);
    wire take_snap2 = dispatch_valid2 && (is_branch2 || is_return2);

    // ================================================================
    // Sequential logic: RR counters, snapshot ID, halt
    // ================================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            alu_rr <= 1'b0;
            fpu_rr <= 1'b0;
            snap_id_counter <= 2'd0;
            hlt <= 1'b0;
        end else if (flush) begin
            // On flush, keep RR state (or reset - doesn't matter much)
            alu_rr <= 1'b0;
            fpu_rr <= 1'b0;
        end else begin
            if (rob_halt_committed)
                hlt <= 1'b1;

            // Update RR counters
            if (dispatch_valid1 || dispatch_valid2) begin
                if (dispatch_valid1 && (is_alu1))
                    alu_rr <= ~alu_rr;
                if (dispatch_valid2 && (is_alu2))
                    alu_rr <= dispatch_valid1 && (is_alu1) ? alu_rr : ~alu_rr;
                if (dispatch_valid1 && is_fpu1)
                    fpu_rr <= ~fpu_rr;
                if (dispatch_valid2 && is_fpu2)
                    fpu_rr <= dispatch_valid1 && is_fpu1 ? fpu_rr : ~fpu_rr;
            end

            // Update snapshot counter
            if (take_snap1 && take_snap2)
                snap_id_counter <= snap_id_counter + 2'd2;
            else if (take_snap1 || take_snap2)
                snap_id_counter <= snap_id_counter + 2'd1;
        end
    end

    // ================================================================
    // MODULE INSTANTIATIONS
    // ================================================================

    // Forward declaration for memory data output
    wire [63:0] lq_mem_read_data_wire;

    // --- Memory ---
    memory memory(
        .clk(clk),
        .reset(reset),
        .PC(64'd0),                          // legacy port, tied off
        .instruction(),                       // legacy port, unused
        .data_address(lq_mem_read_addr),      // load read port
        .data_out(lq_mem_read_data_wire),
        .data_ready(),
        .write_enable(sq_mem_write_en),       // store write port
        .write_address(sq_mem_write_addr),
        .write_data(sq_mem_write_data),
        .fetch_addr(fu_fetch_addr),           // fetch port
        .fetch_data(fu_fetch_data)
    );

    // --- Fetch Unit ---
    fetch_unit fu_inst(
        .clk(clk),
        .rst(reset),
        .fetch_addr(fu_fetch_addr),
        .fetch_data(fu_fetch_data),
        .out_valid1(fu_out_valid1),
        .out_instr1(fu_out_instr1),
        .out_pc1(fu_out_pc1),
        .out_valid2(fu_out_valid2),
        .out_instr2(fu_out_instr2),
        .out_pc2(fu_out_pc2),
        .decode_stall(decode_stall),
        .consume_two(dispatch_valid2),
        .flush(pipe_kill),
        .redirect_pc(rob_mispredict_target)
    );

    // --- Instruction Decoders ---
    instruction_decoder dec1(
        .instruction(fu_out_instr1),
        .opcode(opcode1),
        .rd(rd1), .rs(rs1), .rt(rt1), .L(L1)
    );
    instruction_decoder dec2(
        .instruction(fu_out_instr2),
        .opcode(opcode2),
        .rd(rd2), .rs(rs2), .rt(rt2), .L(L2)
    );

    // --- RAT (primary - 4 read ports for src1/src2 of both instructions) ---
    // When both instructions write the same arch reg, suppress the older (port 1)
    // because the RAT module gives port 1 higher priority, but instr2 is newer.
    wire rat_same_dest = alloc_preg1 && alloc_preg2 && dispatch_valid1 && dispatch_valid2
                         && (dest_areg1 == dest_areg2);
    rat rat_inst(
        .clk(clk),
        .reset(reset),
        .read_sel1(rat_rd_sel1),
        .read_sel2(rat_rd_sel2),
        .read_sel3(rat_rd_sel3),
        .read_sel4(rat_rd_sel4),
        .read_preg1(rat_read_preg1),
        .read_preg2(rat_read_preg2),
        .read_preg3(rat_read_preg3),
        .read_preg4(rat_read_preg4),
        .write_en1(alloc_preg1 && dispatch_valid1 && !rat_same_dest),
        .write_areg1(dest_areg1),
        .write_preg1(new_phys_rd1),
        .write_en2(alloc_preg2 && dispatch_valid2),
        .write_areg2(dest_areg2),
        .write_preg2(new_phys_rd2),
        .snap_en1(take_snap1),
        .snap_id1(snap_id1),
        .snap_en2(take_snap2),
        .snap_id2(snap_id2),
        .snap1_wr_override(alloc_preg1 && dispatch_valid1 && rat_same_dest),
        .snap1_wr_areg(dest_areg1),
        .snap1_wr_preg(new_phys_rd1),
        .restore_en(1'b0),
        .restore_id(rob_mispredict_snap_id)
    );

    // --- RAT extra (for old_phys lookups and any additional src2 reads) ---
    rat rat_extra(
        .clk(clk),
        .reset(reset),
        .read_sel1(dest_areg1),    // old_phys for instr1
        .read_sel2(dest_areg2),    // old_phys for instr2
        .read_sel3(src2_areg1),    // src2 tag for instr1 (when RAT primary used for src1)
        .read_sel4(src2_areg2),    // src2 tag for instr2
        .read_preg1(rat_extra_preg1),
        .read_preg2(rat_extra_preg2),
        .read_preg3(rat_extra_preg3),
        .read_preg4(rat_extra_preg4),
        // Same writes as primary RAT to keep in sync
        .write_en1(alloc_preg1 && dispatch_valid1 && !rat_same_dest),
        .write_areg1(dest_areg1),
        .write_preg1(new_phys_rd1),
        .write_en2(alloc_preg2 && dispatch_valid2),
        .write_areg2(dest_areg2),
        .write_preg2(new_phys_rd2),
        .snap_en1(take_snap1),
        .snap_id1(snap_id1),
        .snap_en2(take_snap2),
        .snap_id2(snap_id2),
        .snap1_wr_override(alloc_preg1 && dispatch_valid1 && rat_same_dest),
        .snap1_wr_areg(dest_areg1),
        .snap1_wr_preg(new_phys_rd1),
        .restore_en(1'b0),
        .restore_id(rob_mispredict_snap_id)
    );

    assign old_phys1_raw = rat_extra_preg1;
    assign old_phys2_raw = rat_extra_preg2;

    // src2 phys tags from rat_extra port3/4, with intra-dep override
    assign ren_phys_src2_1_final = is_store1_only ? rat_read_preg2 :  // store data from primary port2
                                   rat_extra_preg3;                    // src2 from extra port3
    assign ren_phys_src2_2_final = is_store2_only ? rat_read_preg4 :
                                   (alloc_preg1 && src2_areg2 == dest_areg1) ? new_phys_rd1 :
                                   rat_extra_preg4;

    // Also handle intra-dep for src1 of instr2 - override with new_phys_rd1
    // ren_phys_src1_2 already handles this above via intra_dep_src1_2

    // --- Free List ---
    free_list fl_inst(
        .clk(clk),
        .reset(reset),
        .deq_en1(alloc_preg1 && dispatch_valid1),
        .deq_en2(alloc_preg2 && dispatch_valid2),
        .deq_preg1(fl_deq_preg1),
        .deq_preg2(fl_deq_preg2),
        // Only enqueue old_phys back to free list when instruction actually wrote a register
        // (new_phys != 0 means a physical register was allocated at rename)
        .enq_en1(rob_commit_en1 && rob_commit_new_phys1 != 7'd0),
        .enq_preg1(rob_commit_old_phys1),
        .enq_en2(rob_commit_en2 && rob_commit_new_phys2 != 7'd0),
        .enq_preg2(rob_commit_old_phys2),
        .can_alloc2(fl_can_alloc2),
        .snap_en1(take_snap1),
        .snap_id1(snap_id1),
        .snap_en2(take_snap2),
        .snap_id2(snap_id2),
        .restore_en(1'b0),
        .restore_id(rob_mispredict_snap_id)
    );

    // --- Physical Register File ---
    phys_reg_file prf_inst(
        .clk(clk),
        .reset(reset),
        .read_sel1(prf_rd1),
        .read_sel2(prf_rd2),
        .read_sel3(prf_rd3),
        .read_sel4(prf_rd4),
        .read_data1(prf_read_data1),
        .read_data2(prf_read_data2),
        .read_data3(prf_read_data3),
        .read_data4(prf_read_data4),
        .read_ready1(prf_read_ready1),
        .read_ready2(prf_read_ready2),
        .read_ready3(prf_read_ready3),
        .read_ready4(prf_read_ready4),
        .write_en1(cdb0_valid),
        .write_sel1(cdb0_tag),
        .write_data1(cdb0_value),
        .write_en2(cdb1_valid),
        .write_sel2(cdb1_tag),
        .write_data2(cdb1_value),
        .clear_ready_en1(alloc_preg1 && dispatch_valid1),
        .clear_ready_sel1(new_phys_rd1),
        .clear_ready_en2(alloc_preg2 && dispatch_valid2),
        .clear_ready_sel2(new_phys_rd2)
    );

    // --- Architectural Register File (for commit) ---
    // Port 1 has higher priority in reg_file (written last in always block).
    // For dual-commit, commit1=older(head), commit2=newer(head+1).
    // When both write the same arch reg, the NEWER value must win.
    // So we put the newer commit on port 1 (high prio) and older on port 2,
    // OR suppress the older write when both target the same register.
    // Only write ARF when instruction actually wrote a register (new_phys != 0)
    wire arf_wen1_raw = rob_commit_en1 && rob_commit_new_phys1 != 7'd0;
    wire arf_wen2_raw = rob_commit_en2 && rob_commit_new_phys2 != 7'd0;
    wire arf_same_dest = arf_wen1_raw && arf_wen2_raw &&
                         (rob_commit_arch_rd1 == rob_commit_arch_rd2);
    // Suppress older write (port 1) when both write same register
    reg_file reg_file(
        .clk(clk),
        .reset(reset),
        .write_en1(arf_wen1_raw && !arf_same_dest),
        .write_data1(rob_commit_value1),
        .write_sel1(rob_commit_arch_rd1),
        .write_en2(arf_wen2_raw),
        .write_data2(rob_commit_value2),
        .write_sel2(rob_commit_arch_rd2),
        .read_sel1(5'd0),
        .read_sel2(5'd0),
        .read_sel3(5'd0),
        .read_sel4(5'd0),
        .read_data1(),
        .read_data2(),
        .read_data3(),
        .read_data4()
    );

    // --- Reservation Stations ---
    reservation_station #(.NUM_ENTRIES(8)) rs_alu0(
        .clk(clk), .rst(reset),
        .dispatch_en(rs_alu0_dispatch),
        .dispatch_opcode(alu0_disp_opcode),
        .dispatch_src1_val(alu0_disp_src1_val),
        .dispatch_src1_tag(alu0_disp_src1_tag),
        .dispatch_src1_rdy(alu0_disp_src1_rdy),
        .dispatch_src2_val(alu0_disp_src2_val),
        .dispatch_src2_tag(alu0_disp_src2_tag),
        .dispatch_src2_rdy(alu0_disp_src2_rdy),
        .dispatch_dest_tag(alu0_disp_dest),
        .dispatch_rob_idx(alu0_disp_rob_idx),
        .dispatch_imm(alu0_disp_imm),
        .dispatch_pc(alu0_disp_pc),
        .cdb0_valid(cdb0_valid), .cdb0_tag(cdb0_tag), .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid), .cdb1_tag(cdb1_tag), .cdb1_value(cdb1_value),
        .issue_valid(rs_alu0_issue_valid),
        .issue_opcode(rs_alu0_issue_opcode),
        .issue_src1_val(rs_alu0_issue_src1),
        .issue_src2_val(rs_alu0_issue_src2),
        .issue_dest_tag(rs_alu0_issue_dest),
        .issue_rob_idx(rs_alu0_issue_rob),
        .issue_imm(rs_alu0_issue_imm),
        .issue_pc(rs_alu0_issue_pc),
        .issue_ack(rs_alu0_issue_valid && alu0_issue_ready),
        .full(rs_alu0_full),
        .flush(pipe_kill)
    );

    reservation_station #(.NUM_ENTRIES(8)) rs_alu1(
        .clk(clk), .rst(reset),
        .dispatch_en(rs_alu1_dispatch),
        .dispatch_opcode(alu1_disp_opcode),
        .dispatch_src1_val(alu1_disp_src1_val),
        .dispatch_src1_tag(alu1_disp_src1_tag),
        .dispatch_src1_rdy(alu1_disp_src1_rdy),
        .dispatch_src2_val(alu1_disp_src2_val),
        .dispatch_src2_tag(alu1_disp_src2_tag),
        .dispatch_src2_rdy(alu1_disp_src2_rdy),
        .dispatch_dest_tag(alu1_disp_dest),
        .dispatch_rob_idx(alu1_disp_rob_idx),
        .dispatch_imm(alu1_disp_imm),
        .dispatch_pc(alu1_disp_pc),
        .cdb0_valid(cdb0_valid), .cdb0_tag(cdb0_tag), .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid), .cdb1_tag(cdb1_tag), .cdb1_value(cdb1_value),
        .issue_valid(rs_alu1_issue_valid),
        .issue_opcode(rs_alu1_issue_opcode),
        .issue_src1_val(rs_alu1_issue_src1),
        .issue_src2_val(rs_alu1_issue_src2),
        .issue_dest_tag(rs_alu1_issue_dest),
        .issue_rob_idx(rs_alu1_issue_rob),
        .issue_imm(rs_alu1_issue_imm),
        .issue_pc(rs_alu1_issue_pc),
        .issue_ack(rs_alu1_issue_valid && alu1_issue_ready),
        .full(rs_alu1_full),
        .flush(pipe_kill)
    );

    reservation_station #(.NUM_ENTRIES(8)) rs_fpu0(
        .clk(clk), .rst(reset),
        .dispatch_en(rs_fpu0_dispatch),
        .dispatch_opcode(fpu0_disp_opcode),
        .dispatch_src1_val(fpu0_disp_src1_val),
        .dispatch_src1_tag(fpu0_disp_src1_tag),
        .dispatch_src1_rdy(fpu0_disp_src1_rdy),
        .dispatch_src2_val(fpu0_disp_src2_val),
        .dispatch_src2_tag(fpu0_disp_src2_tag),
        .dispatch_src2_rdy(fpu0_disp_src2_rdy),
        .dispatch_dest_tag(fpu0_disp_dest),
        .dispatch_rob_idx(fpu0_disp_rob_idx),
        .dispatch_imm(fpu0_disp_imm),
        .dispatch_pc(fpu0_disp_pc),
        .cdb0_valid(cdb0_valid), .cdb0_tag(cdb0_tag), .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid), .cdb1_tag(cdb1_tag), .cdb1_value(cdb1_value),
        .issue_valid(rs_fpu0_issue_valid),
        .issue_opcode(rs_fpu0_issue_opcode),
        .issue_src1_val(rs_fpu0_issue_src1),
        .issue_src2_val(rs_fpu0_issue_src2),
        .issue_dest_tag(rs_fpu0_issue_dest),
        .issue_rob_idx(rs_fpu0_issue_rob),
        .issue_imm(rs_fpu0_issue_imm),
        .issue_pc(rs_fpu0_issue_pc),
        .issue_ack(rs_fpu0_issue_valid && fpu0_issue_ready),
        .full(rs_fpu0_full),
        .flush(pipe_kill)
    );

    reservation_station #(.NUM_ENTRIES(8)) rs_fpu1(
        .clk(clk), .rst(reset),
        .dispatch_en(rs_fpu1_dispatch),
        .dispatch_opcode(fpu1_disp_opcode),
        .dispatch_src1_val(fpu1_disp_src1_val),
        .dispatch_src1_tag(fpu1_disp_src1_tag),
        .dispatch_src1_rdy(fpu1_disp_src1_rdy),
        .dispatch_src2_val(fpu1_disp_src2_val),
        .dispatch_src2_tag(fpu1_disp_src2_tag),
        .dispatch_src2_rdy(fpu1_disp_src2_rdy),
        .dispatch_dest_tag(fpu1_disp_dest),
        .dispatch_rob_idx(fpu1_disp_rob_idx),
        .dispatch_imm(fpu1_disp_imm),
        .dispatch_pc(fpu1_disp_pc),
        .cdb0_valid(cdb0_valid), .cdb0_tag(cdb0_tag), .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid), .cdb1_tag(cdb1_tag), .cdb1_value(cdb1_value),
        .issue_valid(rs_fpu1_issue_valid),
        .issue_opcode(rs_fpu1_issue_opcode),
        .issue_src1_val(rs_fpu1_issue_src1),
        .issue_src2_val(rs_fpu1_issue_src2),
        .issue_dest_tag(rs_fpu1_issue_dest),
        .issue_rob_idx(rs_fpu1_issue_rob),
        .issue_imm(rs_fpu1_issue_imm),
        .issue_pc(rs_fpu1_issue_pc),
        .issue_ack(rs_fpu1_issue_valid && fpu1_issue_ready),
        .full(rs_fpu1_full),
        .flush(pipe_kill)
    );

    // --- ALU Pipes ---
    alu_pipe alu_pipe0(
        .clk(clk), .rst(reset),
        .issue_valid(rs_alu0_issue_valid),
        .issue_opcode(rs_alu0_issue_opcode),
        .issue_src1(rs_alu0_issue_src1),
        .issue_src2(rs_alu0_issue_src2),
        .issue_dest_tag(rs_alu0_issue_dest),
        .issue_rob_idx(rs_alu0_issue_rob),
        .issue_imm(rs_alu0_issue_imm),
        .issue_pc(rs_alu0_issue_pc),
        .issue_ready(alu0_issue_ready),
        .cdb_valid(alu0_cdb_valid),
        .cdb_tag(alu0_cdb_tag),
        .cdb_value(alu0_cdb_value),
        .cdb_rob_idx(alu0_cdb_rob),
        .br_resolved(alu0_br_resolved),
        .br_taken(alu0_br_taken),
        .br_target(alu0_br_target),
        .br_rob_idx_out(alu0_br_rob_idx),
        .cdb_stall(cdb_alu0_stall),
        .flush(pipe_kill)
    );

    alu_pipe alu_pipe1(
        .clk(clk), .rst(reset),
        .issue_valid(rs_alu1_issue_valid),
        .issue_opcode(rs_alu1_issue_opcode),
        .issue_src1(rs_alu1_issue_src1),
        .issue_src2(rs_alu1_issue_src2),
        .issue_dest_tag(rs_alu1_issue_dest),
        .issue_rob_idx(rs_alu1_issue_rob),
        .issue_imm(rs_alu1_issue_imm),
        .issue_pc(rs_alu1_issue_pc),
        .issue_ready(alu1_issue_ready),
        .cdb_valid(alu1_cdb_valid),
        .cdb_tag(alu1_cdb_tag),
        .cdb_value(alu1_cdb_value),
        .cdb_rob_idx(alu1_cdb_rob),
        .br_resolved(alu1_br_resolved),
        .br_taken(alu1_br_taken),
        .br_target(alu1_br_target),
        .br_rob_idx_out(alu1_br_rob_idx),
        .cdb_stall(cdb_alu1_stall),
        .flush(pipe_kill)
    );

    // --- FPU (wrapper containing both FPU pipes) ---
    fpu fpu(
        .clk(clk), .rst(reset),
        .pipe0_issue_valid(rs_fpu0_issue_valid),
        .pipe0_issue_opcode(rs_fpu0_issue_opcode),
        .pipe0_issue_src1(rs_fpu0_issue_src1),
        .pipe0_issue_src2(rs_fpu0_issue_src2),
        .pipe0_issue_dest_tag(rs_fpu0_issue_dest),
        .pipe0_issue_rob_idx(rs_fpu0_issue_rob),
        .pipe0_issue_ready(fpu0_issue_ready),
        .pipe0_cdb_valid(fpu0_cdb_valid),
        .pipe0_cdb_tag(fpu0_cdb_tag),
        .pipe0_cdb_value(fpu0_cdb_value),
        .pipe0_cdb_rob_idx(fpu0_cdb_rob),
        .pipe1_issue_valid(rs_fpu1_issue_valid),
        .pipe1_issue_opcode(rs_fpu1_issue_opcode),
        .pipe1_issue_src1(rs_fpu1_issue_src1),
        .pipe1_issue_src2(rs_fpu1_issue_src2),
        .pipe1_issue_dest_tag(rs_fpu1_issue_dest),
        .pipe1_issue_rob_idx(rs_fpu1_issue_rob),
        .pipe1_issue_ready(fpu1_issue_ready),
        .pipe1_cdb_valid(fpu1_cdb_valid),
        .pipe1_cdb_tag(fpu1_cdb_tag),
        .pipe1_cdb_value(fpu1_cdb_value),
        .pipe1_cdb_rob_idx(fpu1_cdb_rob),
        .pipe0_cdb_stall(cdb_fpu0_stall),
        .pipe1_cdb_stall(cdb_fpu1_stall),
        .flush(pipe_kill)
    );

    // --- Load Queue ---
    load_queue lq_inst(
        .clk(clk), .rst(reset),
        .dispatch_en(lq_dispatch),
        .dispatch_base_val(lq_disp_base_val),
        .dispatch_base_tag(lq_disp_base_tag),
        .dispatch_base_ready(lq_disp_base_rdy),
        .dispatch_imm(lq_disp_imm),
        .dispatch_dest_tag(lq_disp_dest_tag),
        .dispatch_rob_idx(lq_disp_rob_idx),
        .dispatch_opcode(lq_disp_opcode),
        .cdb0_valid(cdb0_valid), .cdb0_tag(cdb0_tag), .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid), .cdb1_tag(cdb1_tag), .cdb1_value(cdb1_value),
        .mem_read_en(lq_mem_read_en),
        .mem_read_addr(lq_mem_read_addr),
        .mem_read_data(lq_mem_read_data_wire),
        .sq_fwd_valid(sq_fwd_hit),
        .sq_fwd_data(sq_fwd_data),
        .cdb_valid(lq_cdb_valid),
        .cdb_tag(lq_cdb_tag),
        .cdb_value(lq_cdb_value),
        .cdb_rob_idx(lq_cdb_rob),
        .br_resolved(lq_br_resolved),
        .br_taken(lq_br_taken),
        .br_target(lq_br_target),
        .br_rob_idx_out(lq_br_rob_idx),
        .cdb_stall(cdb_lsu0_stall),
        .full(lq_full),
        .flush(flush)
    );

    // --- Store Queue ---
    store_queue sq_inst(
        .clk(clk), .rst(reset),
        .dispatch_en(sq_dispatch),
        .dispatch_addr_base_val(sq_disp_addr_base_val),
        .dispatch_addr_base_tag(sq_disp_addr_base_tag),
        .dispatch_addr_base_ready(sq_disp_addr_base_rdy),
        .dispatch_data_val(sq_disp_data_val),
        .dispatch_data_tag(sq_disp_data_tag),
        .dispatch_data_ready(sq_disp_data_rdy),
        .dispatch_imm(sq_disp_imm),
        .dispatch_rob_idx(sq_disp_rob_idx),
        .dispatch_opcode(sq_disp_opcode),
        .cdb0_valid(cdb0_valid), .cdb0_tag(cdb0_tag), .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid), .cdb1_tag(cdb1_tag), .cdb1_value(cdb1_value),
        // CALL also creates an SQ entry even though its ROB type is BRANCH. Commit any
        // ROB entry that has a matching SQ slot; non-store/non-call instructions simply miss.
        .commit_en(rob_commit_en1 || rob_commit_en2),
        .commit_rob_idx(rob_commit_en1 ?
                        rob_commit_rob_idx1 : rob_commit_rob_idx2),
        .mem_write_en(sq_mem_write_en),
        .mem_write_addr(sq_mem_write_addr),
        .mem_write_data(sq_mem_write_data),
        .fwd_check_en(lq_mem_read_en),
        .fwd_check_addr(lq_mem_read_addr),
        .fwd_hit(sq_fwd_hit),
        .fwd_data(sq_fwd_data),
        .rob_store_addr_ready(sq_rob_store_addr_ready),
        .rob_store_data_ready(sq_rob_store_data_ready),
        .rob_store_addr_ready_idx(sq_rob_store_addr_ready_idx),
        .rob_store_data_ready_idx(sq_rob_store_data_ready_idx),
        .rob_store_addr_value(sq_rob_store_addr_value),
        .rob_store_ready_value(sq_rob_store_ready_value),
        .full(sq_full),
        .flush(flush)
    );

    // --- ROB ---
    rob rob_inst(
        .clk(clk), .rst(reset),
        .alloc_en1(dispatch_valid1),
        .alloc_type1(rob_type1),
        .alloc_arch_rd1(dest_areg1),
        .alloc_old_phys1(old_phys1),
        .alloc_new_phys1(alloc_preg1 ? new_phys_rd1 : 7'd0),
        .alloc_pc1(fu_out_pc1),
        .alloc_branch_pred1(branch_pred1),
        .alloc_branch_target1(64'd0),  // predict not-taken, target=0
        .alloc_snap_id1(snap_id1),
        .alloc_idx1(rob_alloc_idx1),
        .alloc_en2(dispatch_valid2),
        .alloc_type2(rob_type2),
        .alloc_arch_rd2(dest_areg2),
        .alloc_old_phys2(old_phys2),
        .alloc_new_phys2(alloc_preg2 ? new_phys_rd2 : 7'd0),
        .alloc_pc2(fu_out_pc2),
        .alloc_branch_pred2(branch_pred2),
        .alloc_branch_target2(64'd0),
        .alloc_snap_id2(snap_id2),
        .alloc_idx2(rob_alloc_idx2),
        .cdb0_valid(cdb0_valid),
        .cdb0_rob_idx(cdb0_rob),
        .cdb0_value(cdb0_value),
        .cdb1_valid(cdb1_valid),
        .cdb1_rob_idx(cdb1_rob),
        .cdb1_value(cdb1_value),
        .sq_addr_ready(sq_rob_store_addr_ready),
        .sq_addr_rob_idx(sq_rob_store_addr_ready_idx),
        .sq_addr_val(sq_rob_store_addr_value),
        .sq_data_ready(sq_rob_store_data_ready),
        .sq_data_rob_idx(sq_rob_store_data_ready_idx),
        .sq_data_val(sq_rob_store_ready_value),
        .br_resolved(br_resolved_combined),
        .br_taken(br_taken_combined),
        .br_target(br_target_combined),
        .br_rob_idx(br_rob_idx_combined),
        .mispredict(rob_mispredict),
        .mispredict_target(rob_mispredict_target),
        .mispredict_rob_idx(rob_mispredict_rob_idx),
        .mispredict_snap_id(rob_mispredict_snap_id),
        .flush_all(rob_flush_all),
        .has_unresolved_branch(rob_has_unresolved_branch),
        .commit_en1(rob_commit_en1),
        .commit_type1(rob_commit_type1),
        .commit_arch_rd1(rob_commit_arch_rd1),
        .commit_old_phys1(rob_commit_old_phys1),
        .commit_new_phys1(rob_commit_new_phys1),
        .commit_rob_idx1(rob_commit_rob_idx1),
        .commit_value1(rob_commit_value1),
        .commit_en2(rob_commit_en2),
        .commit_type2(rob_commit_type2),
        .commit_arch_rd2(rob_commit_arch_rd2),
        .commit_old_phys2(rob_commit_old_phys2),
        .commit_new_phys2(rob_commit_new_phys2),
        .commit_rob_idx2(rob_commit_rob_idx2),
        .commit_value2(rob_commit_value2),
        .can_alloc2(rob_can_alloc2),
        .halt_committed(rob_halt_committed)
    );

    // --- Sync architectural register file to physical register file ---
    // The autograder may pre-load values into reg_file.registers during reset.
    // Since the OOO pipeline reads from the PRF, we copy on negedge reset.
    // The reg_file no longer clears regs 0-30 on clock edges during reset,
    // so backdoor-written values persist. The initial RAT is identity-mapped.
    integer sync_i;
    always @(negedge reset) begin
        for (sync_i = 0; sync_i < 32; sync_i = sync_i + 1) begin
            prf_inst.regs[sync_i] = reg_file.registers[sync_i];
        end
    end

    // --- CDB Arbiter ---
    cdb_arbiter cdb_arb(
        .alu0_valid(alu0_cdb_valid),
        .alu0_tag(alu0_cdb_tag),
        .alu0_value(alu0_cdb_value),
        .alu0_rob(alu0_cdb_rob),
        .fpu0_valid(fpu0_cdb_valid),
        .fpu0_tag(fpu0_cdb_tag),
        .fpu0_value(fpu0_cdb_value),
        .fpu0_rob(fpu0_cdb_rob),
        .lsu0_valid(lq_cdb_valid),
        .lsu0_tag(lq_cdb_tag),
        .lsu0_value(lq_cdb_value),
        .lsu0_rob(lq_cdb_rob),
        .alu1_valid(alu1_cdb_valid),
        .alu1_tag(alu1_cdb_tag),
        .alu1_value(alu1_cdb_value),
        .alu1_rob(alu1_cdb_rob),
        .fpu1_valid(fpu1_cdb_valid),
        .fpu1_tag(fpu1_cdb_tag),
        .fpu1_value(fpu1_cdb_value),
        .fpu1_rob(fpu1_cdb_rob),
        .lsu1_valid(1'b0),    // tie off 2nd LSU input
        .lsu1_tag(7'd0),
        .lsu1_value(64'd0),
        .lsu1_rob(5'd0),
        .cdb0_valid(cdb0_valid),
        .cdb0_tag(cdb0_tag),
        .cdb0_value(cdb0_value),
        .cdb0_rob(cdb0_rob),
        .cdb1_valid(cdb1_valid),
        .cdb1_tag(cdb1_tag),
        .cdb1_value(cdb1_value),
        .cdb1_rob(cdb1_rob),
        .alu0_stall(cdb_alu0_stall),
        .fpu0_stall(cdb_fpu0_stall),
        .lsu0_stall(cdb_lsu0_stall),
        .alu1_stall(cdb_alu1_stall),
        .fpu1_stall(cdb_fpu1_stall),
        .lsu1_stall(cdb_lsu1_stall)
    );

endmodule

module instruction_decoder(
    input [31:0] instruction,
    output reg [4:0] opcode,
    output reg [4:0] rd,
    output reg [4:0] rs,
    output reg [4:0] rt,
    output reg [11:0] L
);
    always @(*) begin
        opcode = instruction[31:27];
        rd = instruction[26:22];
        rs = instruction[21:17];
        rt = instruction[16:12];
        L = instruction[11:0];
    end
endmodule

module memory(
    input clk,
    input reset,
    input [63:0] PC,
    output [31:0] instruction,
    input [63:0] data_address,
    output [63:0] data_out,
    output data_ready,
    input write_enable,
    input [63:0] write_address,
    input [63:0] write_data,
    input [63:0] fetch_addr,
    output [511:0] fetch_data
);
    reg [7:0] bytes [0:`MEM_SIZE-1];

    assign instruction = {bytes[PC + 3], bytes[PC + 2], bytes[PC + 1], bytes[PC]};

    assign data_out = {bytes[data_address + 7], bytes[data_address + 6],
                       bytes[data_address + 5], bytes[data_address + 4],
                       bytes[data_address + 3], bytes[data_address + 2],
                       bytes[data_address + 1], bytes[data_address]};

    assign data_ready = 1'b1;

    // 64-byte fetch port: 16 instructions (each 32 bits = 4 bytes)
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

    always @(posedge clk) begin
        if (write_enable) begin
            bytes[write_address] <= write_data[7:0];
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
    // 4 read ports
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
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            registers[i] = 64'b0;
        end
        registers[31] = `MEM_SIZE;
    end

    // Reset clears architectural state once when reset is asserted.
    // Backdoor writes performed later while reset remains high still persist,
    // and the negedge-reset PRF sync copies that final state into P0-P31.
    always @(posedge reset) begin
        for (i = 0; i < 31; i = i + 1) begin
            registers[i] <= 64'b0;
        end
        registers[31] <= `MEM_SIZE;
    end

    always @(posedge clk) begin
        if (!reset) begin
            // Write port 2 first, then port 1 takes priority on conflict
            if (write_en2) begin
                registers[write_sel2] <= write_data2;
            end
            if (write_en1) begin
                registers[write_sel1] <= write_data1;
            end
        end
    end
endmodule

// ============================================================
// Task 3: Physical Register File (128x64, 4R/2W, ready bits)
// ============================================================
module phys_reg_file(
    input clk,
    input reset,
    // 4 combinational read ports
    input [6:0] read_sel1,
    input [6:0] read_sel2,
    input [6:0] read_sel3,
    input [6:0] read_sel4,
    output [63:0] read_data1,
    output [63:0] read_data2,
    output [63:0] read_data3,
    output [63:0] read_data4,
    output read_ready1,
    output read_ready2,
    output read_ready3,
    output read_ready4,
    // 2 write ports (from CDB)
    input write_en1,
    input [6:0] write_sel1,
    input [63:0] write_data1,
    input write_en2,
    input [6:0] write_sel2,
    input [63:0] write_data2,
    // 2 clear_ready ports (on rename)
    input clear_ready_en1,
    input [6:0] clear_ready_sel1,
    input clear_ready_en2,
    input [6:0] clear_ready_sel2
);
    reg [63:0] regs [0:127];
    reg ready [0:127];

    // Combinational reads
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
            // Clear ready bits (rename stage)
            if (clear_ready_en1) ready[clear_ready_sel1] <= 1'b0;
            if (clear_ready_en2) ready[clear_ready_sel2] <= 1'b0;
            // Write ports (CDB broadcast) - set value AND ready bit
            // Write port 2 first, port 1 takes priority on conflict
            if (write_en2) begin
                regs[write_sel2] <= write_data2;
                ready[write_sel2] <= 1'b1;
            end
            if (write_en1) begin
                regs[write_sel1] <= write_data1;
                ready[write_sel1] <= 1'b1;
            end
        end
    end
endmodule

// ============================================================
// Task 4: Free List (FIFO, 2 dequeue / 2 enqueue)
// ============================================================
module free_list(
    input clk,
    input reset,
    // 2 dequeue ports (rename allocates phys regs)
    input deq_en1,
    input deq_en2,
    output [6:0] deq_preg1,
    output [6:0] deq_preg2,
    // 2 enqueue ports (commit returns old phys regs)
    input enq_en1,
    input [6:0] enq_preg1,
    input enq_en2,
    input [6:0] enq_preg2,
    // Status
    output can_alloc2,
    // Snapshot (2 ports for dual-issue branches)
    input snap_en1,
    input [1:0] snap_id1,
    input snap_en2,
    input [1:0] snap_id2,
    // Misprediction restore
    input restore_en,
    input [1:0] restore_id
);
    reg [6:0] fifo [0:127];
    reg [6:0] head;
    reg [6:0] tail;
    reg [7:0] cnt; // 8-bit to hold 0..128

    // 4 snapshot slots for head pointer
    reg [6:0] snap_head [0:3];

    assign deq_preg1 = fifo[head];
    assign deq_preg2 = fifo[head + 7'd1];
    assign can_alloc2 = (cnt >= 8'd2);

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize with P32-P127 (96 entries)
            for (i = 0; i < 96; i = i + 1) begin
                fifo[i] <= 7'd32 + i[6:0];
            end
            // Clear rest
            for (i = 96; i < 128; i = i + 1) begin
                fifo[i] <= 7'd0;
            end
            head <= 7'd0;
            tail <= 7'd96;
            cnt <= 8'd96;
        end else if (restore_en) begin
            head <= snap_head[restore_id];
            // Recalculate count: entries from restored head to tail
            if (tail >= snap_head[restore_id])
                cnt <= {1'b0, tail} - {1'b0, snap_head[restore_id]};
            else
                cnt <= 8'd128 - {1'b0, snap_head[restore_id]} + {1'b0, tail};
        end else begin
            // Take snapshots: capture head AFTER this instruction's own dequeue
            if (snap_en1)
                snap_head[snap_id1] <= deq_en1 ? (head + 7'd1) : head;
            if (snap_en2) begin
                // Slot 2's snapshot reflects head after both slot 1 and slot 2 dequeues
                snap_head[snap_id2] <= head + (deq_en1 ? 7'd1 : 7'd0) + (deq_en2 ? 7'd1 : 7'd0);
            end
            // Compute deq and enq counts
            // Dequeue (advance head)
            if (deq_en1 && deq_en2) begin
                head <= head + 7'd2;
            end else if (deq_en1) begin
                head <= head + 7'd1;
            end
            // Enqueue (advance tail)
            if (enq_en1 && enq_en2) begin
                fifo[tail] <= enq_preg1;
                fifo[tail + 7'd1] <= enq_preg2;
                tail <= tail + 7'd2;
            end else if (enq_en1) begin
                fifo[tail] <= enq_preg1;
                tail <= tail + 7'd1;
            end else if (enq_en2) begin
                fifo[tail] <= enq_preg2;
                tail <= tail + 7'd1;
            end
            // Single net count update combining deq and enq
            cnt <= cnt
                - ({7'd0, deq_en1} + {7'd0, deq_en2})
                + ({7'd0, enq_en1} + {7'd0, enq_en2});
        end
    end
endmodule

// ============================================================
// Task 5: RAT with Snapshot Checkpoints
// ============================================================
module rat(
    input clk,
    input reset,
    // 4 combinational read ports (arch reg -> phys reg)
    input [4:0] read_sel1,
    input [4:0] read_sel2,
    input [4:0] read_sel3,
    input [4:0] read_sel4,
    output [6:0] read_preg1,
    output [6:0] read_preg2,
    output [6:0] read_preg3,
    output [6:0] read_preg4,
    // 2 write ports (rename stage updates)
    input write_en1,
    input [4:0] write_areg1,
    input [6:0] write_preg1,
    input write_en2,
    input [4:0] write_areg2,
    input [6:0] write_preg2,
    // Snapshot (2 ports for dual-issue branches)
    input snap_en1,
    input [1:0] snap_id1,
    input snap_en2,
    input [1:0] snap_id2,
    // Override for snapshot 1: un-suppressed slot 1 write (for rat_same_dest case)
    input snap1_wr_override,
    input [4:0] snap1_wr_areg,
    input [6:0] snap1_wr_preg,
    // Restore
    input restore_en,
    input [1:0] restore_id
);
    reg [6:0] rat_table [0:31];
    // Flattened snapshots: 4 checkpoints x 32 entries = 128 entries
    // snapshot[s][i] -> snap_store[s*32 + i]
    reg [6:0] snap_store [0:127];

    // Combinational reads
    assign read_preg1 = rat_table[read_sel1];
    assign read_preg2 = rat_table[read_sel2];
    assign read_preg3 = rat_table[read_sel3];
    assign read_preg4 = rat_table[read_sel4];

    integer i;
    integer s;
    reg [6:0] snap_base;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Identity mapping: R0->P0, ..., R31->P31
            for (i = 0; i < 32; i = i + 1) begin
                rat_table[i] <= i[6:0];
            end
            // Clear all snapshots to identity
            for (i = 0; i < 128; i = i + 1) begin
                snap_store[i] <= i[4:0];
            end
        end else if (restore_en) begin
            // Restore full RAT from snapshot
            snap_base = {restore_id, 5'b0};
            for (i = 0; i < 32; i = i + 1) begin
                rat_table[i] <= snap_store[snap_base + i];
            end
        end else begin
            // Write ports: port 2 first, port 1 takes priority on conflict
            if (write_en2) begin
                rat_table[write_areg2] <= write_preg2;
            end
            if (write_en1) begin
                rat_table[write_areg1] <= write_preg1;
            end
            // Take snapshot 1 (for branch in slot 1): captures state after slot 1's rename only
            if (snap_en1) begin
                snap_base = {snap_id1, 5'b0};
                for (i = 0; i < 32; i = i + 1) begin
                    snap_store[snap_base + i] <= rat_table[i];
                end
                // Include slot 1's write — use override when write_en1 is suppressed (rat_same_dest)
                if (write_en1) begin
                    snap_store[snap_base + write_areg1] <= write_preg1;
                end else if (snap1_wr_override) begin
                    snap_store[snap_base + snap1_wr_areg] <= snap1_wr_preg;
                end
            end
            // Take snapshot 2 (for branch in slot 2): captures state after both slots' renames
            if (snap_en2) begin
                snap_base = {snap_id2, 5'b0};
                for (i = 0; i < 32; i = i + 1) begin
                    snap_store[snap_base + i] <= rat_table[i];
                end
                // Include both writes (en1 overrides en2 on conflict)
                if (write_en2) begin
                    snap_store[snap_base + write_areg2] <= write_preg2;
                end
                if (write_en1) begin
                    snap_store[snap_base + write_areg1] <= write_preg1;
                end
            end
        end
    end
endmodule

// ============================================================================
// Task 6: Parameterized Reservation Station
// ============================================================================
module reservation_station #(
    parameter NUM_ENTRIES = 4
)(
    input clk,
    input rst,

    // Dispatch interface
    input dispatch_en,
    input [4:0] dispatch_opcode,
    input [63:0] dispatch_src1_val,
    input [6:0] dispatch_src1_tag,
    input dispatch_src1_rdy,
    input [63:0] dispatch_src2_val,
    input [6:0] dispatch_src2_tag,
    input dispatch_src2_rdy,
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

    // Issue outputs
    output reg issue_valid,
    output reg [4:0] issue_opcode,
    output reg [63:0] issue_src1_val,
    output reg [63:0] issue_src2_val,
    output reg [6:0] issue_dest_tag,
    output reg [4:0] issue_rob_idx,
    output reg [63:0] issue_imm,
    output reg [63:0] issue_pc,
    input issue_ack,

    // Status
    output full,
    input flush
);

    // Entry storage
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
    reg [4:0] age [0:NUM_ENTRIES-1];

    reg [4:0] age_counter;

    // Full detection: count valid entries
    integer v;
    reg [$clog2(NUM_ENTRIES):0] valid_count;
    always @(*) begin
        valid_count = 0;
        for (v = 0; v < NUM_ENTRIES; v = v + 1)
            if (valid[v]) valid_count = valid_count + 1;
    end
    assign full = (valid_count == NUM_ENTRIES);

    // Find free slot
    integer f_idx;
    reg [$clog2(NUM_ENTRIES)-1:0] free_slot;
    reg free_found;
    always @(*) begin
        free_found = 0;
        free_slot = 0;
        for (f_idx = 0; f_idx < NUM_ENTRIES; f_idx = f_idx + 1) begin
            if (!valid[f_idx] && !free_found) begin
                free_slot = f_idx[$clog2(NUM_ENTRIES)-1:0];
                free_found = 1;
            end
        end
    end

    // Issue selection: oldest ready entry (lowest age among valid with both srcs ready)
    integer s_idx;
    reg [$clog2(NUM_ENTRIES)-1:0] issue_slot;
    reg issue_found;
    reg [4:0] issue_min_age;
    always @(*) begin
        issue_found = 0;
        issue_slot = 0;
        issue_min_age = 5'h1f;
        for (s_idx = 0; s_idx < NUM_ENTRIES; s_idx = s_idx + 1) begin
            if (valid[s_idx] && src1_rdy[s_idx] && src2_rdy[s_idx]) begin
                if (!issue_found || age[s_idx] < issue_min_age) begin
                    issue_slot = s_idx[$clog2(NUM_ENTRIES)-1:0];
                    issue_min_age = age[s_idx];
                    issue_found = 1;
                end
            end
        end
    end

    // Issue output
    always @(*) begin
        issue_valid = issue_found;
        if (issue_found) begin
            issue_opcode = opcode[issue_slot];
            issue_src1_val = src1_val[issue_slot];
            issue_src2_val = src2_val[issue_slot];
            issue_dest_tag = dest_tag[issue_slot];
            issue_rob_idx = rob_idx[issue_slot];
            issue_imm = imm[issue_slot];
            issue_pc = pc[issue_slot];
        end else begin
            issue_opcode = 0;
            issue_src1_val = 0;
            issue_src2_val = 0;
            issue_dest_tag = 0;
            issue_rob_idx = 0;
            issue_imm = 0;
            issue_pc = 0;
        end
    end

    // Sequential logic
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                src1_rdy[i] <= 0;
                src2_rdy[i] <= 0;
            end
            age_counter <= 0;
        end else begin
            // CDB snoop: update pending sources
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (valid[i]) begin
                    if (!src1_rdy[i] && cdb0_valid && src1_tag[i] == cdb0_tag) begin
                        src1_val[i] <= cdb0_value;
                        src1_rdy[i] <= 1;
                    end
                    if (!src1_rdy[i] && cdb1_valid && src1_tag[i] == cdb1_tag) begin
                        src1_val[i] <= cdb1_value;
                        src1_rdy[i] <= 1;
                    end
                    if (!src2_rdy[i] && cdb0_valid && src2_tag[i] == cdb0_tag) begin
                        src2_val[i] <= cdb0_value;
                        src2_rdy[i] <= 1;
                    end
                    if (!src2_rdy[i] && cdb1_valid && src2_tag[i] == cdb1_tag) begin
                        src2_val[i] <= cdb1_value;
                        src2_rdy[i] <= 1;
                    end
                end
            end

            // Issue ack: clear issued entry
            if (issue_ack && issue_found) begin
                valid[issue_slot] <= 0;
            end

            // Dispatch: write to free slot
            if (dispatch_en && free_found) begin
                valid[free_slot] <= 1;
                opcode[free_slot] <= dispatch_opcode;
                src1_val[free_slot] <= dispatch_src1_val;
                src1_tag[free_slot] <= dispatch_src1_tag;
                src1_rdy[free_slot] <= dispatch_src1_rdy;
                src2_val[free_slot] <= dispatch_src2_val;
                src2_tag[free_slot] <= dispatch_src2_tag;
                src2_rdy[free_slot] <= dispatch_src2_rdy;
                dest_tag[free_slot] <= dispatch_dest_tag;
                rob_idx[free_slot] <= dispatch_rob_idx;
                imm[free_slot] <= dispatch_imm;
                pc[free_slot] <= dispatch_pc;
                age[free_slot] <= age_counter;
                age_counter <= age_counter + 1;
            end
        end
    end

endmodule

// ============================================================================
// Task 7: ALU Pipe (2-stage pipelined)
// ============================================================================
module alu_pipe(
    input clk,
    input rst,

    // Issue interface
    input issue_valid,
    input [4:0] issue_opcode,
    input [63:0] issue_src1,
    input [63:0] issue_src2,
    input [6:0] issue_dest_tag,
    input [4:0] issue_rob_idx,
    input [63:0] issue_imm,
    input [63:0] issue_pc,
    output issue_ready,

    // CDB output
    output reg cdb_valid,
    output reg [6:0] cdb_tag,
    output reg [63:0] cdb_value,
    output reg [4:0] cdb_rob_idx,

    // Branch resolution
    output reg br_resolved,
    output reg br_taken,
    output reg [63:0] br_target,
    output reg [4:0] br_rob_idx_out,

    input cdb_stall,
    input flush
);

    // ========================================================================
    // Operation category encoding (decoded in stage 1)
    // ========================================================================
    localparam CAT_ARITH  = 3'd0;  // ADD, ADDI, SUB, SUBI, MUL, DIV
    localparam CAT_LOGIC  = 3'd1;  // AND, OR, XOR, NOT
    localparam CAT_SHIFT  = 3'd2;  // SHFTR, SHFTRI, SHFTL, SHFTLI
    localparam CAT_BRANCH = 3'd3;  // BR, BRR, BRR_L, BRNZ, CALL, RETURN, BRGT
    localparam CAT_MOVE   = 3'd4;  // MOV, MOVI

    // Sub-operation encoding within each category
    localparam SUB_ADD  = 3'd0;
    localparam SUB_SUB  = 3'd1;
    localparam SUB_MUL  = 3'd2;
    localparam SUB_DIV  = 3'd3;
    localparam SUB_AND  = 3'd0;
    localparam SUB_OR   = 3'd1;
    localparam SUB_XOR  = 3'd2;
    localparam SUB_NOT  = 3'd3;
    localparam SUB_SHR  = 3'd0;
    localparam SUB_SHL  = 3'd1;
    localparam SUB_MOV  = 3'd0;
    localparam SUB_MOVI = 3'd1;
    localparam SUB_BR   = 3'd0;
    localparam SUB_BRR  = 3'd1;
    localparam SUB_BRRL = 3'd2;
    localparam SUB_BRNZ = 3'd3;
    localparam SUB_CALL = 3'd4;
    localparam SUB_RET  = 3'd5;
    localparam SUB_BRGT = 3'd6;

    // ========================================================================
    // Stage 1 pipeline registers (Decode / Operand Preparation)
    // ========================================================================
    reg        s1_valid;
    reg [2:0]  s1_category;       // operation category
    reg [2:0]  s1_sub_op;         // sub-operation within category
    reg [63:0] s1_operand_a;      // prepared first operand
    reg [63:0] s1_operand_b;      // prepared second operand
    reg        s1_is_branch;      // is a branch instruction
    reg        s1_br_taken;       // branch condition result (evaluated in stage 1)
    reg [63:0] s1_br_target;      // branch target (computed in stage 1)
    reg        s1_has_result;     // instruction produces a register result
    reg [6:0]  s1_dest_tag;
    reg [4:0]  s1_rob_idx;

    // ========================================================================
    // Stage 1 combinational logic: Decode + operand select + condition eval
    // ========================================================================
    reg [2:0]  s1_cat_next;
    reg [2:0]  s1_sub_next;
    reg [63:0] s1_opa_next;
    reg [63:0] s1_opb_next;
    reg        s1_isbr_next;
    reg        s1_taken_next;
    reg [63:0] s1_brtgt_next;
    reg        s1_hasres_next;

    always @(*) begin
        // Defaults
        s1_cat_next    = CAT_ARITH;
        s1_sub_next    = SUB_ADD;
        s1_opa_next    = 64'd0;
        s1_opb_next    = 64'd0;
        s1_isbr_next   = 1'b0;
        s1_taken_next  = 1'b0;
        s1_brtgt_next  = 64'd0;
        s1_hasres_next = 1'b1;  // most instructions produce a result

        case (issue_opcode)
            // --- Arithmetic ---
            5'h18: begin // ADD rd, rs, rt
                s1_cat_next = CAT_ARITH; s1_sub_next = SUB_ADD;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h19: begin // ADDI rd, L
                s1_cat_next = CAT_ARITH; s1_sub_next = SUB_ADD;
                s1_opa_next = issue_src1; s1_opb_next = issue_imm;
            end
            5'h1a: begin // SUB rd, rs, rt
                s1_cat_next = CAT_ARITH; s1_sub_next = SUB_SUB;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h1b: begin // SUBI rd, L
                s1_cat_next = CAT_ARITH; s1_sub_next = SUB_SUB;
                s1_opa_next = issue_src1; s1_opb_next = issue_imm;
            end
            5'h1c: begin // MUL rd, rs, rt
                s1_cat_next = CAT_ARITH; s1_sub_next = SUB_MUL;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h1d: begin // DIV rd, rs, rt
                s1_cat_next = CAT_ARITH; s1_sub_next = SUB_DIV;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end

            // --- Logic ---
            5'h00: begin // AND
                s1_cat_next = CAT_LOGIC; s1_sub_next = SUB_AND;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h01: begin // OR
                s1_cat_next = CAT_LOGIC; s1_sub_next = SUB_OR;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h02: begin // XOR
                s1_cat_next = CAT_LOGIC; s1_sub_next = SUB_XOR;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h03: begin // NOT
                s1_cat_next = CAT_LOGIC; s1_sub_next = SUB_NOT;
                s1_opa_next = issue_src1; s1_opb_next = 64'd0;
            end

            // --- Shift ---
            5'h04: begin // SHFTR src1 >> src2
                s1_cat_next = CAT_SHIFT; s1_sub_next = SUB_SHR;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h05: begin // SHFTRI src1 >> imm
                s1_cat_next = CAT_SHIFT; s1_sub_next = SUB_SHR;
                s1_opa_next = issue_src1; s1_opb_next = issue_imm;
            end
            5'h06: begin // SHFTL src1 << src2
                s1_cat_next = CAT_SHIFT; s1_sub_next = SUB_SHL;
                s1_opa_next = issue_src1; s1_opb_next = issue_src2;
            end
            5'h07: begin // SHFTLI src1 << imm
                s1_cat_next = CAT_SHIFT; s1_sub_next = SUB_SHL;
                s1_opa_next = issue_src1; s1_opb_next = issue_imm;
            end

            // --- Branch ---
            5'h08: begin // BR rd -> target = src1, taken = 1
                s1_cat_next = CAT_BRANCH; s1_sub_next = SUB_BR;
                s1_isbr_next = 1'b1; s1_hasres_next = 1'b0;
                s1_brtgt_next = issue_src1;
                s1_taken_next = 1'b1;
            end
            5'h09: begin // BRR rd -> target = src1 + pc, taken = 1
                s1_cat_next = CAT_BRANCH; s1_sub_next = SUB_BRR;
                s1_isbr_next = 1'b1; s1_hasres_next = 1'b0;
                // Prepare operands for target addition in stage 2
                s1_opa_next = issue_src1; s1_opb_next = issue_pc;
                s1_taken_next = 1'b1;
            end
            5'h0a: begin // BRR L -> target = imm + pc, taken = 1
                s1_cat_next = CAT_BRANCH; s1_sub_next = SUB_BRRL;
                s1_isbr_next = 1'b1; s1_hasres_next = 1'b0;
                // Prepare operands for target addition in stage 2
                s1_opa_next = issue_imm; s1_opb_next = issue_pc;
                s1_taken_next = 1'b1;
            end
            5'h0b: begin // BRNZ rd, rs -> target = src1, taken = (src2 != 0)
                s1_cat_next = CAT_BRANCH; s1_sub_next = SUB_BRNZ;
                s1_isbr_next = 1'b1; s1_hasres_next = 1'b0;
                s1_brtgt_next = issue_src1;
                // Condition evaluation in stage 1
                s1_taken_next = (issue_src2 != 64'd0);
            end
            5'h0c: begin // CALL -> target = src1, taken = 1 (no register write)
                s1_cat_next = CAT_BRANCH; s1_sub_next = SUB_CALL;
                s1_isbr_next = 1'b1; s1_hasres_next = 1'b0;
                s1_brtgt_next = issue_src1;
                s1_taken_next = 1'b1;
            end
            5'h0d: begin // RETURN -> resolved by LQ, not ALU (this case shouldn't be reached)
                s1_cat_next = CAT_BRANCH; s1_sub_next = SUB_RET;
                s1_isbr_next = 1'b1; s1_hasres_next = 1'b0;
                s1_brtgt_next = 64'd0;
                s1_taken_next = 1'b1;
            end
            5'h0e: begin // BRGT rd, rs, rt -> target = rd register, taken = (rs > rt)
                s1_cat_next = CAT_BRANCH; s1_sub_next = SUB_BRGT;
                s1_isbr_next = 1'b1; s1_hasres_next = 1'b0;
                s1_brtgt_next = issue_imm;
                // Condition: rs > rt (src1 > src2)
                s1_taken_next = (issue_src1 > issue_src2);
            end

            // --- Move ---
            5'h11: begin // MOV rd, rs -> result = src1
                s1_cat_next = CAT_MOVE; s1_sub_next = SUB_MOV;
                s1_opa_next = issue_src1;
            end
            5'h12: begin // MOVI -> result = {rd[63:12], L[11:0]}
                s1_cat_next = CAT_MOVE; s1_sub_next = SUB_MOVI;
                s1_opa_next = issue_src1; // preserve upper 52 bits
                s1_opb_next = issue_imm;  // literal goes into low 12 bits
            end

            default: begin
                s1_cat_next    = CAT_ARITH;
                s1_sub_next    = SUB_ADD;
                s1_opa_next    = 64'd0;
                s1_opb_next    = 64'd0;
                s1_hasres_next = 1'b0;
            end
        endcase
    end

    // Can accept new issue when stage 1 is free and not held by CDB backpressure
    assign issue_ready = (!s1_valid && !cdb_stall) || flush;

    // ========================================================================
    // Stage 2 combinational logic: Execute / Result Generation
    // Uses latched operands and control signals from stage 1 registers
    // ========================================================================
    reg [63:0] s2_result_comb;
    reg [63:0] s2_brtgt_comb;

    always @(*) begin
        s2_result_comb = 64'd0;
        s2_brtgt_comb  = s1_br_target; // default: pre-computed target from stage 1

        case (s1_category)
            CAT_ARITH: begin
                case (s1_sub_op)
                    SUB_ADD: s2_result_comb = s1_operand_a + s1_operand_b;
                    SUB_SUB: s2_result_comb = s1_operand_a - s1_operand_b;
                    SUB_MUL: s2_result_comb = s1_operand_a * s1_operand_b;
                    SUB_DIV: s2_result_comb = (s1_operand_b != 64'd0) ?
                                              s1_operand_a / s1_operand_b : 64'd0;
                    default: s2_result_comb = 64'd0;
                endcase
            end

            CAT_LOGIC: begin
                case (s1_sub_op)
                    SUB_AND: s2_result_comb = s1_operand_a & s1_operand_b;
                    SUB_OR:  s2_result_comb = s1_operand_a | s1_operand_b;
                    SUB_XOR: s2_result_comb = s1_operand_a ^ s1_operand_b;
                    SUB_NOT: s2_result_comb = ~s1_operand_a;
                    default: s2_result_comb = 64'd0;
                endcase
            end

            CAT_SHIFT: begin
                case (s1_sub_op)
                    SUB_SHR: s2_result_comb = s1_operand_a >> s1_operand_b;
                    SUB_SHL: s2_result_comb = s1_operand_a << s1_operand_b;
                    default: s2_result_comb = 64'd0;
                endcase
            end

            CAT_BRANCH: begin
                case (s1_sub_op)
                    SUB_BRR:  s2_brtgt_comb = s1_operand_a + s1_operand_b; // src1 + pc
                    SUB_BRRL: s2_brtgt_comb = s1_operand_a + s1_operand_b; // imm + pc
                    SUB_CALL: s2_result_comb = s1_operand_a - s1_operand_b; // unused by CALL
                    SUB_RET:  s2_result_comb = s1_operand_a - s1_operand_b; // src1 - 8
                    SUB_BRGT: s2_brtgt_comb = s1_br_target;
                    default: ; // BR, BRNZ: target already in s1_br_target
                endcase
            end

            CAT_MOVE: begin
                case (s1_sub_op)
                    SUB_MOV:  s2_result_comb = s1_operand_a;
                    SUB_MOVI: s2_result_comb = {s1_operand_a[63:12], s1_operand_b[11:0]};
                    default:  s2_result_comb = 64'd0;
                endcase
            end

            default: s2_result_comb = 64'd0;
        endcase
    end

    // ========================================================================
    // Pipeline register updates
    // ========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            s1_valid    <= 1'b0;
            cdb_valid   <= 1'b0;
            br_resolved <= 1'b0;
        end else if (cdb_stall) begin
            // Hold all pipeline state when CDB is stalled - don't advance pipeline
            // But clear br_resolved so we don't re-resolve the same branch every cycle
            br_resolved <= 1'b0;
        end else begin
            // ---- Latch into Stage 1 registers (Decode/Operand Prep) ----
            s1_valid <= issue_valid && issue_ready;
            if (issue_valid && issue_ready) begin
                s1_category   <= s1_cat_next;
                s1_sub_op     <= s1_sub_next;
                s1_operand_a  <= s1_opa_next;
                s1_operand_b  <= s1_opb_next;
                s1_is_branch  <= s1_isbr_next;
                s1_br_taken   <= s1_taken_next;
                s1_br_target  <= s1_brtgt_next;
                s1_has_result <= s1_hasres_next;
                s1_dest_tag   <= issue_dest_tag;
                s1_rob_idx    <= issue_rob_idx;
            end

            // ---- Stage 2 output (Execute results -> CDB) ----
            cdb_valid   <= s1_valid && s1_has_result;
            cdb_tag     <= s1_dest_tag;
            cdb_value   <= s2_result_comb;
            cdb_rob_idx <= s1_rob_idx;

            // ---- Branch resolution output (from stage 2 execution) ----
            br_resolved    <= s1_valid && s1_is_branch;
            br_taken       <= s1_br_taken;
            br_target      <= s2_brtgt_comb;
            br_rob_idx_out <= s1_rob_idx;
        end
    end

endmodule

// ============================================================================
// Task 8: FPU Pipe (4-stage pipelined, wraps existing FPU)
// ============================================================================
module fpu_pipe(
    input clk,
    input rst,

    // Issue interface
    input issue_valid,
    input [4:0] issue_opcode,
    input [63:0] issue_src1,
    input [63:0] issue_src2,
    input [6:0] issue_dest_tag,
    input [4:0] issue_rob_idx,
    output issue_ready,

    // CDB output
    output reg cdb_valid,
    output reg [6:0] cdb_tag,
    output reg [63:0] cdb_value,
    output reg [4:0] cdb_rob_idx,

    input cdb_stall,
    input flush
);
    reg s1_valid, s2_valid, s3_valid, s4_valid, s5_valid;
    reg [4:0]  s1_opcode;
    reg [63:0] s1_src1, s1_src2;
    reg [6:0]  s1_dest_tag, s2_dest_tag, s3_dest_tag, s4_dest_tag, s5_dest_tag;
    reg [4:0]  s1_rob_idx,  s2_rob_idx,  s3_rob_idx,  s4_rob_idx,  s5_rob_idx;
    reg [63:0] s2_result, s3_result, s4_result, s5_result;

    wire [63:0] s1_negated_src2 = {~s1_src2[63], s1_src2[62:0]};
    wire [63:0] fadd_result;
    wire [63:0] fsub_result;
    wire [63:0] fmul_result;
    wire [63:0] fdiv_result;
    reg  [63:0] s1_result_comb;

    fpu_add fadd_unit(.a(s1_src1), .b(s1_src2), .result(fadd_result));
    fpu_add fsub_unit(.a(s1_src1), .b(s1_negated_src2), .result(fsub_result));
    fpu_mul fmul_unit(.a(s1_src1), .b(s1_src2), .result(fmul_result));
    fpu_div fdiv_unit(.a(s1_src1), .b(s1_src2), .result(fdiv_result));

    always @(*) begin
        case (s1_opcode)
            5'h14: s1_result_comb = fadd_result;
            5'h15: s1_result_comb = fsub_result;
            5'h16: s1_result_comb = fmul_result;
            5'h17: s1_result_comb = fdiv_result;
            default: s1_result_comb = 64'd0;
        endcase
    end

    assign issue_ready = (!s1_valid && !cdb_stall) || flush;

    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            s1_valid  <= 1'b0;
            s2_valid  <= 1'b0;
            s3_valid  <= 1'b0;
            s4_valid  <= 1'b0;
            s5_valid  <= 1'b0;
            cdb_valid <= 1'b0;
        end else if (cdb_stall) begin
            // Hold the entire pipe when the CDB can't accept a result.
        end else begin
            s1_valid <= issue_valid && issue_ready;
            if (issue_valid && issue_ready) begin
                s1_opcode   <= issue_opcode;
                s1_src1     <= issue_src1;
                s1_src2     <= issue_src2;
                s1_dest_tag <= issue_dest_tag;
                s1_rob_idx  <= issue_rob_idx;
            end

            s2_valid    <= s1_valid;
            s2_result   <= s1_result_comb;
            s2_dest_tag <= s1_dest_tag;
            s2_rob_idx  <= s1_rob_idx;

            s3_valid    <= s2_valid;
            s3_result   <= s2_result;
            s3_dest_tag <= s2_dest_tag;
            s3_rob_idx  <= s2_rob_idx;

            s4_valid    <= s3_valid;
            s4_result   <= s3_result;
            s4_dest_tag <= s3_dest_tag;
            s4_rob_idx  <= s3_rob_idx;

            s5_valid    <= s4_valid;
            s5_result   <= s4_result;
            s5_dest_tag <= s4_dest_tag;
            s5_rob_idx  <= s4_rob_idx;

            cdb_valid   <= s5_valid;
            cdb_tag     <= s5_dest_tag;
            cdb_value   <= s5_result;
            cdb_rob_idx <= s5_rob_idx;
        end
    end

endmodule

// ============================================================================
// FPU Wrapper (contains both FPU pipe instances)
// ============================================================================
module fpu(
    input clk,
    input rst,

    // FPU pipe 0
    input        pipe0_issue_valid,
    input [4:0]  pipe0_issue_opcode,
    input [63:0] pipe0_issue_src1,
    input [63:0] pipe0_issue_src2,
    input [6:0]  pipe0_issue_dest_tag,
    input [4:0]  pipe0_issue_rob_idx,
    output       pipe0_issue_ready,
    output       pipe0_cdb_valid,
    output [6:0] pipe0_cdb_tag,
    output [63:0] pipe0_cdb_value,
    output [4:0] pipe0_cdb_rob_idx,

    // FPU pipe 1
    input        pipe1_issue_valid,
    input [4:0]  pipe1_issue_opcode,
    input [63:0] pipe1_issue_src1,
    input [63:0] pipe1_issue_src2,
    input [6:0]  pipe1_issue_dest_tag,
    input [4:0]  pipe1_issue_rob_idx,
    output       pipe1_issue_ready,
    output       pipe1_cdb_valid,
    output [6:0] pipe1_cdb_tag,
    output [63:0] pipe1_cdb_value,
    output [4:0] pipe1_cdb_rob_idx,

    input pipe0_cdb_stall,
    input pipe1_cdb_stall,
    input flush
);

    fpu_pipe fpu_pipe0(
        .clk(clk), .rst(rst),
        .issue_valid(pipe0_issue_valid),
        .issue_opcode(pipe0_issue_opcode),
        .issue_src1(pipe0_issue_src1),
        .issue_src2(pipe0_issue_src2),
        .issue_dest_tag(pipe0_issue_dest_tag),
        .issue_rob_idx(pipe0_issue_rob_idx),
        .issue_ready(pipe0_issue_ready),
        .cdb_valid(pipe0_cdb_valid),
        .cdb_tag(pipe0_cdb_tag),
        .cdb_value(pipe0_cdb_value),
        .cdb_rob_idx(pipe0_cdb_rob_idx),
        .cdb_stall(pipe0_cdb_stall),
        .flush(flush)
    );

    fpu_pipe fpu_pipe1(
        .clk(clk), .rst(rst),
        .issue_valid(pipe1_issue_valid),
        .issue_opcode(pipe1_issue_opcode),
        .issue_src1(pipe1_issue_src1),
        .issue_src2(pipe1_issue_src2),
        .issue_dest_tag(pipe1_issue_dest_tag),
        .issue_rob_idx(pipe1_issue_rob_idx),
        .issue_ready(pipe1_issue_ready),
        .cdb_valid(pipe1_cdb_valid),
        .cdb_tag(pipe1_cdb_tag),
        .cdb_value(pipe1_cdb_value),
        .cdb_rob_idx(pipe1_cdb_rob_idx),
        .cdb_stall(pipe1_cdb_stall),
        .flush(flush)
    );

endmodule

// ============================================================================
// Task 9: Load Queue (8 entries)
// ============================================================================
module load_queue(
    input clk,
    input rst,

    // Dispatch
    input dispatch_en,
    input [63:0] dispatch_base_val,
    input [6:0] dispatch_base_tag,
    input dispatch_base_ready,
    input [63:0] dispatch_imm,
    input [6:0] dispatch_dest_tag,
    input [4:0] dispatch_rob_idx,
    input [4:0] dispatch_opcode,

    // CDB snoop (2 buses)
    input cdb0_valid,
    input [6:0] cdb0_tag,
    input [63:0] cdb0_value,
    input cdb1_valid,
    input [6:0] cdb1_tag,
    input [63:0] cdb1_value,

    // Memory read port
    output reg mem_read_en,
    output reg [63:0] mem_read_addr,
    input [63:0] mem_read_data,

    // Store-to-load forwarding
    input sq_fwd_valid,
    input [63:0] sq_fwd_data,

    // CDB output
    output reg cdb_valid,
    output reg [6:0] cdb_tag,
    output reg [63:0] cdb_value,
    output reg [4:0] cdb_rob_idx,

    // Branch resolution (for RETURN instructions)
    output reg br_resolved,
    output reg br_taken,
    output reg [63:0] br_target,
    output reg [4:0] br_rob_idx_out,

    // CDB backpressure
    input cdb_stall,

    // Status
    output full,
    input flush
);

    parameter NUM_ENTRIES = 8;

    reg lq_valid [0:NUM_ENTRIES-1];
    reg [63:0] lq_base_val [0:NUM_ENTRIES-1];
    reg [6:0] lq_base_tag [0:NUM_ENTRIES-1];
    reg lq_base_ready [0:NUM_ENTRIES-1];
    reg [63:0] lq_imm [0:NUM_ENTRIES-1];
    reg [6:0] lq_dest_tag [0:NUM_ENTRIES-1];
    reg [4:0] lq_rob_idx [0:NUM_ENTRIES-1];
    reg [4:0] lq_opcode [0:NUM_ENTRIES-1];
    reg lq_addr_computed [0:NUM_ENTRIES-1];
    reg [63:0] lq_addr [0:NUM_ENTRIES-1];
    reg [63:0] lq_mem_data [0:NUM_ENTRIES-1]; // loaded data from memory
    reg lq_done [0:NUM_ENTRIES-1];
    reg [4:0] lq_age [0:NUM_ENTRIES-1];

    reg [4:0] age_counter;

    // Full detection
    integer vc;
    reg [3:0] valid_count;
    always @(*) begin
        valid_count = 0;
        for (vc = 0; vc < NUM_ENTRIES; vc = vc + 1)
            if (lq_valid[vc]) valid_count = valid_count + 1;
    end
    assign full = (valid_count == NUM_ENTRIES);

    // Find free slot
    integer fi;
    reg [2:0] free_slot;
    reg free_found;
    always @(*) begin
        free_found = 0;
        free_slot = 0;
        for (fi = 0; fi < NUM_ENTRIES; fi = fi + 1) begin
            if (!lq_valid[fi] && !free_found) begin
                free_slot = fi[2:0];
                free_found = 1;
            end
        end
    end

    // Find oldest entry ready to issue memory read (addr_computed && !done)
    integer si;
    reg [2:0] read_slot;
    reg read_found;
    reg [4:0] read_min_age;
    always @(*) begin
        read_found = 0;
        read_slot = 0;
        read_min_age = 5'h1f;
        for (si = 0; si < NUM_ENTRIES; si = si + 1) begin
            if (lq_valid[si] && lq_addr_computed[si] && !lq_done[si]) begin
                if (!read_found || lq_age[si] < read_min_age) begin
                    read_slot = si[2:0];
                    read_min_age = lq_age[si];
                    read_found = 1;
                end
            end
        end
    end

    // Memory read request
    always @(*) begin
        mem_read_en = read_found;
        mem_read_addr = read_found ? lq_addr[read_slot] : 64'd0;
    end

    // Find oldest done entry to output on CDB
    integer ci;
    reg [2:0] cdb_slot;
    reg cdb_found;
    reg [4:0] cdb_min_age;
    always @(*) begin
        cdb_found = 0;
        cdb_slot = 0;
        cdb_min_age = 5'h1f;
        for (ci = 0; ci < NUM_ENTRIES; ci = ci + 1) begin
            if (lq_valid[ci] && lq_done[ci]) begin
                if (!cdb_found || lq_age[ci] < cdb_min_age) begin
                    cdb_slot = ci[2:0];
                    cdb_min_age = lq_age[ci];
                    cdb_found = 1;
                end
            end
        end
    end

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                lq_valid[i] <= 0;
                lq_base_ready[i] <= 0;
                lq_addr_computed[i] <= 0;
                lq_done[i] <= 0;
            end
            age_counter <= 0;
            cdb_valid <= 0;
            br_resolved <= 0;
        end else begin
            cdb_valid <= 0;
            br_resolved <= 0;

            // CDB snoop: update base values
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (lq_valid[i] && !lq_base_ready[i]) begin
                    if (cdb0_valid && lq_base_tag[i] == cdb0_tag) begin
                        lq_base_val[i] <= cdb0_value;
                        lq_base_ready[i] <= 1;
                    end
                    if (cdb1_valid && lq_base_tag[i] == cdb1_tag) begin
                        lq_base_val[i] <= cdb1_value;
                        lq_base_ready[i] <= 1;
                    end
                end
            end

            // Address computation
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (lq_valid[i] && lq_base_ready[i] && !lq_addr_computed[i]) begin
                    lq_addr[i] <= lq_base_val[i] + lq_imm[i];
                    lq_addr_computed[i] <= 1;
                end
            end

            // Memory read completion: mark done, store loaded data separately
            if (read_found) begin
                if (sq_fwd_valid) begin
                    lq_mem_data[read_slot] <= sq_fwd_data;
                    lq_done[read_slot] <= 1;
                end else begin
                    lq_mem_data[read_slot] <= mem_read_data;
                    lq_done[read_slot] <= 1;
                end
            end

            // CDB output and free entry (respect backpressure)
            if (cdb_found && !cdb_stall) begin
                if (lq_opcode[cdb_slot] == 5'h0d) begin
                    // RETURN only resolves the branch. It restores the PC from mem[r31-8]
                    // and does not write back a register result.
                    cdb_valid <= 0;
                    br_resolved <= 1;
                    br_taken <= 1;
                    br_target <= lq_mem_data[cdb_slot]; // loaded return address
                    br_rob_idx_out <= lq_rob_idx[cdb_slot];
                end else begin
                    // Regular load: broadcast loaded data on CDB
                    cdb_valid <= 1;
                    cdb_tag <= lq_dest_tag[cdb_slot];
                    cdb_value <= lq_mem_data[cdb_slot];
                end
                cdb_rob_idx <= lq_rob_idx[cdb_slot];
                lq_valid[cdb_slot] <= 0;
            end

            // Dispatch
            if (dispatch_en && free_found) begin
                lq_valid[free_slot] <= 1;
                lq_base_val[free_slot] <= dispatch_base_val;
                lq_base_tag[free_slot] <= dispatch_base_tag;
                lq_base_ready[free_slot] <= dispatch_base_ready;
                lq_imm[free_slot] <= dispatch_imm;
                lq_dest_tag[free_slot] <= dispatch_dest_tag;
                lq_rob_idx[free_slot] <= dispatch_rob_idx;
                lq_opcode[free_slot] <= dispatch_opcode;
                lq_addr_computed[free_slot] <= 0;
                lq_done[free_slot] <= 0;
                lq_age[free_slot] <= age_counter;
                age_counter <= age_counter + 1;
            end
        end
    end

endmodule

// ============================================================================
// Task 9: Store Queue (8 entries)
// ============================================================================
module store_queue(
    input clk,
    input rst,

    // Dispatch
    input dispatch_en,
    input [63:0] dispatch_addr_base_val,
    input [6:0] dispatch_addr_base_tag,
    input dispatch_addr_base_ready,
    input [63:0] dispatch_data_val,
    input [6:0] dispatch_data_tag,
    input dispatch_data_ready,
    input [63:0] dispatch_imm,
    input [4:0] dispatch_rob_idx,
    input [4:0] dispatch_opcode,

    // CDB snoop (2 buses)
    input cdb0_valid,
    input [6:0] cdb0_tag,
    input [63:0] cdb0_value,
    input cdb1_valid,
    input [6:0] cdb1_tag,
    input [63:0] cdb1_value,

    // Commit interface
    input commit_en,
    input [4:0] commit_rob_idx,
    output reg mem_write_en,
    output reg [63:0] mem_write_addr,
    output reg [63:0] mem_write_data,

    // Store-to-load forwarding
    input fwd_check_en,
    input [63:0] fwd_check_addr,
    output reg fwd_hit,
    output reg [63:0] fwd_data,

    // ROB notifications
    output reg rob_store_addr_ready,
    output reg rob_store_data_ready,
    output reg [4:0] rob_store_addr_ready_idx,
    output reg [4:0] rob_store_data_ready_idx,
    output reg [63:0] rob_store_addr_value,
    output reg [63:0] rob_store_ready_value,

    // Status
    output full,
    input flush
);

    parameter NUM_ENTRIES = 8;

    reg sq_valid [0:NUM_ENTRIES-1];
    reg [63:0] sq_addr_base_val [0:NUM_ENTRIES-1];
    reg [6:0] sq_addr_base_tag [0:NUM_ENTRIES-1];
    reg sq_addr_base_ready [0:NUM_ENTRIES-1];
    reg [63:0] sq_data_val [0:NUM_ENTRIES-1];
    reg [6:0] sq_data_tag [0:NUM_ENTRIES-1];
    reg sq_data_ready [0:NUM_ENTRIES-1];
    reg [63:0] sq_imm [0:NUM_ENTRIES-1];
    reg [4:0] sq_rob_idx [0:NUM_ENTRIES-1];
    reg [4:0] sq_opcode [0:NUM_ENTRIES-1];
    reg sq_addr_computed [0:NUM_ENTRIES-1];
    reg [63:0] sq_addr [0:NUM_ENTRIES-1];
    reg [4:0] sq_age [0:NUM_ENTRIES-1];

    reg [4:0] age_counter;

    // Full detection
    integer vc;
    reg [3:0] valid_count;
    always @(*) begin
        valid_count = 0;
        for (vc = 0; vc < NUM_ENTRIES; vc = vc + 1)
            if (sq_valid[vc]) valid_count = valid_count + 1;
    end
    assign full = (valid_count == NUM_ENTRIES);

    // Find free slot
    integer fi;
    reg [2:0] free_slot;
    reg free_found;
    always @(*) begin
        free_found = 0;
        free_slot = 0;
        for (fi = 0; fi < NUM_ENTRIES; fi = fi + 1) begin
            if (!sq_valid[fi] && !free_found) begin
                free_slot = fi[2:0];
                free_found = 1;
            end
        end
    end

    // Store-to-load forwarding (combinational)
    // Forward from any live store whose address and data are both known. We prefer the
    // youngest matching entry because it is the value most recently written to that address.
    integer fwd_i;
    always @(*) begin
        fwd_hit = 0;
        fwd_data = 64'd0;
        if (fwd_check_en && !flush) begin
            for (fwd_i = 0; fwd_i < NUM_ENTRIES; fwd_i = fwd_i + 1) begin
                if (sq_valid[fwd_i] && sq_addr_computed[fwd_i] &&
                    sq_data_ready[fwd_i] && sq_addr[fwd_i] == fwd_check_addr) begin
                    fwd_hit = 1;
                    fwd_data = sq_data_val[fwd_i];
                end
            end
        end
    end

    // Commit: find matching entry by rob_idx
    integer cm_i;
    reg [2:0] commit_slot;
    reg commit_found;
    always @(*) begin
        commit_found = 0;
        commit_slot = 0;
        mem_write_en = 0;
        mem_write_addr = 64'd0;
        mem_write_data = 64'd0;
        if (commit_en) begin
            for (cm_i = 0; cm_i < NUM_ENTRIES; cm_i = cm_i + 1) begin
                if (sq_valid[cm_i] && sq_rob_idx[cm_i] == commit_rob_idx && !commit_found) begin
                    commit_slot = cm_i[2:0];
                    commit_found = 1;
                    mem_write_en = 1;
                    mem_write_addr = sq_addr[cm_i];
                    mem_write_data = sq_data_val[cm_i];
                end
            end
        end
    end

    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                sq_valid[i] <= 0;
                sq_addr_base_ready[i] <= 0;
                sq_data_ready[i] <= 0;
                sq_addr_computed[i] <= 0;
            end
            age_counter <= 0;
            rob_store_addr_ready <= 0;
            rob_store_data_ready <= 0;
            rob_store_addr_value <= 64'd0;
            rob_store_ready_value <= 64'd0;
        end else if (flush) begin
            // Preserve existing SQ entries across branch redirects. With only one unresolved
            // branch allowed in flight, younger wrong-path stores are never dispatched here,
            // and CALL's own stack-push must survive the redirect.
            rob_store_addr_ready <= 0;
            rob_store_data_ready <= 0;
            rob_store_addr_value <= 64'd0;
        end else begin
            rob_store_addr_ready <= 0;
            rob_store_data_ready <= 0;
            rob_store_addr_value <= 64'd0;

            // CDB snoop: update addr base and data values
            // Use first-match priority for ROB data notification
            begin : cdb_snoop_block
                reg data_notified;
                data_notified = 0;
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (sq_valid[i]) begin
                        if (!sq_addr_base_ready[i] && cdb0_valid && sq_addr_base_tag[i] == cdb0_tag) begin
                            sq_addr_base_val[i] <= cdb0_value;
                            sq_addr_base_ready[i] <= 1;
                        end
                        if (!sq_addr_base_ready[i] && cdb1_valid && sq_addr_base_tag[i] == cdb1_tag) begin
                            sq_addr_base_val[i] <= cdb1_value;
                            sq_addr_base_ready[i] <= 1;
                        end
                        if (!data_notified && !sq_data_ready[i] && cdb0_valid && sq_data_tag[i] == cdb0_tag) begin
                            sq_data_val[i] <= cdb0_value;
                            sq_data_ready[i] <= 1;
                            rob_store_data_ready <= 1;
                            rob_store_data_ready_idx <= sq_rob_idx[i];
                            rob_store_ready_value <= cdb0_value;
                            data_notified = 1;
                        end
                        if (!data_notified && !sq_data_ready[i] && cdb1_valid && sq_data_tag[i] == cdb1_tag) begin
                            sq_data_val[i] <= cdb1_value;
                            sq_data_ready[i] <= 1;
                            rob_store_data_ready <= 1;
                            rob_store_data_ready_idx <= sq_rob_idx[i];
                            rob_store_ready_value <= cdb1_value;
                            data_notified = 1;
                        end
                    end
                end
            end

            // Address computation - use first-match priority for ROB addr notification
            begin : addr_comp_block
                reg addr_notified;
                addr_notified = 0;
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (sq_valid[i] && sq_addr_base_ready[i] && !sq_addr_computed[i]) begin
                        sq_addr[i] <= sq_addr_base_val[i] + sq_imm[i];
                        sq_addr_computed[i] <= 1;
                        if (!addr_notified) begin
                            rob_store_addr_ready <= 1;
                            rob_store_addr_ready_idx <= sq_rob_idx[i];
                            rob_store_addr_value <= sq_addr_base_val[i] + sq_imm[i];
                            addr_notified = 1;
                        end
                    end
                end
            end

            // Commit: free the matching SQ entry after the write has been driven combinationally.
            if (commit_en && commit_found) begin
                sq_valid[commit_slot] <= 0;
            end

            // Dispatch
            if (dispatch_en && free_found) begin
                sq_valid[free_slot] <= 1;
                sq_addr_base_val[free_slot] <= dispatch_addr_base_val;
                sq_addr_base_tag[free_slot] <= dispatch_addr_base_tag;
                sq_addr_base_ready[free_slot] <= dispatch_addr_base_ready;
                sq_data_val[free_slot] <= dispatch_data_val;
                sq_data_tag[free_slot] <= dispatch_data_tag;
                sq_data_ready[free_slot] <= dispatch_data_ready;
                sq_imm[free_slot] <= dispatch_imm;
                sq_rob_idx[free_slot] <= dispatch_rob_idx;
                sq_opcode[free_slot] <= dispatch_opcode;
                sq_addr_computed[free_slot] <= 0;
                sq_age[free_slot] <= age_counter;
                age_counter <= age_counter + 1;

                // If the store data is already known at dispatch, tell the ROB immediately
                // so a head store doesn't wait forever for a CDB event that will never come.
                if (dispatch_data_ready) begin
                    rob_store_data_ready <= 1;
                    rob_store_data_ready_idx <= dispatch_rob_idx;
                    rob_store_ready_value <= dispatch_data_val;
                end
            end
        end
    end

endmodule

// ============================================================
// Task 10: Reorder Buffer (32 entries)
// ============================================================
module rob(
    input  wire        clk,
    input  wire        rst,

    // Allocate port 1
    input  wire        alloc_en1,
    input  wire [2:0]  alloc_type1,
    input  wire [4:0]  alloc_arch_rd1,
    input  wire [6:0]  alloc_old_phys1,
    input  wire [6:0]  alloc_new_phys1,
    input  wire [63:0] alloc_pc1,
    input  wire        alloc_branch_pred1,
    input  wire [63:0] alloc_branch_target1,
    input  wire [1:0]  alloc_snap_id1,
    output wire [4:0]  alloc_idx1,

    // Allocate port 2
    input  wire        alloc_en2,
    input  wire [2:0]  alloc_type2,
    input  wire [4:0]  alloc_arch_rd2,
    input  wire [6:0]  alloc_old_phys2,
    input  wire [6:0]  alloc_new_phys2,
    input  wire [63:0] alloc_pc2,
    input  wire        alloc_branch_pred2,
    input  wire [63:0] alloc_branch_target2,
    input  wire [1:0]  alloc_snap_id2,
    output wire [4:0]  alloc_idx2,

    // CDB completion bus 0
    input  wire        cdb0_valid,
    input  wire [4:0]  cdb0_rob_idx,
    input  wire [63:0] cdb0_value,

    // CDB completion bus 1
    input  wire        cdb1_valid,
    input  wire [4:0]  cdb1_rob_idx,
    input  wire [63:0] cdb1_value,

    // Store queue notifications
    input  wire        sq_addr_ready,
    input  wire [4:0]  sq_addr_rob_idx,
    input  wire [63:0] sq_addr_val,
    input  wire        sq_data_ready,
    input  wire [4:0]  sq_data_rob_idx,
    input  wire [63:0] sq_data_val,

    // Branch resolution
    input  wire        br_resolved,
    input  wire        br_taken,
    input  wire [63:0] br_target,
    input  wire [4:0]  br_rob_idx,

    // Mispredict outputs
    output reg         mispredict,
    output reg  [63:0] mispredict_target,
    output reg  [4:0]  mispredict_rob_idx,
    output reg  [1:0]  mispredict_snap_id,
    output reg         flush_all,

    // Commit port 1
    output reg         commit_en1,
    output reg  [2:0]  commit_type1,
    output reg  [4:0]  commit_arch_rd1,
    output reg  [6:0]  commit_old_phys1,
    output reg  [6:0]  commit_new_phys1,
    output reg  [4:0]  commit_rob_idx1,
    output reg  [63:0] commit_value1,

    // Commit port 2
    output reg         commit_en2,
    output reg  [2:0]  commit_type2,
    output reg  [4:0]  commit_arch_rd2,
    output reg  [6:0]  commit_old_phys2,
    output reg  [6:0]  commit_new_phys2,
    output reg  [4:0]  commit_rob_idx2,
    output reg  [63:0] commit_value2,

    // Status
    output wire        can_alloc2,
    output wire        has_unresolved_branch,
    output reg         halt_committed
);

    localparam DEPTH = 32;
    // itype constants
    localparam ITYPE_ALU    = 3'd0;
    localparam ITYPE_FPU    = 3'd1;
    localparam ITYPE_LOAD   = 3'd2;
    localparam ITYPE_STORE  = 3'd3;
    localparam ITYPE_BRANCH = 3'd4;
    localparam ITYPE_HALT   = 3'd5;

    // Entry storage
    reg        valid          [0:DEPTH-1];
    reg        complete       [0:DEPTH-1];
    reg [2:0]  itype          [0:DEPTH-1];
    reg [4:0]  arch_rd        [0:DEPTH-1];
    reg [6:0]  old_phys       [0:DEPTH-1];
    reg [6:0]  new_phys       [0:DEPTH-1];
    reg [63:0] pc             [0:DEPTH-1];
    reg        branch_pred    [0:DEPTH-1];
    reg [63:0] branch_target_pred [0:DEPTH-1];
    reg        branch_actual_taken [0:DEPTH-1];
    reg [63:0] branch_actual_target [0:DEPTH-1];
    reg        branch_resolved_flag [0:DEPTH-1];
    reg [63:0] store_addr     [0:DEPTH-1];
    reg [63:0] store_data     [0:DEPTH-1];
    reg        store_addr_rdy [0:DEPTH-1];
    reg        store_data_rdy [0:DEPTH-1];
    reg [63:0] result         [0:DEPTH-1];
    reg [1:0]  snap_id        [0:DEPTH-1];

    reg [4:0] head, tail;
    reg [5:0] count;
    integer ub_i;
    reg unresolved_branch_pending;

    assign alloc_idx1 = tail;
    assign alloc_idx2 = tail + 5'd1;
    assign can_alloc2 = (count <= 6'd30);
    assign has_unresolved_branch = unresolved_branch_pending;
    always @(*) begin
        unresolved_branch_pending = 1'b0;
        for (ub_i = 0; ub_i < DEPTH; ub_i = ub_i + 1) begin
            if (valid[ub_i] && itype[ub_i] == ITYPE_BRANCH && !branch_resolved_flag[ub_i]) begin
                unresolved_branch_pending = 1'b1;
            end
        end
    end

    // Helper: check if index is strictly between head and tail (exclusive)
    // i.e., index is a valid allocated entry after br_rob_idx
    function automatic logic is_after_in_ring(input [4:0] idx, input [4:0] ref_idx, input [4:0] t);
        // Returns 1 if idx is between ref_idx+1 and tail-1 (in circular order)
        logic [4:0] offset_idx;
        logic [4:0] offset_tail;
        offset_idx  = idx - ref_idx - 5'd1;
        offset_tail = t   - ref_idx - 5'd1;
        is_after_in_ring = (offset_idx < offset_tail);
    endfunction

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            mispredict <= 0;
            flush_all <= 0;
            mispredict_target <= 0;
            mispredict_rob_idx <= 0;
            mispredict_snap_id <= 0;
            commit_en1 <= 0;
            commit_en2 <= 0;
            halt_committed <= 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                valid[i] <= 0;
                complete[i] <= 0;
                branch_resolved_flag[i] <= 0;
                store_addr_rdy[i] <= 0;
                store_data_rdy[i] <= 0;
            end
        end else begin
            // Default outputs
            mispredict <= 0;
            flush_all <= 0;
            commit_en1 <= 0;
            commit_en2 <= 0;

            if (halt_committed) begin
                // HALT is terminal: stop allocating/committing further work.
            end else begin
            // Track whether a mispredict fires this cycle (blocking var for alloc guard)
            // Unified count tracking to avoid non-blocking assignment conflicts
            begin : mispredict_guard
                reg this_cycle_flush;
                reg [5:0] commit_count;
                reg [5:0] alloc_count;
                this_cycle_flush = 0;
                commit_count = 0;
                alloc_count = 0;

            // --- CDB completion ---
            if (cdb0_valid && valid[cdb0_rob_idx]) begin
                complete[cdb0_rob_idx] <= 1;
                result[cdb0_rob_idx] <= cdb0_value;
            end
            if (cdb1_valid && valid[cdb1_rob_idx]) begin
                complete[cdb1_rob_idx] <= 1;
                result[cdb1_rob_idx] <= cdb1_value;
            end

            // --- Store queue notifications ---
            if (sq_addr_ready && valid[sq_addr_rob_idx]) begin
                store_addr_rdy[sq_addr_rob_idx] <= 1;
                store_addr[sq_addr_rob_idx] <= sq_addr_val;
            end
            if (sq_data_ready && valid[sq_data_rob_idx]) begin
                store_data_rdy[sq_data_rob_idx] <= 1;
                store_data[sq_data_rob_idx] <= sq_data_val;
            end

            // --- Branch resolution ---
            if (br_resolved && valid[br_rob_idx]) begin
                branch_resolved_flag[br_rob_idx] <= 1;
                branch_actual_taken[br_rob_idx] <= br_taken;
                branch_actual_target[br_rob_idx] <= br_target;
                complete[br_rob_idx] <= 1;

                // Check for mispredict
                if ((branch_pred[br_rob_idx] != br_taken) ||
                    (branch_pred[br_rob_idx] && br_taken &&
                     (branch_target_pred[br_rob_idx] != br_target))) begin
                    mispredict <= 1;
                    mispredict_rob_idx <= br_rob_idx;
                    mispredict_snap_id <= snap_id[br_rob_idx];
                    flush_all <= 1;
                    this_cycle_flush = 1;
                    // Redirect target: if taken, go to actual target; if not taken, pc+4
                    mispredict_target <= br_taken ? br_target : (pc[br_rob_idx] + 64'd4);

                    // Invalidate all entries after the mispredicted branch
                    for (i = 0; i < DEPTH; i = i + 1) begin
                        if (is_after_in_ring(i[4:0], br_rob_idx, tail)) begin
                            valid[i] <= 0;
                            complete[i] <= 0;
                        end
                    end

                    // Update tail and count (use 5-bit subtraction for circular distance)
                    tail <= br_rob_idx + 5'd1;
                    count <= {1'b0, (br_rob_idx - head)} + 6'd1;
                end
            end

            // --- Commit (up to 2/cycle from head) ---
            // Suppress commits when mispredict detected this cycle
            if (!this_cycle_flush) begin
                reg can_commit1;
                reg can_commit2;
                reg [4:0] head2;
                reg is_store1, is_store2;
                reg is_call1, is_call2;

                head2 = head + 5'd1;
                is_store1 = (itype[head] == ITYPE_STORE);
                is_store2 = (itype[head2] == ITYPE_STORE);
                // CALL is encoded as a branch ROB entry with an accompanying SQ entry.
                // Wait for that SQ entry to have both address and data ready before retiring it.
                is_call1 = (itype[head] == ITYPE_BRANCH) &&
                           (store_addr_rdy[head] || store_data_rdy[head]);
                is_call2 = (itype[head2] == ITYPE_BRANCH) &&
                           (store_addr_rdy[head2] || store_data_rdy[head2]);

                can_commit1 = valid[head] && (
                    (complete[head] && (!is_call1 ||
                     (store_addr_rdy[head] && store_data_rdy[head]))) ||
                    (is_store1 && store_addr_rdy[head] && store_data_rdy[head]) ||
                    (itype[head] == ITYPE_HALT)
                );

                if (can_commit1) begin
                    commit_en1 <= 1;
                    commit_type1 <= itype[head];
                    commit_arch_rd1 <= arch_rd[head];
                    commit_old_phys1 <= old_phys[head];
                    commit_new_phys1 <= new_phys[head];
                    commit_rob_idx1 <= head;
                    commit_value1 <= is_store1 ? store_data[head] : result[head];
                    valid[head] <= 0;
                    complete[head] <= 0;
                    store_addr_rdy[head] <= 0;
                    store_data_rdy[head] <= 0;
                    commit_count = commit_count + 6'd1;

                    if (itype[head] == ITYPE_HALT) begin
                        halt_committed <= 1;
                    end

                    // Try second commit
                    can_commit2 = valid[head2] && (count > 6'd1) && (
                        (complete[head2] && (!is_call2 ||
                         (store_addr_rdy[head2] && store_data_rdy[head2]))) ||
                        (is_store2 && store_addr_rdy[head2] && store_data_rdy[head2]) ||
                        (itype[head2] == ITYPE_HALT)
                    );

                    // Only 1 SQ commit per cycle (stores and CALLs both use SQ)
                    if ((is_store1 || is_call1) && (is_store2 || is_call2)) begin
                        can_commit2 = 0;
                    end

                    if (can_commit2) begin
                        commit_en2 <= 1;
                        commit_type2 <= itype[head2];
                        commit_arch_rd2 <= arch_rd[head2];
                        commit_old_phys2 <= old_phys[head2];
                        commit_new_phys2 <= new_phys[head2];
                        commit_rob_idx2 <= head2;
                        commit_value2 <= is_store2 ? store_data[head2] : result[head2];
                        valid[head2] <= 0;
                        complete[head2] <= 0;
                        store_addr_rdy[head2] <= 0;
                        store_data_rdy[head2] <= 0;
                        commit_count = commit_count + 6'd1;

                        if (itype[head2] == ITYPE_HALT) begin
                            halt_committed <= 1;
                        end

                        head <= head + 5'd2;
                    end else begin
                        head <= head + 5'd1;
                    end
                end
            end

            // --- Allocate (after commit to allow same-cycle free/alloc) ---
            // Suppress alloc when mispredict detected this cycle
            if (alloc_en1 && !this_cycle_flush) begin
                valid[tail] <= 1;
                complete[tail] <= 0;
                itype[tail] <= alloc_type1;
                arch_rd[tail] <= alloc_arch_rd1;
                old_phys[tail] <= alloc_old_phys1;
                new_phys[tail] <= alloc_new_phys1;
                pc[tail] <= alloc_pc1;
                branch_pred[tail] <= alloc_branch_pred1;
                branch_target_pred[tail] <= alloc_branch_target1;
                snap_id[tail] <= alloc_snap_id1;
                branch_resolved_flag[tail] <= 0;
                store_addr_rdy[tail] <= 0;
                store_data_rdy[tail] <= 0;
                alloc_count = alloc_count + 6'd1;

                if (alloc_en2) begin
                    valid[tail + 5'd1] <= 1;
                    complete[tail + 5'd1] <= 0;
                    itype[tail + 5'd1] <= alloc_type2;
                    arch_rd[tail + 5'd1] <= alloc_arch_rd2;
                    old_phys[tail + 5'd1] <= alloc_old_phys2;
                    new_phys[tail + 5'd1] <= alloc_new_phys2;
                    pc[tail + 5'd1] <= alloc_pc2;
                    branch_pred[tail + 5'd1] <= alloc_branch_pred2;
                    branch_target_pred[tail + 5'd1] <= alloc_branch_target2;
                    snap_id[tail + 5'd1] <= alloc_snap_id2;
                    branch_resolved_flag[tail + 5'd1] <= 0;
                    store_addr_rdy[tail + 5'd1] <= 0;
                    store_data_rdy[tail + 5'd1] <= 0;
                    alloc_count = alloc_count + 6'd1;

                    tail <= tail + 5'd2;
                end else begin
                    tail <= tail + 5'd1;
                end
            end

            // --- Unified count update (avoids non-blocking assignment conflicts) ---
            // When mispredict fires, count is set directly; commits/allocs are suppressed
            if (!this_cycle_flush) begin
                count <= count - commit_count + alloc_count;
            end
            end // mispredict_guard
            end
        end
    end

endmodule

// ============================================================
// Task 11: Fetch Unit with Branch Predictor
// ============================================================
`ifndef START
`define START 64'h2000
`endif

module fetch_unit(
    input  wire        clk,
    input  wire        rst,

    // Memory interface
    output wire [63:0] fetch_addr,
    input  wire [511:0] fetch_data,  // 16 instructions (512 bits)

    // Decode output port 1
    output wire        out_valid1,
    output wire [31:0] out_instr1,
    output wire [63:0] out_pc1,

    // Decode output port 2
    output wire        out_valid2,
    output wire [31:0] out_instr2,
    output wire [63:0] out_pc2,

    // Backpressure
    input  wire        decode_stall,
    input  wire        consume_two,

    // Flush / redirect
    input  wire        flush,
    input  wire [63:0] redirect_pc
);

    // Fetch buffer: 16-entry circular buffer, each entry = {pc(64), instruction(32)}
    reg [95:0] fbuf [0:15];
    reg [3:0]  fb_head, fb_tail;
    reg [4:0]  fb_count;

    // PC register
    reg [63:0] pc_reg;

    assign fetch_addr = pc_reg;

    // Number of valid entries in fetch buffer
    wire [4:0] fb_free = 5'd16 - fb_count;

    // Output logic: supply up to 2 instructions from buffer head
    wire fb_has1 = (fb_count >= 5'd1);
    wire fb_has2 = (fb_count >= 5'd2);

    assign out_valid1 = fb_has1 && !flush;
    assign out_instr1 = fbuf[fb_head][31:0];
    assign out_pc1    = fbuf[fb_head][95:32];

    wire [3:0] fb_head_plus1 = fb_head + 4'd1;
    assign out_valid2 = fb_has2 && !flush && !decode_stall;
    assign out_instr2 = fbuf[fb_head_plus1][31:0];
    assign out_pc2    = fbuf[fb_head_plus1][95:32];

    // Drain count: how many instructions consumed this cycle
    wire drain1 = out_valid1 && !decode_stall && !flush;
    wire drain2 = out_valid2 && !decode_stall && !flush && consume_two;
    wire [1:0] drain_cnt = {1'b0, drain1} + {1'b0, drain2};

    // Fill: can we fetch this cycle?
    wire can_fetch = !flush && (fb_free >= 5'd4);
    // Number to enqueue: min(fb_free, 16)
    wire [4:0] to_enqueue = can_fetch ? ((fb_free > 5'd16) ? 5'd16 : fb_free) : 5'd0;

    integer j;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_reg <= `START;
            fb_head <= 0;
            fb_tail <= 0;
            fb_count <= 0;
        end else if (flush) begin
            pc_reg <= redirect_pc;
            fb_head <= 0;
            fb_tail <= 0;
            fb_count <= 0;
        end else begin

            // Drain from head
            fb_head <= fb_head + {2'b0, drain_cnt};

            // Fill from memory into buffer
            if (can_fetch) begin
                for (j = 0; j < 16; j = j + 1) begin
                    if (j[4:0] < to_enqueue) begin
                        fbuf[fb_tail + j[3:0]] <= {pc_reg + {58'b0, j[3:0], 2'b0}, fetch_data[j*32 +: 32]};
                    end
                end
                fb_tail <= fb_tail + to_enqueue[3:0];
                pc_reg <= pc_reg + {57'b0, to_enqueue, 2'b0};
            end

            // Single update to fb_count combining drain and fill
            fb_count <= fb_count - {3'b0, drain_cnt} + to_enqueue;
        end
    end

endmodule

// ============================================================
// Task 12: CDB Arbiter (combinational)
// ============================================================
module cdb_arbiter(
    // Producer inputs - ALU pipe 0
    input  wire        alu0_valid,
    input  wire [6:0]  alu0_tag,
    input  wire [63:0] alu0_value,
    input  wire [4:0]  alu0_rob,

    // Producer inputs - FPU pipe 0
    input  wire        fpu0_valid,
    input  wire [6:0]  fpu0_tag,
    input  wire [63:0] fpu0_value,
    input  wire [4:0]  fpu0_rob,

    // Producer inputs - LSU pipe 0
    input  wire        lsu0_valid,
    input  wire [6:0]  lsu0_tag,
    input  wire [63:0] lsu0_value,
    input  wire [4:0]  lsu0_rob,

    // Producer inputs - ALU pipe 1
    input  wire        alu1_valid,
    input  wire [6:0]  alu1_tag,
    input  wire [63:0] alu1_value,
    input  wire [4:0]  alu1_rob,

    // Producer inputs - FPU pipe 1
    input  wire        fpu1_valid,
    input  wire [6:0]  fpu1_tag,
    input  wire [63:0] fpu1_value,
    input  wire [4:0]  fpu1_rob,

    // Producer inputs - LSU pipe 1
    input  wire        lsu1_valid,
    input  wire [6:0]  lsu1_tag,
    input  wire [63:0] lsu1_value,
    input  wire [4:0]  lsu1_rob,

    // CDB bus 0 outputs
    output wire        cdb0_valid,
    output wire [6:0]  cdb0_tag,
    output wire [63:0] cdb0_value,
    output wire [4:0]  cdb0_rob,

    // CDB bus 1 outputs
    output wire        cdb1_valid,
    output wire [6:0]  cdb1_tag,
    output wire [63:0] cdb1_value,
    output wire [4:0]  cdb1_rob,

    // Stall outputs
    output wire        alu0_stall,
    output wire        fpu0_stall,
    output wire        lsu0_stall,
    output wire        alu1_stall,
    output wire        fpu1_stall,
    output wire        lsu1_stall
);

    // Bus 0 priority: alu0 > fpu0 > lsu0
    wire bus0_sel_alu0 = alu0_valid;
    wire bus0_sel_fpu0 = fpu0_valid && !alu0_valid;
    wire bus0_sel_lsu0 = lsu0_valid && !alu0_valid && !fpu0_valid;

    assign cdb0_valid = alu0_valid || fpu0_valid || lsu0_valid;
    assign cdb0_tag   = bus0_sel_alu0 ? alu0_tag   : (bus0_sel_fpu0 ? fpu0_tag   : lsu0_tag);
    assign cdb0_value = bus0_sel_alu0 ? alu0_value : (bus0_sel_fpu0 ? fpu0_value : lsu0_value);
    assign cdb0_rob   = bus0_sel_alu0 ? alu0_rob   : (bus0_sel_fpu0 ? fpu0_rob   : lsu0_rob);

    // Bus 1 priority: alu1 > fpu1 > lsu1
    wire bus1_sel_alu1 = alu1_valid;
    wire bus1_sel_fpu1 = fpu1_valid && !alu1_valid;
    wire bus1_sel_lsu1 = lsu1_valid && !alu1_valid && !fpu1_valid;

    assign cdb1_valid = alu1_valid || fpu1_valid || lsu1_valid;
    assign cdb1_tag   = bus1_sel_alu1 ? alu1_tag   : (bus1_sel_fpu1 ? fpu1_tag   : lsu1_tag);
    assign cdb1_value = bus1_sel_alu1 ? alu1_value : (bus1_sel_fpu1 ? fpu1_value : lsu1_value);
    assign cdb1_rob   = bus1_sel_alu1 ? alu1_rob   : (bus1_sel_fpu1 ? fpu1_rob   : lsu1_rob);

    // Stall signals: producer is valid but didn't get the bus
    assign alu0_stall = 1'b0;  // alu0 always wins bus 0
    assign fpu0_stall = fpu0_valid && alu0_valid;
    assign lsu0_stall = lsu0_valid && (alu0_valid || fpu0_valid);

    assign alu1_stall = 1'b0;  // alu1 always wins bus 1
    assign fpu1_stall = fpu1_valid && alu1_valid;
    assign lsu1_stall = lsu1_valid && (alu1_valid || fpu1_valid);

endmodule

module fpu_class(input [63:0] f, output nan, output infinity, output zero, output subnormal, output normal);
    wire expOnes = &f[62:52];
    wire expZero = ~|f[62:52];
    wire fracZero = ~|f[51:0];
 
    assign nan = expOnes & ~fracZero;
    assign infinity = expOnes & fracZero;
    assign zero = expZero & fracZero;
    assign subnormal = expZero & ~fracZero;
    assign normal = ~expOnes & ~expZero;
endmodule

module fpu_mul(input [63:0] a, input [63:0] b, output reg [63:0] result);
    wire aNan, aInf, aZero, aSubnormal, aNormal;
    wire bNan, bInf, bZero, bSubnormal, bNormal;

    fpu_class classA(.f(a), .nan(aNan), .infinity(aInf), .zero(aZero), .subnormal(aSubnormal), .normal(aNormal));
    fpu_class classB(.f(b), .nan(bNan), .infinity(bInf), .zero(bZero), .subnormal(bSubnormal), .normal(bNormal));

    function [5:0] count_leading_zeros(input [52:0] sig);
        integer i;
        begin : clz_loop
            count_leading_zeros = 0;
            for (i = 52; i >= 0; i = i - 1) begin
                if (sig[i]) disable clz_loop;
                else count_leading_zeros = count_leading_zeros + 1;
            end
        end
    endfunction

    reg signed [12:0] shiftAmount;
    reg guard, round_bit, sticky;
    reg [52:0] sigFinal;
    reg [52:0] sigA;
    reg [52:0] sigB;

    reg [5:0] shift;
    reg signed [12:0] expA, expB;
    reg signed [12:0] expResult;
    reg [105:0] sigResult;
    reg sign;

    always @(*) begin
        if (aNan | bNan) begin
            result = 64'h7ff8000000000000; // propagated NaN
        end else if ((aInf & bZero) | (bInf & aZero)) begin
            result = 64'h7ff8000000000000; // generated NaN (inf*0)
        end else if ((aInf & ~bZero) | (~aZero & bInf)) begin
            result = {a[63] ^ b[63], 11'h7ff, 52'h0};
        end else if (aZero | bZero) begin
            result = {a[63] ^ b[63], 63'h0}; // Zero
        end else begin
            // For normal and subnormal numbers, we would need to implement the actual multiplication logic, which is complex and involves handling the exponent and significand separately. This is a placeholder for the actual multiplication logic.
            result = 64'h0; // Placeholder
            result[63] = a[63] ^ b[63]; // Sign bit

            sigA = {aNormal, a[51:0]};
            sigB = {bNormal, b[51:0]};

            // pre-normalize subnormal numbers
            if (aNormal) begin
                expA = a[62:52] - 1023; // Unbias the exponent
            end else begin
                shift = count_leading_zeros(sigA);
                sigA = sigA << shift; // Normalize the significand
                expA = -1022 - shift; // Adjust exponent for subnormal
            end
            if (bNormal) begin
                expB = b[62:52] - 1023; // Unbias the exponent
            end else begin
                shift = count_leading_zeros(sigB);
                sigB = sigB << shift; // Normalize the significand
                expB = -1022 - shift; // Adjust exponent for subnormal
            end

            expResult = expA + expB + 1023; // Add exponents
            sigResult = sigA * sigB; // Multiply significands

            if (sigResult[105]) begin
                expResult = expResult + 1; // Normalize if the result is too large
                sigResult = sigResult >> 1;
            end

            // Rounding
            // [104] is the leading bit
            // [103: 52] are the fraction bits
            // [51] guard bit, [50] round bit, and [49:0] sticky bits
            sigFinal = sigResult[104:52];

            guard = sigResult[51];
            round_bit = sigResult[50];
            sticky = |sigResult[49:0];
            // 000 to 011 would round down, 101 to 111 would round up, and 100 would round to the nearest even
            if (guard & (round_bit | sigFinal[0] | sticky)) begin
                sigFinal = sigFinal + 1; // Round up
                if (sigFinal == 53'h20000000000000) begin
                    expResult = expResult + 1; // Handle rounding overflow
                    sigFinal = 53'h10000000000000; // Reset to normalized value
                end
            end

            // Handle overflow and underflow
            sign = a[63] ^ b[63];
            if (expResult >= 2047) begin
                result = {sign, 11'h7ff, 52'h0}; // Overflow to Infinity
            end else if (expResult <= 0) begin
                shiftAmount = 1 - expResult; // Calculate how much to shift for subnormal
                if (shiftAmount < 53) begin
                    sigFinal = sigFinal >> shiftAmount; // Shift to create subnormal result
                    result = {sign, 11'h0, sigFinal[51:0]}; // Subnormal result
                end else begin
                    result = {sign, 63'h0}; // Underflow to Zero
                end
            end else begin
                result = {sign, expResult[10:0], sigFinal[51:0]}; // Normalized result
            end
        end
    end
endmodule

module fpu_add(input [63:0] a, input [63:0] b, output reg [63:0] result);
    // Similar to multiplication, we would need to implement the actual addition logic, which involves aligning the exponents and adding the significands. This is a placeholder for the actual addition logic.
    wire aNan, aInf, aZero, aSubnormal, aNormal;
    wire bNan, bInf, bZero, bSubnormal, bNormal;

    fpu_class classA(.f(a), .nan(aNan), .infinity(aInf), .zero(aZero), .subnormal(aSubnormal), .normal(aNormal));
    fpu_class classB(.f(b), .nan(bNan), .infinity(bInf), .zero(bZero), .subnormal(bSubnormal), .normal(bNormal));

    function [5:0] count_leading_zeros(input [55:0] sig);
        integer i;
        begin : clz_loop
            count_leading_zeros = 0;
            for (i = 55; i >= 0; i = i - 1) begin
                if (sig[i]) disable clz_loop;
                else count_leading_zeros = count_leading_zeros + 1;
            end
        end
    endfunction

    reg [52:0] augendSig;
    reg [52:0] addendSig;
    reg signed [12:0] shift;
    reg signed [12:0] expResult;
    reg signed [12:0] expA, expB;
    reg sign;

    reg guard, round_bit, sticky;
    reg [55:0] extAugend;
    reg [55:0] extAddend;
    reg [52:0] sigFinal;

    reg [56:0] sumSig;
    reg [56:0] diffSig;
    reg [12:0] shiftAmount;

    always @(*) begin
        if (aNan | bNan) begin
            result = 64'h7ff8000000000000; // propagated NaN
        end else if ((aInf | bInf)) begin
            if ((aInf & bInf) & (a[63] ^ b[63])) begin
                result = 64'hfff8000000000000; // generated NaN (inf - inf)
            end else begin
                if (aInf & ~bInf) begin
                    result = a;
                end else if (~aInf & bInf) begin
                    result = b;
                end else begin
                    result = a; // both same-sign infinity, return either
                end
            end
        end else if (aZero & bZero) begin
            result = {(a[63] & b[63]), 63'h0}; // Zero, negative zero if both is negative
        end else if (aZero) begin
            result = b;
        end else if (bZero) begin
            result = a;
        end else begin
            expA = aNormal ? a[62:52] : 11'd1; 
            expB = bNormal ? b[62:52] : 11'd1;

            if (expA > expB) begin
                augendSig[52:0] = {aNormal, a[51:0]};
                addendSig[52:0] = {bNormal, b[51:0]};
                sign = a[63];
                expResult = expA;
                shift = expA - expB;
            end else if (expA < expB) begin
                augendSig[52:0] = {bNormal, b[51:0]};
                addendSig[52:0] = {aNormal, a[51:0]};
                sign = b[63];
                expResult = expB;
                shift = expB - expA;
            end else begin
                shift = 0;
                expResult = expA;
                if (a[63] == b[63]) begin
                    sign = a[63];
                    augendSig[52:0] = {aNormal, a[51:0]};
                    addendSig[52:0] = {bNormal, b[51:0]};
                end else begin
                    if (a[51:0] > b[51:0]) begin
                        sign = a[63];
                        augendSig[52:0] = {aNormal, a[51:0]};
                        addendSig[52:0] = {bNormal, b[51:0]};
                    end else if (a[51:0] < b[51:0]) begin
                        sign = b[63];
                        augendSig[52:0] = {bNormal, b[51:0]};
                        addendSig[52:0] = {aNormal, a[51:0]};
                    end else begin
                        sign = 0;
                        augendSig[52:0] = {bNormal, b[51:0]};
                        addendSig[52:0] = {aNormal, a[51:0]};
                    end
                end
            end
            
            extAugend = {augendSig, 3'b0}; // Extend augend significand for potential overflow
            extAddend = {addendSig, 3'b0}; // Extend addend significand for potential overflow
            sticky = shift == 0 ? 0 : |(extAddend << (56 - shift));

            extAddend = extAddend >> shift; // Align addend significand to augend

            if (a[63] == b[63]) begin // addition
                sumSig = extAugend + extAddend; // Add significands

                // Normalize the result
                if (sumSig[56]) begin
                    expResult = expResult + 1; // Normalize if the result is too large
                    sticky = sticky | sumSig[0]; // Update sticky bit with the bit that will be shifted out
                    sumSig = sumSig >> 1;
                end

                // Rounding
                guard = sumSig[2];
                round_bit = sumSig[1];
                sticky = sticky | sumSig[0]; // Update sticky bit with the bit that will be shifted out


                sigFinal = sumSig[55:3]; // The final significand after shifting out the guard, round, and sticky bits
                if (guard & (round_bit | sumSig[3] | sticky)) begin
                    sigFinal = sigFinal + 1;
                    if (sigFinal == 53'h20000000000000) begin
                        expResult = expResult + 1; // Handle rounding overflow
                        sigFinal = 53'h10000000000000; // Reset to normalized value
                    end
                end

                if (expResult >= 2047) begin
                    result = {sign, 11'h7ff, 52'h0}; // Overflow to Infinity
                end else if (expResult < -1074) begin
                    result = {sign, 63'h0}; // Underflow to Zero
                end else if (expResult <= 0) begin
                        shiftAmount = 1 - expResult; // Calculate how much to shift for subnormal
                        if (shiftAmount < 53) begin
                            sigFinal = sigFinal >> shiftAmount; // Shift to create subnormal result
                            result = {sign, 11'h0, sigFinal[51:0]}; // Subnormal result
                        end else begin
                            result = {sign, 63'h0}; // Underflow to Zero
                        end
                end else begin
                    result = {sign, expResult[10:0], sigFinal[51:0]};
                end
            end else begin // subtraction
                diffSig = extAugend - extAddend; // Subtract significands

                if (diffSig == 0) begin
                    result = {sign, 63'h0}; // Result is zero
                end else begin
                    shiftAmount = count_leading_zeros(diffSig[55:0]);
                    
                    if (shiftAmount < expResult) begin
                        expResult = expResult - shiftAmount; // Adjust exponent for normalization
                        diffSig = diffSig << shiftAmount; // Normalize the significand
                    end else begin
                        diffSig = diffSig << (expResult - 1); // Shift to create subnormal result
                        expResult = 0; // Handle the case where the leading bit is just below the guard bit
                    end
                    // Rounding
                    guard = diffSig[2];
                    round_bit = diffSig[1];
                    sticky = sticky | diffSig[0]; // Update sticky bit with the bit that will be shifted out
                    
                    sigFinal = diffSig[55:3]; // The final significand after shifting out the guard, round, and sticky bits
                    if (guard & (round_bit | diffSig[3] | sticky)) begin
                        sigFinal = sigFinal + 1;
                        if (sigFinal == 53'h20000000000000) begin
                            expResult = expResult + 1; // Handle rounding overflow
                            sigFinal = 53'h10000000000000; // Reset to normalized value
                        end
                    end

                    if (expResult < -1074) begin
                        result = {sign, 63'h0};
                    end else begin
                        result = {sign, expResult[10:0], sigFinal[51:0]};
                    end
                end
            end
        end
    end
endmodule

module fpu_div(input [63:0] a, input [63:0] b, output reg [63:0] result);
    wire aNan, aInf, aZero, aSubnormal, aNormal;
    wire bNan, bInf, bZero, bSubnormal, bNormal;

    fpu_class classA(.f(a), .nan(aNan), .infinity(aInf), .zero(aZero), .subnormal(aSubnormal), .normal(aNormal));
    fpu_class classB(.f(b), .nan(bNan), .infinity(bInf), .zero(bZero), .subnormal(bSubnormal), .normal(bNormal));

    function [5:0] count_leading_zeros(input [52:0] sig);
        integer i;
        begin : clz_loop
            count_leading_zeros = 0;
            for (i = 52; i >= 0; i = i - 1) begin
                if (sig[i]) disable clz_loop;
                else count_leading_zeros = count_leading_zeros + 1;
            end
        end
    endfunction

    reg [56:0] q;
    reg[109:0] dividend;
    reg[52:0] divisor;
    reg [109:0] r;
    reg guard, round_bit, sticky;
    reg [52:0] sigFinal;
    reg signed [12:0] shiftAmount;
    reg sign;

    reg signed [12:0] expResult;
    integer i;

    reg signed [12:0] expA, expB;
    reg [52:0] sigA, sigB;
    reg [5:0] shift;

    always @(*) begin

        sign = a[63] ^ b[63];
        if (aNan | bNan) begin
            result = 64'h7ff8000000000000; // propagated NaN
        end else if (aInf & bInf) begin
            result = 64'hfff8000000000000; // generated NaN (inf/inf)
        end else if (aInf) begin
            result = {sign, 11'h7ff, 52'h0}; // inf/anything = inf
        end else if (bZero) begin
            result = 64'h7ff8000000000000; // NaN (num/0, 0/0)
        end else if (aZero) begin
            result = {sign, 63'h0}; // Zero
        end else if (bInf) begin
            result = {sign, 63'h0}; // num/inf = Zero
        end else begin
            // For normal and subnormal numbers, we would need to implement the actual division logic, which is complex and involves handling the exponent and significand separately. This is a placeholder for the actual division logic.
            sigA = {aNormal, a[51:0]};
            sigB = {bNormal, b[51:0]};

            if (aNormal) begin
                expA = a[62:52] - 1023;
            end else begin
                shift = count_leading_zeros(sigA);
                sigA = sigA << shift;
                expA = -1022 - shift;
            end
            if (bNormal) begin
                expB = b[62:52] - 1023;
            end else begin
                shift = count_leading_zeros(sigB);
                sigB = sigB << shift;
                expB = -1022 - shift;
            end

            expResult = expA - expB + 1023;

            divisor = sigB;
            q = 0;
            r = {57'b0, sigA};

            // Initial quotient bit (integer part of sigA/sigB)
            if (r >= {57'b0, divisor}) begin
                r = r - {57'b0, divisor};
                q[0] = 1'b1;
            end

            // Generate 56 fractional quotient bits
            for (i = 0; i < 56; i = i + 1) begin
                r = r << 1;
                q = q << 1;
                if (r >= {57'b0, divisor}) begin
                    r = r - {57'b0, divisor};
                    q[0] = 1'b1;
                end
            end

            // Normalize so q[55] is the leading 1
            if (q[56]) begin
                sticky = q[0] | (r != 0);
                q = q >> 1;
            end else begin
                expResult = expResult - 1;
                sticky = (r != 0);
            end

            // Rounding (round to nearest even)
            guard = q[2];
            round_bit = q[1];
            sticky = sticky | q[0];

            sigFinal = q[55:3];
            if (guard & (round_bit | sigFinal[0] | sticky)) begin
                sigFinal = sigFinal + 1;
                if (sigFinal == 53'h20000000000000) begin
                    expResult = expResult + 1;
                    sigFinal = 53'h10000000000000;
                end
            end

            if (expResult >= 2047) begin
                result = {sign, 11'h7ff, 52'h0};
            end else if (expResult < -1074) begin
                result = {sign, 63'h0};
            end else if (expResult <= 0) begin
                shiftAmount = 1 - expResult; // Calculate how much to shift for subnormal
                if (shiftAmount < 53) begin
                    sigFinal = sigFinal >> shiftAmount; // Shift to create subnormal result
                    result = {sign, 11'h0, sigFinal[51:0]}; // Subnormal result
                end else begin
                    result = {sign, 63'h0}; // Underflow to Zero
                end
            end else begin
                result = {sign, expResult[10:0], sigFinal[51:0]};
            end
        end
    end
endmodule


module alu(
    input [4:0] opcode,
    input [63:0] PC,
    input [63:0] rd_data,
    input [63:0] rs_data,
    input [63:0] rt_data,
    input [63:0] r31_data,
    input [11:0] L_data,
    output reg [63:0] result,
    output reg writeback,
    output reg [63:0] branch_target,
    output reg branch_taken
);
// control signal:
// use register or L bit for operation
    wire [63:0] extended_L;
    assign extended_L = {{52{L_data[11]}}, L_data};

    wire [63:0] fpu_add_result;
    wire [63:0] fpu_sub_result;
    wire [63:0] fpu_mul_result;
    wire [63:0] fpu_div_result;

    fpu_add fpu_add_unit(
        .a(rs_data),
        .b(rt_data),
        .result(fpu_add_result)
    );

    fpu_mul fpu_mul_unit(
        .a(rs_data),
        .b(rt_data),
        .result(fpu_mul_result)
    );

    fpu_div fpu_div_unit(
        .a(rs_data),
        .b(rt_data),
        .result(fpu_div_result)
    );

    wire [63:0] negated;
    assign negated = {~rt_data[63], rt_data[62:0]};
    fpu_add fpu_sub_unit(
        .a(rs_data),
        .b(negated),
        .result(fpu_sub_result)
    );

    always @(*) begin
        result = 64'b0;
        writeback = 1'b1;
        branch_target = PC + 64'd4;
        branch_taken = 1'b0;
        case (opcode)
            5'h18: result = rs_data + rt_data; // ADD
            5'h19: result = rd_data + extended_L; // ADDI
            5'h1a: result = rs_data - rt_data; // SUB
            5'h1b: result = rd_data - extended_L; // SUBI
            5'h1c: result = rs_data * rt_data; // MUL
            5'h1d: result = rs_data / rt_data; // DIV

            5'h00: result = rs_data & rt_data; // AND
            5'h01: result = rs_data | rt_data; // OR
            5'h02: result = rs_data ^ rt_data; // XOR
            5'h03: result = ~rs_data; // NOT

            5'h04: result = rs_data >> rt_data; // SHFTR
            5'h05: result = rd_data >> extended_L; // SHFTRI
            5'h06: result = rs_data << rt_data; // SHFTL
            5'h07: result = rd_data << extended_L; // SHFTLI

            5'h08: begin // br rd
                writeback = 1'b0;
                branch_target = rd_data;
                branch_taken = 1'b1;
            end
            5'h09: begin // brr rd
                writeback = 1'b0;
                branch_target = rd_data + PC;
                branch_taken = 1'b1;
            end
            5'h0a: begin // brr L
                writeback = 1'b0;
                branch_target = extended_L + PC;
                branch_taken = 1'b1;
            end

            5'h0b: begin  // brnz rd, rs
                writeback = 1'b0;
                branch_target = rd_data;
                if (rs_data != 64'b0) begin
                    branch_taken = 1'b1;
                end
            end
            5'h0c: begin // call
                writeback = 1'b0;
                branch_target = rd_data;
                branch_taken = 1'b1;
            end
            5'h0d: begin // return
                writeback = 1'b0;
                branch_target = r31_data - 64'd8; // address of saved PC on stack
                branch_taken = 1'b1;
            end
            5'h0e: begin // brgt rd, rs, rt
                writeback = 1'b0;
                branch_target = rd_data;
                if (rs_data > rt_data) begin
                    branch_taken = 1'b1;
                end
            end

            // mov operations
            5'h10: result = rs_data + extended_L; // mov rd, (rs)(L)
            5'h11: result = rs_data; // mov rd, rs
            5'h12: result = {rd_data[63:12], extended_L[11:0]}; // MOVI: set low 12 bits to L
            5'h13: begin
                writeback = 1'b0;
                result = rd_data + extended_L; // mov (rd)(L), rs
            end
            
            // FPU operations in another file: fpu.sv
            5'h14: result = fpu_add_result; // FADD
            5'h15: result = fpu_sub_result; // FSUB
            5'h16: result = fpu_mul_result; // FMUL
            5'h17: result = fpu_div_result; // FDIV
            default: begin
                writeback = 1'b0;
                result = 64'b0;
            end
        endcase
    end
endmodule
