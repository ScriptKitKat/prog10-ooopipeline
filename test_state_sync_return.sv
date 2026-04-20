`include "tinker.sv"

module test_state_sync_return;
    reg clk, reset;
    wire hlt;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

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
        reset = 1;
        #2;

        // 0x2000: return
        // 0x2004: addi r2, 5   (wrong-path marker)
        // 0x2008: addi r2, 1   (correct target)
        // 0x200c: halt
        store_instr(64'h2000, 32'h68000000);
        store_instr(64'h2004, 32'hC8800005);
        store_instr(64'h2008, 32'hC8800001);
        store_instr(64'h200C, 32'h78000000);

        // Return target = 0x2008
        store_mem64(64'd524280, 64'h0000000000002008);

        #8 reset = 0;

        // Simulate state-loader writes after reset release:
        // architectural state says r2=0, but PRF P2 is stale 4.
        dut.reg_file.registers[31] = 64'd524288;
        dut.reg_file.registers[2]  = 64'd0;
        dut.prf_inst.regs[2]       = 64'd4;
        dut.prf_inst.ready[2]      = 1'b1;

        cycles = 0;
        while (!hlt && cycles < 200) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (dut.reg_file.registers[2] !== 64'd1) begin
            $display("FAIL state_sync_return r2=%0d cycles=%0d", dut.reg_file.registers[2], cycles);
            $finish;
        end

        $display("PASS state_sync_return r2=%0d cycles=%0d", dut.reg_file.registers[2], cycles);
        $finish;
    end
endmodule
