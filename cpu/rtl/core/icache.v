`include "riscv_defines.h"

module icache(
    // 时钟/复位
    input  wire                 clk              ,
    input  wire                 reset            ,
    // 与取指阶段（IF）对接（VIPT 接口）
    input  wire                 icache_req       ,  // 取指请求（读指令）
    input  wire [`PC_WIDTH-1:0] va               ,  // 虚拟地址（用于索引，来自IF）
    input  wire [`PC_WIDTH-1:0] pa               ,  // 物理地址（用于Tag比较，来自IMMU）
    input  wire                 immu_ready       ,  // IMMU地址转换完成（有效时才可判定命中）
    output reg                  icache_ack       ,  // 响应信号（1=取指完成）
    output reg [31:0]           icache_rdata     ,  // 指令数据返回（32位）
    output reg                  icache_miss      ,  // 缓存缺失标记
    output reg                  icache_unbusy    ,  // 缓存非忙（可接收新请求）
    input  wire                 core_stall       ,  // 全局核心暂停
    input  wire                 if_excp_flush    ,  // 取指阶段异常冲刷
    // AXI总线接口（读通道，仅用于指令缺失填充）
    output reg                  axi_arvalid      ,  // 读地址有效
    output wire [31:0]          axi_araddr       ,  // 读地址（缓存行起始物理地址）
    output wire [2:0]           axi_arprot       ,  // 读保护属性（指令访问）
    input  wire                 axi_arready      ,  // 读地址就绪
    input  wire                 axi_rvalid       ,  // 读数据有效
    input  wire [31:0]          axi_rdata        ,  // 读数据（指令）
    input  wire                 axi_rlast        ,  // 读数据最后一拍
    output wire                 axi_rready       ,  // 读数据就绪（本模块始终就绪）
    // 性能计数
    output reg                  cache_miss_cnt_en  // 缓存缺失计数使能
);

// ====================== 内部参数/宏定义 ======================
localparam CACHE_ROW_WIDTH    = 128;        // 缓存行宽度（128位，4条32位指令）
localparam INDEX_WIDTH        = 8;          // 索引位宽（256组，页内偏移<4KB，VIPT安全）
localparam TAG_WIDTH          = 20;         // 物理标签位宽（PA[31:12]）
localparam OFFSET_WIDTH       = 4;          // 偏移位宽（VA[3:0]，页内偏移）
localparam WAY_CNT            = 2;          // 路数（2路组相联）
localparam REFILL_CNT_WIDTH   = 2;          // 填充计数位宽（4个32位指令）

// 状态机定义（仅读操作，精简状态）
localparam ICACHE_IDLE        = 3'b001;     // 空闲状态
localparam ICACHE_LOOKUP      = 3'b010;     // 查找状态（并行读Tag+等待IMMU）
localparam ICACHE_REFILL      = 3'b100;     // 填充状态（指令缺失）

// AXI保护属性（指令访问，特权级0，普通访问）
localparam AXI_ARPROT_INST    = 3'b000;

// ====================== VIPT 地址拆分 ======================
wire [TAG_WIDTH-1:0]          pa_tag;         // 物理标签（来自IMMU的PA[31:12]）
wire [INDEX_WIDTH-1:0]        va_index;       // 虚拟索引（来自VA[11:4]，页内偏移）
wire [OFFSET_WIDTH-1:0]       offset;         // 偏移（VA[3:0]，缓存行内指令偏移）
wire [OFFSET_WIDTH-2:0]       inst_offset;    // 指令偏移（VA[3:2]，128位行内4条指令）

assign pa_tag      = pa[31:(INDEX_WIDTH + OFFSET_WIDTH)];  // PA[31:12]
assign va_index    = va[(INDEX_WIDTH + OFFSET_WIDTH - 1):OFFSET_WIDTH];  // VA[11:4]
assign offset      = va[OFFSET_WIDTH-1:0];  // VA[3:0]
assign inst_offset = offset[3:2];  // 缓存行内32位指令的偏移（0~3）

// ====================== 缓存存储体（2路组相联，物理Tag） ======================
reg [CACHE_ROW_WIDTH-1:0]     data_way0[0:(1<<INDEX_WIDTH)-1];  // Way0指令存储
reg [CACHE_ROW_WIDTH-1:0]     data_way1[0:(1<<INDEX_WIDTH)-1];  // Way1指令存储
reg [TAG_WIDTH-1:0]           tag_way0[0:(1<<INDEX_WIDTH)-1];   // Way0物理标签
reg [TAG_WIDTH-1:0]           tag_way1[0:(1<<INDEX_WIDTH)-1];   // Way1物理标签
reg                           valid_way0[0:(1<<INDEX_WIDTH)-1];  // Way0有效位
reg                           valid_way1[0:(1<<INDEX_WIDTH)-1];  // Way1有效位

//状态机
reg [2:0]                     icache_state;   // 当前状态
reg [2:0]                     next_state;     // 下一状态

// LRU状态（每组1位，0=Way0为LRU，1=Way1为LRU）
reg                           lru_bit[0:(1<<INDEX_WIDTH)-1];

// ====================== 并行读Tag（不等待IMMU，取指请求到来立即读） ======================
reg [TAG_WIDTH-1:0]          tag0_r;         // Way0读出的物理Tag（寄存）
reg [TAG_WIDTH-1:0]          tag1_r;         // Way1读出的物理Tag（寄存）
reg                           valid0_r;       // Way0有效位（寄存）
reg                           valid1_r;       // Way1有效位（寄存）

always @(posedge clk) begin
    if (icache_req && !core_stall && !if_excp_flush) begin
        tag0_r    <= tag_way0[va_index];
        tag1_r    <= tag_way1[va_index];
        valid0_r  <= valid_way0[va_index];
        valid1_r  <= valid_way1[va_index];
    end
end

// ====================== 同步命中比较（IMMU_ready有效时判定） ======================
reg [WAY_CNT-1:0]             way_hit;        // 各路命中标记
reg                           cache_hit;      // 缓存命中（IMMU_ready+Tag匹配）
reg                           hit_way;        // 命中路（0=Way0，1=Way1）

always @(*) begin
    // 命中条件：有效位为1 + 物理Tag匹配 + IMMU转换完成
    way_hit[0] = valid0_r && (tag0_r == pa_tag) && immu_ready;
    way_hit[1] = valid1_r && (tag1_r == pa_tag) && immu_ready;
    cache_hit   = |way_hit;
    hit_way     = way_hit[1] ? 1'b1 : 1'b0;
end

// ====================== LRU替换策略（优先无效路，其次LRU） ======================
reg [0:0]                     replace_way;     // 选中的替换路
reg                           has_invalid_way; // 是否存在无效路

always @(*) begin
    has_invalid_way = !valid_way0[va_index] || !valid_way1[va_index];
    // 替换路：无效路优先，无则用LRU
    replace_way = !valid_way0[va_index] ? 1'b0 :
                  !valid_way1[va_index] ? 1'b1 : lru_bit[va_index];
end

// LRU状态更新（命中时更新，标记命中路为最近使用）
integer i;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 复位时LRU位初始化为0
        for (i = 0; i < (1<<INDEX_WIDTH); i = i + 1) begin
            lru_bit[i] <= 1'b0;
        end
    end else if (icache_state == ICACHE_LOOKUP && cache_hit) begin
        // Way0命中 → 标记Way1为LRU（lru_bit=1）
        if (way_hit[0]) begin
            lru_bit[va_index] <= 1'b1;
        end
        // Way1命中 → 标记Way0为LRU（lru_bit=0）
        else if (way_hit[1]) begin
            lru_bit[va_index] <= 1'b0;
        end
    end
end

// ====================== AXI接口信号生成 ======================
reg [`PC_WIDTH-1:0]           req_pa_reg;     // 锁存请求的物理地址（用于AXI）
reg [REFILL_CNT_WIDTH-1:0]    refill_cnt;     // 填充计数（0~3）
reg [CACHE_ROW_WIDTH-1:0]     refill_buffer;  // 填充缓冲区（暂存AXI读指令）

