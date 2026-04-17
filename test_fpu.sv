`include "tinker.sv"

module test_fpu;
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

        // Pre-load r1 = 1.0 (double), r2 = 2.0 (double)
        dut.reg_file.registers[1] = $realtobits(1.0);
        dut.reg_file.registers[2] = $realtobits(2.0);

        // addf r3, r1, r2  (opcode 0x14)
        store_instr(64'h2000, mk_instr(5'h14, 5'd3, 5'd1, 5'd2, 12'd0));
        // halt
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 300) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        $display("Cycles: %0d", cycle_count);
        $display("r3 = %f (expect 3.0)", $bitstoreal(dut.reg_file.registers[3]));
        if (cycle_count < 300)
            $display("PASS (no timeout)");
        else
            $display("FAIL (timeout)");

        $finish;
    end
endmodule
