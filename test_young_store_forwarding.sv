`include "tinker.sv"

module test_young_store_forwarding;
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

    task store_mem64(input [63:0] addr, input [63:0] data);
        begin
            dut.memory.bytes[addr + 0] = data[7:0];
            dut.memory.bytes[addr + 1] = data[15:8];
            dut.memory.bytes[addr + 2] = data[23:16];
            dut.memory.bytes[addr + 3] = data[31:24];
            dut.memory.bytes[addr + 4] = data[39:32];
            dut.memory.bytes[addr + 5] = data[47:40];
            dut.memory.bytes[addr + 6] = data[55:48];
            dut.memory.bytes[addr + 7] = data[63:56];
        end
    endtask

    integer cycles;
    initial begin
        clk = 0;
        reset = 1; #2;

        // Initial memory value should be observed by the older load.
        dut.reg_file.registers[1] = 64'd99;       // store data
        dut.reg_file.registers[2] = 64'h3000;     // base
        store_mem64(64'h3000, 64'd11);

        // Slot1 older LOAD, slot2 younger STORE to same address.
        // Correct behavior: load sees old memory value (11), not younger store value (99).
        store_instr(64'h2000, mk_instr(5'h10, 5'd3, 5'd2, 5'd0, 12'd0)); // load r3 <- [r2]
        store_instr(64'h2004, mk_instr(5'h13, 5'd2, 5'd1, 5'd0, 12'd0)); // store [r2] <- r1
        store_instr(64'h2008, mk_instr(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0)); // halt

        #8 reset = 0;
        cycles = 0;
        while (!hlt && cycles < 200) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!hlt) begin
            $display("FAIL timeout");
            $finish(1);
        end

        if (dut.reg_file.registers[3] !== 64'd11) begin
            $display("FAIL younger-store-forwarding corruption: r3=%0d expected=11", dut.reg_file.registers[3]);
            $finish(1);
        end

        $display("PASS load ordering preserved");
        $finish;
    end
endmodule
