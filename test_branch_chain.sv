`include "tinker.sv"

module test_branch_chain;
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
    localparam LOOP_COUNT = 5;  // small count for quick test

    // Memory layout:
    // 0x2000: movi r21, LOOP_COUNT
    // 0x2004: subi r21, 1          (:loop)
    // 0x2008: brnz r20, r21        (branch to :b1 if r21 != 0)
    // 0x200C: halt
    // 0x2010: br r22               (:b1)
    // 0x2014: br r23               (:b2)
    // 0x2018: br r24               (:b3)
    // 0x201C: br r25               (:b4)
    // 0x2020: br r26               (:b5)

    initial begin
        clk = 0; reset = 1;
        #2;

        // Pre-load all registers (simulating what ld/mov instructions would do)
        dut.reg_file.registers[20] = 64'h200C;  // :b1
        dut.reg_file.registers[21] = LOOP_COUNT; // loop counter
        dut.reg_file.registers[22] = 64'h2010;  // :b2
        dut.reg_file.registers[23] = 64'h2014;  // :b3
        dut.reg_file.registers[24] = 64'h2018;  // :b4
        dut.reg_file.registers[25] = 64'h201C;  // :b5
        dut.reg_file.registers[26] = 64'h2000;  // :loop

        // :loop - subi r21, 1 (opcode 0x1b)
        store_instr(64'h2000, mk_instr(5'h1b, 5'd21, 5'd0, 5'd0, 12'd1));

        // brnz r20, r21 (opcode 0x0b, rd=r20=target, rs=r21=condition)
        store_instr(64'h2004, mk_instr(5'h0b, 5'd20, 5'd21, 5'd0, 12'd0));

        // halt (opcode 0x0f)
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        // :b1 - br r22 (opcode 0x08)
        store_instr(64'h200C, mk_instr(5'h08, 5'd22, 5'd0, 5'd0, 12'd0));

        // :b2 - br r23
        store_instr(64'h2010, mk_instr(5'h08, 5'd23, 5'd0, 5'd0, 12'd0));

        // :b3 - br r24
        store_instr(64'h2014, mk_instr(5'h08, 5'd24, 5'd0, 5'd0, 12'd0));

        // :b4 - br r25
        store_instr(64'h2018, mk_instr(5'h08, 5'd25, 5'd0, 5'd0, 12'd0));

        // :b5 - br r26
        store_instr(64'h201C, mk_instr(5'h08, 5'd26, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 5000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        $display("Branch chain test:");
        $display("  Cycles: %0d", cycle_count);
        $display("  r21 = %0d (expect 0)", dut.reg_file.registers[21]);

        if (cycle_count < 5000 && dut.reg_file.registers[21] === 64'd0)
            $display("  PASS");
        else begin
            $display("  FAIL");
            if (cycle_count >= 5000) $display("  TIMEOUT");
        end

        $finish;
    end
endmodule
