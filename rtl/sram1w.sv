module sram1w #(
    parameter int ADDR_WIDTH = 12,
    parameter int DATA_WIDTH = 64
) (
    input  logic                     clk,
    input  logic                     reset_n,

    // Read Port
    input  logic [ADDR_WIDTH-1:0]    read_address,
    input  logic                     read_enable,
    output logic [DATA_WIDTH-1:0]    read_data,
    output logic                     read_valid,

    // Write Port
    input  logic [ADDR_WIDTH-1:0]    write_address,
    input  logic [DATA_WIDTH-1:0]    write_data,
    input  logic                     write_enable
);

    // Memory declaration
    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // Registered read with valid signal
    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            read_data  <= '0;
            read_valid <= 1'b0;
        end else begin
            if (read_enable) begin
                read_data  <= mem[read_address];
                read_valid <= 1'b1;
            end else begin
                read_valid <= 1'b0;
            end
        end
    end

    // Write operation + dump memory
    always_ff @(posedge clk) begin
        if (write_enable) begin
            mem[write_address] <= write_data;
            $display("Write: Addr=%0d Data=%h", write_address, write_data);
            $writememh("/users/hdurak/Desktop/sram_trial/tb/debug1.mem", mem);
        end
    end

    // Final dump at end of simulation
    final begin
        $writememh("/users/hdurak/Desktop/sram_trial/tb/debug1.mem", mem);
        $display("Final memory dump completed.");
    end

endmodule
