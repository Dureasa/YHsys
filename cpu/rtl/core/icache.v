`include "riscv_defines.h"

module icache(
    // 时钟/复位
    input  wire                 clk              ,  // 系统时钟
    input  wire                 reset            ,  // 异步复位（高有效）
    // 与取指阶段对接
    input  wire                 if_req           ,  // 取指阶段读请求
    input  wire [`PC_WIDTH-1:0] if_addr          ,  // 取指地址（PC）
    output reg                  icache_data_ok   ,  // 数据就绪（指令返回）
    output reg [`INST_WIDTH-1:0] icache_rdata    ,  // 返回指令（32位）
    output reg                  icache_miss      ,  // 缓存缺失标记
    output reg                  icache_unbusy    ,  // 缓存非忙（可接收新请求）
    input  wire                 tlb_excp_cancel_req, // TLB异常取消请求
    // AXI总线接口（读通道）
    output reg                  axi_arvalid      ,  // 读地址有效
    output wire [31:0]          axi_araddr       ,  // 读地址（缓存行起始地址）
    output wire [2:0]           axi_arprot       ,  // 读保护属性
    input  wire                 axi_arready      ,  // 读地址就绪
    input  wire                 axi_rvalid       ,  // 读数据有效
    input  wire [31:0]          axi_rdata        ,  // 读数据
    input  wire                 axi_rlast        ,  // 读数据最后一拍
    input  wire                 axi_rready       ,  // 读数据就绪（本模块始终就绪）
    // 性能计数
    output reg                  cache_miss_cnt_en, // 缓存缺失计数使能
    // 非缓存访问控制（可选）
    input  wire                 uncache_en       ,  // 非缓存访问使能
    input  wire                 core_stall       ,  // 全局核心暂停
    // 缓存操作（CACOP，可选）
    input  wire                 icacop_op_en     ,  // 缓存操作使能
    input  wire [1:0]           cacop_op_mode    ,  // 缓存操作模式（0=无效化）
    input  wire [`PC_WIDTH-1:0] cacop_op_addr    ,  // 缓存操作地址
    output reg                  icacop_done         // 缓存操作完成
    // 测试接口（可选）
    /*
    output wire [31:0]          test_tag_way0[255:0], // 测试用标签（Way0）
    output wire [31:0]          test_tag_way1[255:0], // 测试用标签（Way1）
    output wire [255:0]         test_lru_bit          // 测试用LRU位\
    */
);

// ====================== 内部参数/宏定义 ======================
localparam CACHE_ROW_WIDTH    = 128;        // 缓存行宽度（128位）
localparam INDEX_WIDTH        = 8;          // 索引位宽（256组）
localparam TAG_WIDTH          = 20;         // 标签位宽
localparam OFFSET_WIDTH       = 4;          // 偏移位宽（128位行内偏移）
localparam WAY_CNT            = 2;          // 路数（2路组相联）
localparam REPLACE_WAY_WIDTH  = 1;          // 替换路数位宽

// 状态机定义
localparam ICACHE_IDLE        = 3'b001;     // 空闲状态
localparam ICACHE_LOOKUP      = 3'b010;     // 查找状态
localparam ICACHE_REFILL      = 3'b100;     // 填充状态

// ====================== 内部信号定义 ======================
// 地址拆分
wire [TAG_WIDTH-1:0]          tag;            // 标签（地址[31:12]）
wire [INDEX_WIDTH-1:0]        index;          // 索引（地址[11:4]）
wire [OFFSET_WIDTH-1:0]       offset;         // 偏移（地址[3:0]）
wire [OFFSET_WIDTH-2:0]       word_offset;    // 字偏移（地址[3:2]，128位行内4个32位字）

// 缓存存储体
reg [CACHE_ROW_WIDTH-1:0]     data_way0[0:(1<<INDEX_WIDTH)-1]; // Way0数据存储
reg [CACHE_ROW_WIDTH-1:0]     data_way1[0:(1<<INDEX_WIDTH)-1]; // Way1数据存储
reg [TAG_WIDTH-1:0]           tag_way0[0:(1<<INDEX_WIDTH)-1];  // Way0标签
reg [TAG_WIDTH-1:0]           tag_way1[0:(1<<INDEX_WIDTH)-1];  // Way1标签
reg                           valid_way0[0:(1<<INDEX_WIDTH)-1]; // Way0有效位
reg                           valid_way1[0:(1<<INDEX_WIDTH)-1]; // Way1有效位

