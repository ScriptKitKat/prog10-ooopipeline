`include "tinker.sv"

// Test: addi r1, #5 then halt. No register pre-loading.
// This is what the autograder likely does.
module test_addi_simple;
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
        // Only instructions, no register pre-loading
        // addi r1, #5 (opcode 0x19): rd=1, rs=0, rt=0, L=5
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd5));
        // halt
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 200) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        $display("Cycles: %0d", cycle_count);
        $display("r1 = %0d (expect 5)", dut.reg_file.registers[1]);
        if (dut.reg_file.registers[1] === 64'd5)
            $display("PASS addi");
        else
            $display("FAIL addi: r1 = %0d", dut.reg_file.registers[1]);

        $finish;
    end
endmodule
