`include "riscv_defines.h"

module dcache(
    input  wire                 clk              ,
    input  wire                 reset            ,

    // 来自 MEM：VA 用于索引，PA 用于比较
    input  wire                 dcache_req       ,
    input  wire [`PC_WIDTH-1:0] va               , // 虚拟地址（取 index）
    input  wire [`PC_WIDTH-1:0] pa               , // 物理地址（取 tag）
    input  wire                 dcache_we        ,
    input  wire [31:0]          dcache_wdata     ,
    input  wire [1:0]           dcache_size      ,
    input  wire                 dcache_sign_ext  ,
    output reg                  dcache_ack       ,
    output reg [31:0]           dcache_rdata     ,
    output reg                  dcache_miss      ,
    output reg                  dcache_unbusy    ,

    // AXI
    output reg                  axi_arvalid      ,
    output wire [31:0]          axi_araddr       ,
    output wire [2:0]           axi_arprot       ,
    input  wire                 axi_arready      ,
    input  wire                 axi_rvalid       ,
    input  wire [31:0]          axi_rdata        ,
    input  wire                 axi_rlast        ,
    output wire                 axi_rready       ,

    output reg                  axi_awvalid      ,
    output wire [31:0]          axi_awaddr       ,
    output wire [2:0]           axi_awprot       ,
    input  wire                 axi_awready      ,
    output reg                  axi_wvalid       ,
    output wire [31:0]          axi_wdata        ,
    output wire [3:0]           axi_wstrb        ,
    input  wire                 axi_wready       ,
    input  wire                 axi_bvalid       ,
    input  wire [1:0]           axi_bresp        ,

    output reg                  cache_miss_cnt_en,
    input  wire                 uncache_en       ,
    input  wire                 core_stall
);

localparam CACHE_ROW_WIDTH  = 128;
localparam INDEX_WIDTH      = 8;    // 页内偏移 < 页大小(4KB) → VIPT 安全
localparam TAG_WIDTH        = 20;
localparam OFFSET_WIDTH     = 4;
localparam WAY_CNT          = 2;

localparam DCACHE_IDLE      = 3'b001;
localparam DCACHE_LOOKUP    = 3'b010;
localparam DCACHE_REFILL    = 3'b100;
localparam DCACHE_WRITEBACK = 3'b101;

localparam STRB_BYTE     = 4'b0001;
localparam STRB_HALFWORD= 4'b0011;
localparam STRB_WORD    = 4'b1111;

// ====================== VIPT 地址拆分 ======================
wire [TAG_WIDTH-1:0]    pa_tag;     // 物理Tag（来自MMU）
wire [INDEX_WIDTH-1:0]  va_index;   // 虚拟索引（来自VA低位）
wire [OFFSET_WIDTH-1:0] offset;
wire [1:0]              word_offset;
wire [1:0]              byte_offset;

assign pa_tag      = pa[31:12];
assign va_index    = va[11:4];     // VIPT核心：index来自VA
assign offset      = va[3:0];
assign word_offset = offset[3:2];
assign byte_offset = offset[1:0];

// ====================== 2路存储 ======================
reg [CACHE_ROW_WIDTH-1:0] data_way0[0:(1<<INDEX_WIDTH)-1];
reg [CACHE_ROW_WIDTH-1:0] data_way1[0:(1<<INDEX_WIDTH)-1];
reg [TAG_WIDTH-1:0]       tag_way0[0:(1<<INDEX_WIDTH)-1];
reg [TAG_WIDTH-1:0]       tag_way1[0:(1<<INDEX_WIDTH)-1];
reg                       valid_way0[0:(1<<INDEX_WIDTH)-1];
reg                       valid_way1[0:(1<<INDEX_WIDTH)-1];
reg                       dirty_way0[0:(1<<INDEX_WIDTH)-1];
reg                       dirty_way1[0:(1<<INDEX_WIDTH)-1];
reg                       lru_bit[0:(1<<INDEX_WIDTH)-1];

// ====================== 并行读 Tag（不等待MMU） ======================
reg [TAG_WIDTH-1:0] tag0_r;
reg [TAG_WIDTH-1:0] tag1_r;
reg                 v0_r;
reg                 v1_r;

always @(posedge clk) begin
    if(dcache_req && !core_stall) begin
        tag0_r <= tag_way0[va_index];
        tag1_r <= tag_way1[va_index];
        v0_r   <= valid_way0[va_index];
        v1_r   <= valid_way1[va_index];
    end
end

// ====================== 同步比较（MMU给出PA后） ======================
reg hit_way;
reg cache_hit;
always @(*) begin
    cache_hit = 1'b0;
    hit_way   = 1'b0;
    if(v0_r && (tag0_r == pa_tag)) begin cache_hit=1; hit_way=0; end
    if(v1_r && (tag1_r == pa_tag)) begin cache_hit=1; hit_way=1; end
    cache_hit = cache_hit & ~uncache_en;
end

// ====================== AXI ======================
reg [`PC_WIDTH-1:0] req_pa_reg;
reg                 req_we_reg;
reg [31:0]          req_wdata_reg;
reg [1:0]           req_size_reg;

