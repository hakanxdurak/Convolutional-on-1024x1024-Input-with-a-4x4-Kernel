// 1R1W Synchronous SRAM with init file and read-valid pipeline
module sram1r1w #(
    parameter int ADDR_WIDTH = 12,   // Address width
    parameter int DATA_WIDTH = 64    // Data width
) (
    //---------------------------------------------------------------
    // General
    input  logic                     clk,
    input  logic                     reset_n,

    //---------------------------------------------------------------
    // Port A: Read Port
    input  logic [ADDR_WIDTH-1:0]    read_address,
    input  logic                     read_enable,
    output logic [DATA_WIDTH-1:0]    read_data,
    output logic                     read_valid, // NEW: indicates data is valid

    //---------------------------------------------------------------
    // Port B: Write Port
    input  logic [ADDR_WIDTH-1:0]    write_address,
    input  logic [DATA_WIDTH-1:0]    write_data,
    input  logic                     write_enable
);

    // Memory declaration
    logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // Initialize memory from external file
    initial begin
        $readmemh("./../tb/debug0.mem", mem);  
    end

    // Registered read data with valid signal
    always_ff @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            read_data  <= '0;
            read_valid <= 1'b0;
        end else begin
            if (read_enable) begin
                read_data  <= mem[read_address];
                read_valid <= 1'b1;  // Data will be valid next cycle
            end else begin
                read_valid <= 1'b0;
            end
        end
    end

    // Write operation
    always_ff @(posedge clk) begin
        if (write_enable)
            mem[write_address] <= write_data;
    end

endmodule
