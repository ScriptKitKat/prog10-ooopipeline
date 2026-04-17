`include "tinker.sv"

module debug_ooo_hang;
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

    integer i;

    initial begin
        clk = 0;
        reset = 1; #2;
        for (i = 0; i < 'h60; i = i + 1) dut.memory.bytes[i] = 8'h0;
        for (i = 'h2000; i < 'h2080; i = i + 1) dut.memory.bytes[i] = 8'h0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd1));
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        #8 reset = 0;
        repeat (20) @(posedge clk);
        $display("r1=%0d hlt=%b", dut.reg_file.registers[1], hlt);
        $finish;
    end
endmodule
