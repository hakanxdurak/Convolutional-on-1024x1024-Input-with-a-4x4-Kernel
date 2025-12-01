module main_top #(
  parameter int SRAM_ADDRESS_WIDTH = 12,
  parameter int SRAM_DATA_WIDTH    = 64,
  parameter int KERNEL_DATA_WIDTH  = 8
)(
  input  logic clk,
  input  logic reset_n,
  input  logic start,
  output logic ready
);

  // ===================================
  // Internal variables 
  // ===================================
  logic [SRAM_ADDRESS_WIDTH-1:0] read_address;
  logic [SRAM_DATA_WIDTH-1:0]    read_data;
  logic                          read_enable;
  logic                          read_valid;

  logic [SRAM_ADDRESS_WIDTH-1:0] write_address;
  logic [SRAM_DATA_WIDTH-1:0]    write_data;
  logic                          write_enable;

  // Full precision convolution results
  logic  [20:0] conv_results [0:4];
  logic [7:0]  conv_results_trunc [0:4];
  
  // ===================================
  // FSM State
  // ===================================
  typedef enum logic { IDLE, PROCESSING } main_fsm_t;
  main_fsm_t main_fsm, main_fsm_next;

  always_ff @(posedge clk or negedge reset_n) begin
    if(~reset_n) main_fsm <= IDLE;
    else         main_fsm <= main_fsm_next;
  end
  always_comb begin  
    case(main_fsm)
      IDLE       : main_fsm_next = start ? PROCESSING : IDLE;
      PROCESSING : main_fsm_next = ready ? IDLE : PROCESSING;
      default    : main_fsm_next = IDLE;
    endcase
  end

  // ====================================
  // SRAM Reading
  // ====================================
  logic [SRAM_ADDRESS_WIDTH-1:0] addr_counter_reg_next;
  logic [SRAM_ADDRESS_WIDTH-1:0] addr_counter_reg;

  always_comb begin
    if      (main_fsm == IDLE       && start      ) addr_counter_reg_next = '0;
    else if (main_fsm == PROCESSING && read_enable) addr_counter_reg_next = addr_counter_reg + 8;
    else                                            addr_counter_reg_next = addr_counter_reg;
  end
  always_ff @(posedge clk or negedge reset_n) begin
    if(~reset_n) addr_counter_reg <= '0;
    else         addr_counter_reg <= addr_counter_reg_next;
  end

  assign read_enable  = (main_fsm == PROCESSING);
  assign ready        = ((main_fsm == PROCESSING) && (addr_counter_reg == 'h408));
  assign read_address = addr_counter_reg;

  // ====================================
  // SRAM Instances
  // ====================================
  sram1r1w #(
    .ADDR_WIDTH(SRAM_ADDRESS_WIDTH), 
    .DATA_WIDTH(SRAM_DATA_WIDTH)
    ) u_sram (
    .clk          (clk         ), 
    .reset_n      (reset_n     ),
    .read_address (read_address), 
    .read_enable  (read_enable ),
    .read_data    (read_data   ), 
    .read_valid   (read_valid  ),
    .write_address('0          ), 
    .write_data   ('0          ), 
    .write_enable ('0          )
  );

  sram1w #(
    .ADDR_WIDTH(SRAM_ADDRESS_WIDTH), 
    .DATA_WIDTH(SRAM_DATA_WIDTH)
    ) u_sram_results (
    .clk          (clk          ), 
    .reset_n      (reset_n      ),
    .read_address ('0           ), 
    .read_enable  ('0           ),
    .read_data    (             ), 
    .read_valid   (             ),
    .write_address(write_address), 
    .write_data   (write_data   ), 
    .write_enable (write_enable )
  );

  // ===================================
  // Kernel Storage
  // ===================================
  logic  [KERNEL_DATA_WIDTH-1:0] kernel [0:3][0:3];
  logic [1:0] row_reg_next;
  logic [1:0] row_reg;

  always_comb begin
    if    (read_valid && (row_reg < 2)) row_reg_next =row_reg + 1; 
    else                               row_reg_next =row_reg;
  end
  always_ff @(posedge clk or negedge reset_n) begin
    if (~reset_n) row_reg <= '0;
    else          row_reg <= row_reg_next;
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (~reset_n) begin
      for (int r = 0; r < 4; r++) 
        for (int c = 0; c < 4; c++) 
          kernel[r][c] <= '0;
    end else if (read_valid && row_reg < 2) begin
      case (row_reg)
        2'd0: begin
          kernel[0][0] <= read_data[7:0];   kernel[0][1] <= read_data[15:8];
          kernel[0][2] <= read_data[23:16]; kernel[0][3] <= read_data[31:24];
          kernel[1][0] <= read_data[39:32]; kernel[1][1] <= read_data[47:40];
          kernel[1][2] <= read_data[55:48]; kernel[1][3] <= read_data[63:56];
        end
        2'd1: begin
          kernel[2][0] <= read_data[7:0];   kernel[2][1] <= read_data[15:8];
          kernel[2][2] <= read_data[23:16]; kernel[2][3] <= read_data[31:24];
          kernel[3][0] <= read_data[39:32]; kernel[3][1] <= read_data[47:40];
          kernel[3][2] <= read_data[55:48]; kernel[3][3] <= read_data[63:56];
        end
      endcase
    end
  end

  // ===================================
  // Sliding Line Buffers
  // ===================================
  logic  [7:0] line1 [0:7];
  logic  [7:0] line2 [0:7];
  logic  [7:0] line3 [0:7];
  logic  [7:0] line4 [0:7];

  always_ff @(posedge clk or negedge reset_n) begin
    if (~reset_n) begin
      for (int i = 0; i < 8; i++) begin
        line1[i] <= '0; 
        line2[i] <= '0; 
        line3[i] <= '0; 
        line4[i] <= '0;
      end
    end else if (read_valid && addr_counter_reg >= 'h18) begin
      // Shift lines upward and insert new line at bottom
      for (int i = 0; i < 8; i++) begin
        line1[i] <= line2[i];
        line2[i] <= line3[i];
        line3[i] <= line4[i];
        line4[i] <= read_data[(8*i)+:8];
      end
    end
  end

  // ===================================
  // Immediate line1 change detection
  // ===================================
  logic  [7:0] line1_prev [0:7];
  logic line1_changed_comb;

  always_comb begin
    line1_changed_comb = 1'b0;
    for (int i = 0; i < 8; i++) begin
      if (line1[i] != line1_prev[i]) line1_changed_comb = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge reset_n) begin
    if (~reset_n) for (int i = 0; i < 8; i++) line1_prev[i] <= '0;
    else          for (int i = 0; i < 8; i++) line1_prev[i] <= line1[i];
  end

  // ===================================
  // Convolution + Truncation
  // ===================================
  always_comb begin
    for (int w = 0; w < 5; w++) begin
      conv_results[w] = 0;
      if (addr_counter_reg >= 'h18) begin
        for (int r = 0; r < 4; r++) begin
          for (int c = 0; c < 4; c++) begin
            case (r)
              0: conv_results[w] += kernel[r][c] * line1[w+c];
              1: conv_results[w] += kernel[r][c] * line2[w+c];
              2: conv_results[w] += kernel[r][c] * line3[w+c];
              3: conv_results[w] += kernel[r][c] * line4[w+c];
            endcase
          end
        end
      end
      conv_results_trunc[w] = conv_results[w][7:0];
    end
  end

  // ===================================
  // Write to second SRAM immediately when line1 changes
  // ===================================
  always_ff @(posedge clk or negedge reset_n) begin
    if (~reset_n) begin
      write_enable  <= '0;
      write_address <= '0;
      write_data    <= '0;
    end else if (line1_changed_comb) begin
      write_enable  <= 1'b1;
      write_address <= write_address + 1;
      write_data    <= {conv_results_trunc[4], conv_results_trunc[3],
                        conv_results_trunc[2], conv_results_trunc[1],
                        conv_results_trunc[0], 24'b0};
    end else begin
      write_enable <= 1'b0;
    end
  end

endmodule