assign axi_araddr  = {req_pa_reg[31:4], 4'b0};
assign axi_awaddr  = {req_pa_reg[31:4], 4'b0};
assign axi_arprot  = 3'b010;
assign axi_awprot  = 3'b010;
assign axi_rready  = 1'b1;

// ====================== 状态机 ======================
reg replace_way;
reg [2:0] dcache_state;
reg [2:0] next_state;

always @(posedge clk or posedge reset) begin
    if(reset) dcache_state <= DCACHE_IDLE;
    else dcache_state <= next_state;
end

always @(*) begin
    next_state = dcache_state;
    case(dcache_state)
        DCACHE_IDLE: if(dcache_req && !core_stall) next_state=DCACHE_LOOKUP;
        DCACHE_LOOKUP: begin
            if(uncache_en) next_state=DCACHE_IDLE;
            else if(!cache_hit) begin
                if(req_we_reg && ((replace_way==0&&dirty_way0[va_index])||
                                  (replace_way==1&&dirty_way1[va_index])))
                    next_state=DCACHE_WRITEBACK;
                else next_state=DCACHE_REFILL;
            end else next_state=DCACHE_IDLE;
        end
        DCACHE_REFILL: if(axi_rvalid&&axi_rlast) next_state=DCACHE_IDLE;
        DCACHE_WRITEBACK:if(axi_bvalid) next_state=DCACHE_REFILL;
    endcase
end

// ====================== LRU ======================
always @(*) begin
    if(!valid_way0[va_index])      replace_way=0;
    else if(!valid_way1[va_index]) replace_way=1;
    else                           replace_way=lru_bit[va_index];
end

integer i;
always @(posedge clk or posedge reset) begin
    if(reset) for(i=0;i<(1<<INDEX_WIDTH);i=i+1) lru_bit[i]<=0;
    else if(dcache_state==DCACHE_LOOKUP && cache_hit && dcache_ack)
        lru_bit[va_index] <= ~hit_way;
end

// ====================== 数据通路 ======================
reg [3:0] wstrb;
reg [31:0] aligned_wdata;
reg [1:0] refill_cnt;
reg [CACHE_ROW_WIDTH-1:0] refill_buffer;
reg [1:0] wback_cnt;
reg [CACHE_ROW_WIDTH-1:0] wback_buffer;

always @(posedge clk or posedge reset) begin
    if(reset) begin
        dcache_ack<=0; dcache_rdata<=0; dcache_miss<=0; dcache_unbusy<=1;
        axi_arvalid<=0; axi_awvalid<=0; axi_wvalid<=0;
        req_pa_reg<=32'h80000000; cache_miss_cnt_en<=0;
        for(i=0;i<(1<<INDEX_WIDTH);i=i+1) begin
            valid_way0[i]<=0; valid_way1[i]<=0; dirty_way0[i]<=0; dirty_way1[i]<=0;
        end
    end else begin
        dcache_ack<=0; dcache_miss<=0; cache_miss_cnt_en<=0;
        axi_arvalid<=0; axi_awvalid<=0; axi_wvalid<=0;

        case(dcache_state)
            DCACHE_IDLE: begin
                dcache_unbusy<=1;
                if(dcache_req && !core_stall) begin
                    req_pa_reg    <= pa;
                    req_we_reg    <= dcache_we;
                    req_wdata_reg <= dcache_wdata;
                    req_size_reg  <= dcache_size;
                end
            end
            DCACHE_LOOKUP: begin
                dcache_unbusy<=0;
                if(cache_hit) begin
                    dcache_ack<=1;
                    if(req_we_reg) begin
                        if(hit_way==0) begin
                            data_way0[va_index][word_offset*32 +:32] <=
                                (wstrb&aligned_wdata)|(~wstrb&data_way0[va_index][word_offset*32 +:32]);
                            dirty_way0[va_index]<=1;
                        end else begin
                            data_way1[va_index][word_offset*32 +:32] <=
                                (wstrb&aligned_wdata)|(~wstrb&data_way1[va_index][word_offset*32 +:32]);
                            dirty_way1[va_index]<=1;
                        end
                    end else begin
                        dcache_rdata <= hit_way ?
                            data_way1[va_index][word_offset*32 +:32] :
                            data_way0[va_index][word_offset*32 +:32];
                    end
                end else begin
                    axi_arvalid<=1; dcache_miss<=1; cache_miss_cnt_en<=1;
                end
            end
            DCACHE_REFILL: begin
                dcache_unbusy<=0;
                if(axi_arvalid&&axi_arready) axi_arvalid<=0;
                if(axi_rvalid) begin
                    refill_buffer[refill_cnt*32 +:32] <= axi_rdata;
                    refill_cnt<=refill_cnt+1;
                    if(axi_rlast) begin
                        if(replace_way==0) begin
                            data_way0[va_index]<=refill_buffer;
                            tag_way0[va_index]<=req_pa_reg[31:12];
                            valid_way0[va_index]<=1;
                            dirty_way0[va_index]<=req_we_reg;
                        end else begin
                            data_way1[va_index]<=refill_buffer;
                            tag_way1[va_index]<=req_pa_reg[31:12];
                            valid_way1[va_index]<=1;
                            dirty_way1[va_index]<=req_we_reg;
                        end
                        dcache_ack<=1;
                        dcache_rdata<=refill_buffer[word_offset*32 +:32];
                        refill_cnt<=0;
                    end
                end
            end
            DCACHE_WRITEBACK: begin
                dcache_unbusy<=0;
                wback_buffer <= replace_way ? data_way1[va_index] : data_way0[va_index];
                axi_awvalid<=1;
                if(axi_awready) axi_awvalid<=0;
                if(!axi_awvalid) begin axi_wvalid<=1; if(axi_wready) wback_cnt<=wback_cnt+1; end
            end
        endcase
    end
end

// ====================== 写掩码 ======================
always @(*) begin
    case(req_size_reg)
        2'b01: wstrb = STRB_BYTE << byte_offset;
        2'b10: wstrb = STRB_HALFWORD << {byte_offset[1],1'b0};
        default:wstrb = STRB_WORD;
    endcase
    aligned_wdata = req_wdata_reg << (word_offset*32);
end

assign axi_wdata = (dcache_state==DCACHE_WRITEBACK) ?
    wback_buffer[wback_cnt*32 +:32] : aligned_wdata;
assign axi_wstrb = (dcache_state==DCACHE_WRITEBACK) ? STRB_WORD : wstrb;


endmodule