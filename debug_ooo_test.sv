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
            dut.memory.bytes[addr + 0] = word[7:0];
            dut.memory.bytes[addr + 1] = word[15:8];
            dut.memory.bytes[addr + 2] = word[23:16];
            dut.memory.bytes[addr + 3] = word[31:24];
        end
    endtask

    task check_reg(input [4:0] reg_num, input [63:0] expected, input string test_name);
        begin
            if (dut.reg_file.registers[reg_num] === expected) begin
                $display("  PASS: r%0d = %0d (expected %0d) [%s]",
                         reg_num, dut.reg_file.registers[reg_num], expected, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: r%0d = %0d (expected %0d) [%s]",
                         reg_num, dut.reg_file.registers[reg_num], expected, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Store a 64-bit value in memory (little-endian)
    task store_qword(input [63:0] addr, input [63:0] val);
        begin
            dut.memory.bytes[addr + 0] = val[7:0];
            dut.memory.bytes[addr + 1] = val[15:8];
            dut.memory.bytes[addr + 2] = val[23:16];
            dut.memory.bytes[addr + 3] = val[31:24];
            dut.memory.bytes[addr + 4] = val[39:32];
            dut.memory.bytes[addr + 5] = val[47:40];
            dut.memory.bytes[addr + 6] = val[55:48];
            dut.memory.bytes[addr + 7] = val[63:56];
        end
    endtask

    integer i;

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
        reset = 1; #2;
        for (i = 0; i < 'h60; i = i + 1) dut.memory.bytes[i] = 8'h0;
        for (i = 'h2000; i < 'h2080; i = i + 1) dut.memory.bytes[i] = 8'h0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd1));   // addi r1, #1
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd2));   // addi r2, #2
        store_instr(64'h2008, mk_instr(5'h19, 5'd3, 5'd0, 5'd0, 12'd3));   // addi r3, #3
        store_instr(64'h200c, mk_instr(5'h19, 5'd4, 5'd0, 5'd0, 12'd4));   // addi r4, #4
        store_instr(64'h2010, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        #8 reset = 0;
        repeat (20) @(posedge clk);

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
        reset = 1; #2;
        for (i = 0; i < 'h60; i = i + 1) dut.memory.bytes[i] = 8'h0;
        for (i = 'h2000; i < 'h2080; i = i + 1) dut.memory.bytes[i] = 8'h0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd5));   // addi r1, #5  -> r1=5
        store_instr(64'h2004, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd3));   // addi r1, #3  -> r1=8
        store_instr(64'h2008, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd2));   // addi r1, #2  -> r1=10
        store_instr(64'h200c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        #8 reset = 0;
        repeat (300) @(posedge clk);

        check_reg(1, 64'd10, "dep chain r1");

        // ============================================================
        // Test 3: Register-to-register ADD
        // ============================================================
        $display("\n=== Test 3: Register-to-register ADD ===");
        reset = 1; #2;
        for (i = 0; i < 'h60; i = i + 1) dut.memory.bytes[i] = 8'h0;
        for (i = 'h2000; i < 'h2080; i = i + 1) dut.memory.bytes[i] = 8'h0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd10));  // addi r1, #10
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd20));  // addi r2, #20
        store_instr(64'h2008, mk_instr(5'h18, 5'd3, 5'd1, 5'd2, 12'd0));   // add r3, r1, r2
        store_instr(64'h200c, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        #8 reset = 0;
        repeat (300) @(posedge clk);

        check_reg(1, 64'd10, "add r1");
        check_reg(2, 64'd20, "add r2");
        check_reg(3, 64'd30, "add r3=r1+r2");

        // ============================================================
        // Test 4: Store and Load
        // ============================================================
        $display("\n=== Test 4: Store and Load ===");
        reset = 1; #2;
        for (i = 0; i < 'h60; i = i + 1) dut.memory.bytes[i] = 8'h0;
        for (i = 'h2000; i < 'h2080; i = i + 1) dut.memory.bytes[i] = 8'h0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd100)); // addi r1, #100
        store_instr(64'h2004, mk_instr(5'h19, 5'd2, 5'd0, 5'd0, 12'd42));  // addi r2, #42
        store_instr(64'h2008, mk_instr(5'h13, 5'd1, 5'd2, 5'd0, 12'd0));   // store (r1)(0), r2
        store_instr(64'h200c, mk_instr(5'h10, 5'd3, 5'd1, 5'd0, 12'd0));   // load r3, (r1)(0)
        store_instr(64'h2010, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        #8 reset = 0;
        repeat (400) @(posedge clk);

        check_reg(1, 64'd100, "st/ld r1");
        check_reg(2, 64'd42,  "st/ld r2");
        check_reg(3, 64'd42,  "st/ld r3=mem[100]");

        // ============================================================
        // Test 5: Branch chain loop (tests branch prediction)
        // ============================================================
        $display("\n=== Test 5: Branch chain loop ===");
        reset = 1; #2;
        for (i = 0; i < 'h60; i = i + 1) dut.memory.bytes[i] = 8'h0;
        for (i = 'h2000; i < 'h2080; i = i + 1) dut.memory.bytes[i] = 8'h0;

        // Data section: store 64-bit addresses at low memory
        store_qword(64'h00, 64'h2028);  // addr of b1  -> loaded into r20
        store_qword(64'h08, 64'h202C);  // addr of b2  -> loaded into r22
        store_qword(64'h10, 64'h2030);  // addr of b3  -> loaded into r23
        store_qword(64'h18, 64'h2034);  // addr of b4  -> loaded into r24
        store_qword(64'h20, 64'h2038);  // addr of b5  -> loaded into r25
        store_qword(64'h28, 64'h201C);  // addr of loop -> loaded into r26
        store_qword(64'h30, 64'd5);     // counter = 5  -> loaded into r21

        // Code section at 0x2000
        store_instr(64'h2000, mk_instr(5'h10, 5'd20, 5'd0, 5'd0, 12'd0));  // load r20, (r0)(0)
        store_instr(64'h2004, mk_instr(5'h10, 5'd22, 5'd0, 5'd0, 12'd8));  // load r22, (r0)(8)
        store_instr(64'h2008, mk_instr(5'h10, 5'd23, 5'd0, 5'd0, 12'd16)); // load r23, (r0)(16)
        store_instr(64'h200C, mk_instr(5'h10, 5'd24, 5'd0, 5'd0, 12'd24)); // load r24, (r0)(24)
        store_instr(64'h2010, mk_instr(5'h10, 5'd25, 5'd0, 5'd0, 12'd32)); // load r25, (r0)(32)
        store_instr(64'h2014, mk_instr(5'h10, 5'd26, 5'd0, 5'd0, 12'd40)); // load r26, (r0)(40)
        store_instr(64'h2018, mk_instr(5'h10, 5'd21, 5'd0, 5'd0, 12'd48)); // load r21, (r0)(48)
        // :loop (0x201C): subi r21, 1
        store_instr(64'h201C, mk_instr(5'h1b, 5'd21, 5'd0, 5'd0, 12'd1));
        // brnz r20, r21
        store_instr(64'h2020, mk_instr(5'h0b, 5'd20, 5'd21, 5'd0, 12'd0));
        // halt
        store_instr(64'h2024, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        // :b1 (0x2028): br r22
        store_instr(64'h2028, mk_instr(5'h08, 5'd22, 5'd0, 5'd0, 12'd0));
        // :b2 (0x202C): br r23
        store_instr(64'h202C, mk_instr(5'h08, 5'd23, 5'd0, 5'd0, 12'd0));
        // :b3 (0x2030): br r24
        store_instr(64'h2030, mk_instr(5'h08, 5'd24, 5'd0, 5'd0, 12'd0));
        // :b4 (0x2034): br r25
        store_instr(64'h2034, mk_instr(5'h08, 5'd25, 5'd0, 5'd0, 12'd0));
        // :b5 (0x2038): br r26
        store_instr(64'h2038, mk_instr(5'h08, 5'd26, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;
        repeat (500) @(posedge clk);

        check_reg(21, 64'd0, "branch loop r21 final=0");
        if (hlt !== 1'b1) begin
            $display("  FAIL: hlt not asserted"); fail_count = fail_count + 1;
        end else begin
            $display("  PASS: hlt asserted"); pass_count = pass_count + 1;
        end

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
