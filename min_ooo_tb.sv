`include "tinker.sv"

module min_ooo_tb;
    reg clk, reset;
    wire hlt;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    integer pass_count, fail_count;

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
        pass_count = 0;
        fail_count = 0;

        // Exact same program as smoke test, with clear_mem
        reset = 1; #2;
        // Test: clear exactly 64 bytes (the fetch window)
        for (i = 'h2000; i < 'h2040; i = i + 1) dut.memory.bytes[i] = 8'h0;
        store_instr(64'h2000, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd5));
        store_instr(64'h2004, mk_instr(5'h19, 5'd1, 5'd0, 5'd0, 12'd3));
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));
        #8 reset = 0;
        repeat (200) @(posedge clk);

        $display("r1 = %0d (expect 8)", dut.reg_file.registers[1]);
        $display("hlt = %b (expect 1)", hlt);
        if (dut.reg_file.registers[1] === 64'd8 && hlt === 1'b1)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end
endmodule