// AXI读地址（缓存行起始物理地址，对齐到128位）
assign axi_araddr  = {req_pa_reg[31:4], 4'b0};
// AXI保护属性（指令访问）
assign axi_arprot  = AXI_ARPROT_INST;
// 读数据就绪（始终就绪）
assign axi_rready  = 1'b1;

// ====================== 状态机 ======================
// 状态寄存器更新
always @(posedge clk or posedge reset) begin
    if (reset) begin
        icache_state <= ICACHE_IDLE;
    end else begin
        icache_state <= next_state;
    end
end

// 下一状态逻辑
always @(*) begin
    next_state = icache_state;
    case (icache_state)
        ICACHE_IDLE: begin
            // 空闲：有取指请求且未暂停/冲刷 → 进入查找
            if (icache_req && !core_stall && !if_excp_flush) begin
                next_state = ICACHE_LOOKUP;
            end
        end
        ICACHE_LOOKUP: begin
            // 查找：异常冲刷 → 返回空闲；命中 → 返回空闲；未命中+IMMU就绪 → 填充
            if (if_excp_flush) begin
                next_state = ICACHE_IDLE;
            end else if (cache_hit) begin
                next_state = ICACHE_IDLE;
            end else if (!cache_hit && immu_ready) begin
                next_state = ICACHE_REFILL;
            end
            // 未命中且IMMU未就绪 → 保持查找，等待IMMU
        end
        ICACHE_REFILL: begin
            // 填充：AXI读完成 → 返回空闲；异常冲刷 → 撤销填充
            if (if_excp_flush || (axi_rvalid && axi_rlast)) begin
                next_state = ICACHE_IDLE;
            end
        end
        default: begin
            next_state = ICACHE_IDLE;
        end
    endcase
end

// ====================== 状态机输出与控制逻辑 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 复位初始化
        icache_ack        <= 1'b0;
        icache_rdata      <= 32'b0;
        icache_miss       <= 1'b0;
        icache_unbusy     <= 1'b1;
        axi_arvalid       <= 1'b0;
        refill_cnt        <= 2'b0;
        refill_buffer     <= 128'b0;
        req_pa_reg        <= 32'h80000000;
        cache_miss_cnt_en <= 1'b0;

        // 缓存存储体初始化
        for (i = 0; i < (1<<INDEX_WIDTH); i = i + 1) begin
            valid_way0[i] <= 1'b0;
            valid_way1[i] <= 1'b0;
            tag_way0[i]   <= {TAG_WIDTH{1'b0}};
            tag_way1[i]   <= {TAG_WIDTH{1'b0}};
            data_way0[i]  <= {CACHE_ROW_WIDTH{1'b0}};
            data_way1[i]  <= {CACHE_ROW_WIDTH{1'b0}};
        end
    end else begin
        // 默认值（避免锁存器）
        icache_ack        <= 1'b0;
        icache_miss       <= 1'b0;
        cache_miss_cnt_en <= 1'b0;
        axi_arvalid       <= 1'b0;

        case (icache_state)
            ICACHE_IDLE: begin
                icache_unbusy <= 1'b1;
                // 锁存请求的物理地址（IMMU输出的PA）
                if (icache_req && !core_stall && !if_excp_flush) begin
                    req_pa_reg <= pa;
                end
            end
            ICACHE_LOOKUP: begin
                icache_unbusy <= 1'b0;
                if (if_excp_flush) begin
                    // 异常冲刷：无响应
                    icache_ack <= 1'b0;
                end else if (cache_hit) begin
                    // 命中：返回对应指令
                    icache_ack <= 1'b1;
                    if (hit_way == 1'b0) begin
                        icache_rdata <= data_way0[va_index][inst_offset*32 +: 32];
                    end else begin
                        icache_rdata <= data_way1[va_index][inst_offset*32 +: 32];
                    end
                end else if (immu_ready) begin
                    // 未命中+IMMU就绪：发起AXI读，标记缺失
                    axi_arvalid       <= 1'b1;
                    icache_miss       <= 1'b1;
                    cache_miss_cnt_en <= 1'b1;
                end
            end
            ICACHE_REFILL: begin
                icache_unbusy <= 1'b0;
                // AXI读地址握手完成后，撤销读请求
                if (axi_arvalid && axi_arready) begin
                    axi_arvalid <= 1'b0;
                end
                // 接收AXI指令，填充缓冲区
                if (axi_rvalid) begin
                    refill_cnt <= refill_cnt + 1'b1;
                    case (refill_cnt)
                        2'b00: refill_buffer[31:0]   <= axi_rdata;
                        2'b01: refill_buffer[63:32]  <= axi_rdata;
                        2'b10: refill_buffer[95:64]  <= axi_rdata;
                        2'b11: refill_buffer[127:96] <= axi_rdata;
                    endcase
                    // 最后一拍指令 → 写入缓存存储体
                    if (axi_rlast) begin
                        if (replace_way == 1'b0) begin
                            data_way0[va_index]  <= refill_buffer;
                            tag_way0[va_index]   <= pa_tag;
                            valid_way0[va_index] <= 1'b1;
                        end else begin
                            data_way1[va_index]  <= refill_buffer;
                            tag_way1[va_index]   <= pa_tag;
                            valid_way1[va_index] <= 1'b1;
                        end
                        // 返回填充的指令
                        icache_ack   <= 1'b1;
                        icache_rdata <= refill_buffer[inst_offset*32 +: 32];
                        refill_cnt   <= 2'b0;
                    end
                end
                // 异常冲刷：撤销AXI请求，清空填充计数
                if (if_excp_flush) begin
                    axi_arvalid <= 1'b0;
                    refill_cnt  <= 2'b0;
                end
            end
        endcase
    end
end

endmodule