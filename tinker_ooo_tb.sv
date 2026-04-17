`include "tinker.sv"

// Comprehensive OOO pipeline tests for tinker_core.
module tinker_ooo_tb;
    reg clk, reset;
    wire hlt;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    integer pass_count, fail_count;

    // Helper to build an instruction word: [opcode:5 | rd:5 | rs:5 | rt:5 | L:12]
    function [31:0] mk_instr(input [4:0] op, input [4:0] rd,
                             input [4:0] rs, input [4:0] rt, input [11:0] L);
        mk_instr = {op, rd, rs, rt, L};
    endfunction

    task store_instr(input [63:0] addr, input [31:0] word);
        begin
            dut.mem_inst.bytes[addr + 0] = word[7:0];
            dut.mem_inst.bytes[addr + 1] = word[15:8];
            dut.mem_inst.bytes[addr + 2] = word[23:16];
            dut.mem_inst.bytes[addr + 3] = word[31:24];
        end
    endtask

    task check_reg(input [4:0] reg_num, input [63:0] expected, input string test_name);
        begin
            if (dut.arf_inst.registers[reg_num] === expected) begin
                $display("  PASS: r%0d = %0d (expected %0d) [%s]",
                         reg_num, dut.arf_inst.registers[reg_num], expected, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: r%0d = %0d (expected %0d) [%s]",
                         reg_num, dut.arf_inst.registers[reg_num], expected, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Clear instruction memory region
    task clear_mem;
        integer i;
        begin
            for (i = 'h2000; i < 'h2040; i = i + 1)
                dut.mem_inst.bytes[i] = 8'h0;
        end
    endtask

    // Apply reset and wait
    task do_reset;
        begin
            reset = 1;
            #2;
        end
    endtask

    task release_and_run(input integer cycles);
        begin
            #8 reset = 0;
            repeat (cycles) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("tinker_ooo_tb.vcd");
        $dumpvars(0, tinker_ooo_tb);

        clk = 0;
        pass_count = 0;
        fail_count = 0;

        // ============================================================
        // Test 1: Independent instructions (ILP exploitation)
        // ============================================================
        $display("\n=== Test 1: Independent ADDI instructions ===");
        do_reset;
        clear_mem;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd1));   // addi r1, #1
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd2));   // addi r2, #2
        store_instr(64'h2008, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd3));   // addi r3, #3
        store_instr(64'h200c, mk_instr(5'h19, 5'd4, 5'd0, 5'd0, 12'd4));   // addi r4, #4
        store_instr(64'h2010, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        release_and_run(300);

        check_reg(1, 64'd1, "indep addi r1");
        check_reg(2, 64'd2, "indep addi r2");
        check_reg(3, 64'd3, "indep addi r3");
        check_reg(4, 64'd4, "indep addi r4");
        if (hlt !== 1'b1) begin
            $display("  FAIL: hlt not asserted"); fail_count = fail_count + 1;
        end else begin
            $display("  PASS: hlt asserted"); pass_count = pass_count + 1;
        end

        // ============================================================
        // Test 2: Data dependency chain (RAW hazards)
        // ============================================================
        $display("\n=== Test 2: Data dependency chain ===");
        do_reset;
        clear_mem;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd5));   // addi r1, #5  -> r1=5
        store_instr(64'h2004, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd3));   // addi r1, #3  -> r1=8
        store_instr(64'h2008, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd2));   // addi r1, #2  -> r1=10
        store_instr(64'h200c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        release_and_run(300);

        check_reg(1, 64'd10, "dep chain r1");

        // ============================================================
        // Test 3: Register-to-register ADD
        // ============================================================
        $display("\n=== Test 3: Register-to-register ADD ===");
        do_reset;
        clear_mem;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd10));  // addi r1, #10
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd20));  // addi r2, #20
        store_instr(64'h2008, mk_instr(5'h18, 5'd3, 5'd1, 5'd2, 12'd0));   // add r3, r1, r2
        store_instr(64'h200c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        release_and_run(300);

        check_reg(1, 64'd10, "add r1");
        check_reg(2, 64'd20, "add r2");
        check_reg(3, 64'd30, "add r3=r1+r2");

        // ============================================================
        // Test 4: Store and Load
        // ============================================================
        $display("\n=== Test 4: Store and Load ===");
        do_reset;
        clear_mem;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd100)); // addi r1, #100
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd42));  // addi r2, #42
        store_instr(64'h2008, mk_instr(5'h13, 5'd1, 5'd2, 5'd0, 12'd0));   // store (r1)(0), r2
        store_instr(64'h200c, mk_instr(5'h10, 5'd3, 5'd1, 5'd0, 12'd0));   // load r3, (r1)(0)
        store_instr(64'h2010, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        release_and_run(400);

        check_reg(1, 64'd100, "st/ld r1");
        check_reg(2, 64'd42,  "st/ld r2");
        check_reg(3, 64'd42,  "st/ld r3=mem[100]");

        // ============================================================
        // Summary
        // ============================================================
        $display("\n=== Summary ===");
        $display("PASSED: %0d / %0d", pass_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TESTS FAILED", fail_count);

        $finish;
    end
endmodule
