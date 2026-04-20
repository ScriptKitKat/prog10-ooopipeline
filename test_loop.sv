`include "tinker.sv"

module test_loop;
    reg clk, reset;
    wire hlt;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

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

    integer cycle_count;

    initial begin
        clk = 0;

        // === Test 1: Simple loop using BRNZ (10 iterations) ===
        // r1 = 10 (counter), r2 = loop target address
        // loop: subi r1, 1
        //       brnz r2, r1   (branch to loop if r1 != 0)
        //       halt
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd10;
        dut.reg_file.registers[2] = 64'h2000;  // loop target
        store_instr(64'h2000, mk_instr(5'h1b, 5'd1, 5'd0, 5'd0, 12'd1));   // subi r1, 1
        store_instr(64'h2004, mk_instr(5'h0b, 5'd2, 5'd1, 5'd0, 12'd0));   // brnz r2, r1
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 2000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        $display("Loop BRNZ (10 iter): cycles=%0d r1=%0d %s",
                 cycle_count, dut.reg_file.registers[1],
                 (cycle_count < 2000 && dut.reg_file.registers[1] === 64'd0) ? "PASS" : "FAIL");

        // === Test 2: Loop using BRR_L (backward branch with immediate) ===
        // This is a tighter loop using PC-relative backward branch
        // r1 = 10 (counter)
        // 0x2000: subi r1, 1
        // 0x2004: brnz r3, r1   (branch to 0x200c if r1 != 0)
        // 0x2008: halt
        // 0x200c: brr_L -12     (jump back to 0x2000: PC + (-12) = 0x200c + (-12) = 0x2000)
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd10;
        dut.reg_file.registers[3] = 64'h200c;  // target for brnz -> go to brr_L
        store_instr(64'h2000, mk_instr(5'h1b, 5'd1, 5'd0, 5'd0, 12'd1));              // subi r1, 1
        store_instr(64'h2004, mk_instr(5'h0b, 5'd3, 5'd1, 5'd0, 12'd0));              // brnz r3, r1
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));              // halt
        store_instr(64'h200c, mk_instr(5'h0a, 5'd0, 5'd0, 5'd0, 12'hFF4));            // brr_L -12
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 2000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        $display("Loop BRR_L (10 iter): cycles=%0d r1=%0d %s",
                 cycle_count, dut.reg_file.registers[1],
                 (cycle_count < 2000 && dut.reg_file.registers[1] === 64'd0) ? "PASS" : "FAIL");

        // === Test 3: Larger loop (100 iterations) - likely to timeout on grader ===
        reset = 1; #2;
        dut.reg_file.registers[1] = 64'd100;
        dut.reg_file.registers[2] = 64'h2000;
        store_instr(64'h2000, mk_instr(5'h1b, 5'd1, 5'd0, 5'd0, 12'd1));   // subi r1, 1
        store_instr(64'h2004, mk_instr(5'h0b, 5'd2, 5'd1, 5'd0, 12'd0));   // brnz r2, r1
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));   // halt
        #8 reset = 0;
        cycle_count = 0;
        while (!hlt && cycle_count < 50000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        $display("Loop BRNZ (100 iter): cycles=%0d r1=%0d %s (%.1f cycles/iter)",
                 cycle_count, dut.reg_file.registers[1],
                 (cycle_count < 50000 && dut.reg_file.registers[1] === 64'd0) ? "PASS" : "FAIL",
                 cycle_count / 100.0);

        $finish;
    end
endmodule
