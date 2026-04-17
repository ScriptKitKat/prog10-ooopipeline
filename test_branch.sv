`include "tinker.sv"

module test_branch;
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
        clk = 0; reset = 1;
        #2;

        // BRR L: branch to PC + L (opcode 0x0a)
        // At 0x2000: brr_L +8 -> should jump to 0x200c (0x2000+4+8=0x200c? or 0x2000+8=0x2008?)
        // brr_L: target = imm + PC
        // Let's jump to 0x2008: offset from PC (0x2000) = 8
        store_instr(64'h2000, mk_instr(5'h0a, 5'd0, 5'd0, 5'd0, 12'd8));
        // 0x2004: this should be skipped by branch... but wait, brr_L jumps to PC+imm = 0x2000+8 = 0x2008
        store_instr(64'h2004, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd99));  // addi r1, #99 (should be skipped)
        // 0x2008: halt
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 300) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        $display("Cycles: %0d", cycle_count);
        $display("r1 = %0d (expect 0 - branch should skip addi)", dut.reg_file.registers[1]);
        if (cycle_count < 300 && dut.reg_file.registers[1] === 64'd0)
            $display("PASS branch");
        else begin
            $display("FAIL branch");
            if (cycle_count >= 300) $display("  TIMEOUT");
        end

        $finish;
    end
endmodule
