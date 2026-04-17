`include "tinker.sv"

module test_store;
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

        // Pre-load: r1 = 42, r2 = 0x3000 (address to store to)
        dut.reg_file.registers[1] = 64'd42;
        dut.reg_file.registers[2] = 64'h3000;

        // mov [rd+L], rs  (opcode 0x13 = store)
        // store: addr = rd + L, data = rs
        // So: store r2, r1, L=0 means mem[r2+0] = r1 = 42
        store_instr(64'h2000, mk_instr(5'h13, 5'd2, 5'd1, 5'd0, 12'd0));
        // halt
        store_instr(64'h2004, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0));

        #8 reset = 0;

        cycle_count = 0;
        while (!hlt && cycle_count < 300) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        // Check memory at 0x3000
        $display("Cycles: %0d", cycle_count);
        $display("mem[0x3000] = %0d (expect 42)",
            {dut.memory.bytes[64'h3007], dut.memory.bytes[64'h3006],
             dut.memory.bytes[64'h3005], dut.memory.bytes[64'h3004],
             dut.memory.bytes[64'h3003], dut.memory.bytes[64'h3002],
             dut.memory.bytes[64'h3001], dut.memory.bytes[64'h3000]});
        if (cycle_count < 300)
            $display("PASS (no timeout)");
        else
            $display("FAIL (timeout)");

        $finish;
    end
endmodule