// LRU状态（核心新增）
reg                           lru_bit[0:(1<<INDEX_WIDTH)-1];    // 每组1位LRU状态

// 命中检测
reg [WAY_CNT-1:0]             way_hit;        // 各路命中标记
reg                           cache_hit;      // 缓存命中

// 状态机
reg [2:0]                     icache_state;   // 当前状态
reg [2:0]                     next_state;     // 下一状态

// 替换策略（LRU版）
reg [REPLACE_WAY_WIDTH-1:0]   replace_way;    // 选中的替换路
reg                           has_invalid_way;// 是否存在无效路
reg [REPLACE_WAY_WIDTH-1:0]   invalid_way;    // 无效路

// 填充相关
reg [1:0]                     refill_cnt;     // 填充计数（4个32位字）
reg [CACHE_ROW_WIDTH-1:0]     refill_buffer;  // 填充缓冲区
reg [`PC_WIDTH-1:0]           req_addr_reg;   // 锁存请求地址
reg                           req_valid_reg;  // 锁存请求有效

// ====================== 地址拆分 ======================
assign tag          = if_addr[31:(INDEX_WIDTH + OFFSET_WIDTH)];
assign index        = if_addr[(INDEX_WIDTH + OFFSET_WIDTH - 1):OFFSET_WIDTH];
assign offset       = if_addr[OFFSET_WIDTH-1:0];
assign word_offset  = offset[3:2];  // 128位行内的32位字偏移（0~3）

// ====================== 命中检测 ======================
always @(*) begin
    // Way0命中：有效位为1 + 标签匹配
    way_hit[0] = valid_way0[index] && (tag_way0[index] == tag);
    // Way1命中：有效位为1 + 标签匹配
    way_hit[1] = valid_way1[index] && (tag_way1[index] == tag);
    // 缓存命中：任意一路命中 且 非缓存操作/非非缓存访问
    cache_hit = (|way_hit) && !icacop_op_en && !uncache_en;
end

// ====================== LRU替换策略 ======================
// 1. 无效路检测（优先替换无效路，无则用LRU）
always @(*) begin
    has_invalid_way = 1'b0;
    invalid_way = 1'b0;
    if (!valid_way0[index]) begin
        has_invalid_way = 1'b1;
        invalid_way = 1'b0;
    end else if (!valid_way1[index]) begin
        has_invalid_way = 1'b1;
        invalid_way = 1'b1;
    end
    // 替换路：无效路优先 > LRU路
    replace_way = has_invalid_way ? invalid_way : lru_bit[index];
end
integer i;
// 2. LRU状态更新（命中时更新，标记命中路为"最近使用"）
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 复位时LRU位初始化为0（Way0为LRU）
        
        for (i = 0; i < (1<<INDEX_WIDTH); i = i + 1) begin
            lru_bit[i] <= 1'b0;
        end
    end else if (icache_state == ICACHE_LOOKUP && cache_hit) begin
        // Way0命中 → 标记Way1为LRU（lru_bit=1）
        if (way_hit[0]) begin
            lru_bit[index] <= 1'b1;
        end
        // Way1命中 → 标记Way0为LRU（lru_bit=0）
        else if (way_hit[1]) begin
            lru_bit[index] <= 1'b0;
        end
    end else if (icache_state == ICACHE_LOOKUP && icacop_op_en) begin
        // 缓存操作（无效化）→ 若无效路是LRU路，更新LRU位
        case (cacop_op_mode)
            2'b00: begin  // 无效化指定路
                if (replace_way == lru_bit[index]) begin
                    lru_bit[index] <= ~lru_bit[index];
                end
            end
            2'b01: begin  // 无效化整个组 → LRU位重置为0
                lru_bit[index] <= 1'b0;
            end
        endcase
    end
end

// ====================== AXI读地址生成 ======================
// 缓存行起始地址（对齐到128位）
assign axi_araddr = {req_addr_reg[31:4], 4'b0};
// AXI保护属性（取指阶段，特权级0，指令访问）
assign axi_arprot = 3'b001;
// AXI读数据就绪（始终就绪）
assign axi_rready = 1'b1;

// ====================== 状态机控制 ======================
// 1. 状态寄存器更新
always @(posedge clk or posedge reset) begin
    if (reset) begin
        icache_state <= ICACHE_IDLE;
    end else begin
        icache_state <= next_state;
    end
end

// 2. 下一状态逻辑
always @(*) begin
    next_state = icache_state;
    case (icache_state)
        ICACHE_IDLE: begin
            // 空闲状态：有取指请求/缓存操作请求则进入查找状态
            if ((if_req && !core_stall) || icacop_op_en) begin
                next_state = ICACHE_LOOKUP;
            end
        end
        ICACHE_LOOKUP: begin
            // 查找状态：
            if (tlb_excp_cancel_req || icacop_op_en) begin
                // TLB异常/缓存操作 → 返回空闲
                next_state = ICACHE_IDLE;
            end else if (uncache_en) begin
                // 非缓存访问 → 直接填充（AXI读）
                next_state = ICACHE_REFILL;
            end else if (!cache_hit && if_req) begin
                // 缓存缺失 → 填充状态
                next_state = ICACHE_REFILL;
            end else begin
                // 缓存命中 → 返回空闲
                next_state = ICACHE_IDLE;
            end
        end
        ICACHE_REFILL: begin
            // 填充状态：AXI读完成（rlast）/异常取消 → 返回空闲
            if (tlb_excp_cancel_req || (axi_rvalid && axi_rlast)) begin
                next_state = ICACHE_IDLE;
            end
        end
        default: begin
            next_state = ICACHE_IDLE;
        end
    endcase
end

// ====================== 状态机输出逻辑 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 复位初始化
        icache_data_ok    <= 1'b0;
        icache_rdata      <= 32'b0;
        icache_miss       <= 1'b0;
        icache_unbusy     <= 1'b1;
        axi_arvalid       <= 1'b0;
        refill_cnt        <= 2'b0;
        refill_buffer     <= 128'b0;
        req_addr_reg      <= 32'h80000000; //复位PC地址
        req_valid_reg     <= 1'b0;
        cache_miss_cnt_en <= 1'b0;
        icacop_done       <= 1'b0;

        // 缓存存储体初始化（有效位清零）
        //integer i;
        for (i = 0; i < (1<<INDEX_WIDTH); i = i + 1) begin
            valid_way0[i] <= 1'b0;
            valid_way1[i] <= 1'b0;
            tag_way0[i]   <= {TAG_WIDTH{1'b0}};
            tag_way1[i]   <= {TAG_WIDTH{1'b0}};
            data_way0[i]  <= {CACHE_ROW_WIDTH{1'b0}};
            data_way1[i]  <= {CACHE_ROW_WIDTH{1'b0}};
        end
    end else begin
        // 默认值
        icache_data_ok    <= 1'b0;
        icache_miss       <= 1'b0;
        icacop_done       <= 1'b0;
        cache_miss_cnt_en <= 1'b0;

        case (icache_state)
            ICACHE_IDLE: begin
                icache_unbusy <= 1'b1;
                // 锁存请求地址
                if ((if_req && !core_stall) || icacop_op_en) begin
                    req_addr_reg  <= icacop_op_en ? cacop_op_addr : if_addr;
                    req_valid_reg <= 1'b1;
                end else begin
                    req_valid_reg <= 1'b0;
                end
            end

            ICACHE_LOOKUP: begin
                icache_unbusy <= 1'b0;
                if (tlb_excp_cancel_req) begin
                    // TLB异常取消 → 无输出
                    icache_data_ok <= 1'b0;
                end else if (icacop_op_en) begin
                    // 缓存操作（无效化）
                    case (cacop_op_mode)
                        2'b00: begin  // 无效化指定路
                            if (replace_way == 1'b0) begin
                                valid_way0[index] <= 1'b0;
                            end else begin
                                valid_way1[index] <= 1'b0;
                            end
                        end
                        2'b01: begin  // 无效化整个组
                            valid_way0[index] <= 1'b0;
                            valid_way1[index] <= 1'b0;
                        end
                    endcase
                    icacop_done <= 1'b1;
                end else if (uncache_en) begin
                    // 非缓存访问 → 发起AXI读
                    axi_arvalid <= 1'b1;
                    icache_miss <= 1'b1;
                end else if (cache_hit) begin
                    // 缓存命中 → 返回指令
                    icache_data_ok <= 1'b1;
                    // 选择命中路的指令（128位行内取32位）
                    if (way_hit[0]) begin
                        case (word_offset)
                            2'b00: icache_rdata <= data_way0[index][31:0];
                            2'b01: icache_rdata <= data_way0[index][63:32];
                            2'b10: icache_rdata <= data_way0[index][95:64];
                            2'b11: icache_rdata <= data_way0[index][127:96];
                        endcase
                    end else begin
                        case (word_offset)
                            2'b00: icache_rdata <= data_way1[index][31:0];
                            2'b01: icache_rdata <= data_way1[index][63:32];
                            2'b10: icache_rdata <= data_way1[index][95:64];
                            2'b11: icache_rdata <= data_way1[index][127:96];
                        endcase
                    end
                end else begin
                    // 缓存缺失 → 发起AXI读（替换LRU路）
                    axi_arvalid <= 1'b1;
                    icache_miss <= 1'b1;
                    cache_miss_cnt_en <= 1'b1;
                end
            end

            ICACHE_REFILL: begin
                icache_unbusy <= 1'b0;
                // AXI读地址握手完成后，撤销读请求
                if (axi_arvalid && axi_arready) begin
                    axi_arvalid <= 1'b0;
                end
                // 接收AXI读数据，填充缓冲区
                if (axi_rvalid) begin
                    refill_cnt <= refill_cnt + 1'b1;
                    case (refill_cnt)
                        2'b00: refill_buffer[31:0]   <= axi_rdata;
                        2'b01: refill_buffer[63:32]  <= axi_rdata;
                        2'b10: refill_buffer[95:64]  <= axi_rdata;
                        2'b11: refill_buffer[127:96] <= axi_rdata;
                    endcase
                    // 最后一拍数据 → 写入缓存存储体（LRU路）
                    if (axi_rlast) begin
                        if (replace_way == 1'b0) begin
                            data_way0[index]  <= refill_buffer;
                            tag_way0[index]   <= tag;
                            valid_way0[index] <= 1'b1;
                        end else begin
                            data_way1[index]  <= refill_buffer;
                            tag_way1[index]   <= tag;
                            valid_way1[index] <= 1'b1;
                        end
                        // 返回指令给取指阶段
                        icache_data_ok <= 1'b1;
                        case (word_offset)
                            2'b00: icache_rdata <= refill_buffer[31:0];
                            2'b01: icache_rdata <= refill_buffer[63:32];
                            2'b10: icache_rdata <= refill_buffer[95:64];
                            2'b11: icache_rdata <= refill_buffer[127:96];
                        endcase
                        refill_cnt <= 2'b0;
                    end
                end
                // 非缓存访问：直接返回AXI数据（不写入缓存）
                if (uncache_en && axi_rvalid) begin
                    icache_data_ok <= 1'b1;
                    icache_rdata   <= axi_rdata;
                end
                // TLB异常取消 → 撤销AXI请求
                if (tlb_excp_cancel_req) begin
                    axi_arvalid <= 1'b0;
                end
            end
        endcase
    end
end

/*
// ====================== 测试接口赋值 ======================
generate
    genvar i;
    for (i = 0; i < (1<<INDEX_WIDTH); i = i + 1) begin
        assign test_tag_way0[i] = {tag_way0[i], valid_way0[i]};
        assign test_tag_way1[i] = {tag_way1[i], valid_way1[i]};
        assign test_lru_bit[i]  = lru_bit[i]; // LRU位测试输出
    end
endgenerate
*/
endmodule
