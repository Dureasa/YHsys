`include "riscv_defines.h"

module dcache(
    // 时钟/复位
    input  wire                 clk              ,  // 系统时钟
    input  wire                 reset            ,  // 异步复位（高有效）
    // 与访存阶段对接
    input  wire                 dcache_req       ,  // 访存阶段请求（读/写）
    input  wire                 dcache_we        ,  // 写使能（1=写，0=读）
    input  wire [`PC_WIDTH-1:0] dcache_addr      ,  // 访存地址
    input  wire [31:0]          dcache_wdata     ,  // 写数据（32位）
    input  wire [1:0]           dcache_size      ,  // 访问大小（00=字，01=字节，10=半字）
    input  wire                 dcache_sign_ext  ,  // 读数据符号扩展标记（透传，本模块不处理）
    output reg                  dcache_ack       ,  // 响应信号（1=操作完成）
    output reg [31:0]           dcache_rdata     ,  // 读数据返回（32位）
    output reg                  dcache_miss      ,  // 缓存缺失标记
    output reg                  dcache_unbusy    ,  // 缓存非忙（可接收新请求）
    input  wire                 tlb_excp_cancel_req, // TLB异常取消请求
    // AXI总线接口（读/写通道）
    // 读通道（缓存缺失填充）
    output reg                  axi_arvalid      ,  // 读地址有效
    output wire [31:0]          axi_araddr       ,  // 读地址（缓存行起始地址）
    output wire [2:0]           axi_arprot       ,  // 读保护属性
    input  wire                 axi_arready      ,  // 读地址就绪
    input  wire                 axi_rvalid       ,  // 读数据有效
    input  wire [31:0]          axi_rdata        ,  // 读数据
    input  wire                 axi_rlast        ,  // 读数据最后一拍
    input  wire                 axi_rready       ,  // 读数据就绪（本模块始终就绪）
    // 写通道（写回/直写）
    output reg                  axi_awvalid      ,  // 写地址有效
    output wire [31:0]          axi_awaddr       ,  // 写地址（缓存行起始地址）
    output wire [2:0]           axi_awprot       ,  // 写保护属性
    input  wire                 axi_awready      ,  // 写地址就绪
    output reg                  axi_wvalid       ,  // 写数据有效
    output wire [31:0]          axi_wdata        ,  // 写数据
    output wire [3:0]           axi_wstrb        ,  // 写选通（字节使能）
    input  wire                 axi_wready       ,  // 写数据就绪
    input  wire                 axi_bvalid       ,  // 写响应有效
    input  wire [1:0]           axi_bresp        ,  // 写响应
    // 性能计数
    output reg                  cache_miss_cnt_en, // 缓存缺失计数使能
    // 非缓存访问控制
    input  wire                 uncache_en       ,  // 非缓存访问使能
    input  wire                 core_stall       ,  // 全局核心暂停
    // 缓存操作（CACOP）
    input  wire                 dcacop_op_en     ,  // 缓存操作使能
    input  wire [1:0]           cacop_op_mode    ,  // 缓存操作模式（0=无效化，1=写回）
    input  wire [`PC_WIDTH-1:0] cacop_op_addr    ,  // 缓存操作地址
    output reg                  dcacop_done         // 缓存操作完成
);

// ====================== 内部参数/宏定义 ======================
localparam CACHE_ROW_WIDTH    = 128;        // 缓存行宽度（128位）
localparam INDEX_WIDTH        = 8;          // 索引位宽（256组）
localparam TAG_WIDTH          = 20;         // 标签位宽（31:12）
localparam OFFSET_WIDTH       = 4;          // 偏移位宽（11:4索引，3:0偏移）
localparam WAY_CNT            = 2;          // 路数（2路组相联）
localparam REPLACE_WAY_WIDTH  = 1;          // 替换路数位宽
localparam REFILL_CNT_WIDTH   = 2;          // 填充计数位宽（4个32位字）

// 状态机定义（与ICache对齐，适配读写操作）
localparam DCACHE_IDLE        = 3'b001;     // 空闲状态
localparam DCACHE_LOOKUP      = 3'b010;     // 查找状态（读/写命中判断）
localparam DCACHE_REFILL      = 3'b100;     // 填充状态（读缺失）
localparam DCACHE_WRITEBACK   = 3'b101;     // 写回状态（写缺失，替换脏行）

// 写选通生成参数（根据访问大小）
localparam STRB_BYTE          = 4'b0001;    // 字节写选通
localparam STRB_HALFWORD      = 4'b0011;    // 半字写选通
localparam STRB_WORD          = 4'b1111;    // 字写选通

// ====================== 内部信号定义 ======================
// 地址拆分（与ICache一致，适配32位地址）
wire [TAG_WIDTH-1:0]          tag;            // 标签（地址[31:12]）
wire [INDEX_WIDTH-1:0]        index;          // 索引（地址[11:4]）
wire [OFFSET_WIDTH-1:0]       offset;         // 偏移（地址[3:0]）
wire [OFFSET_WIDTH-2:0]       word_offset;    // 字偏移（地址[3:2]，128位行内4个32位字）
wire [1:0]                    byte_offset;    // 字节偏移（地址[1:0]）

// 缓存存储体（2路，含有效位、脏位、标签、数据）
reg [CACHE_ROW_WIDTH-1:0]     data_way0[0:(1<<INDEX_WIDTH)-1];  // Way0数据存储
reg [CACHE_ROW_WIDTH-1:0]     data_way1[0:(1<<INDEX_WIDTH)-1];  // Way1数据存储
reg [TAG_WIDTH-1:0]           tag_way0[0:(1<<INDEX_WIDTH)-1];   // Way0标签
reg [TAG_WIDTH-1:0]           tag_way1[0:(1<<INDEX_WIDTH)-1];   // Way1标签
reg                           valid_way0[0:(1<<INDEX_WIDTH)-1];  // Way0有效位
reg                           valid_way1[0:(1<<INDEX_WIDTH)-1];  // Way1有效位
reg                           dirty_way0[0:(1<<INDEX_WIDTH)-1];  // Way0脏位（写过未写回）
reg                           dirty_way1[0:(1<<INDEX_WIDTH)-1];  // Way1脏位

// LRU状态（与ICache一致，每组1位）
reg                           lru_bit[0:(1<<INDEX_WIDTH)-1];     // 0=Way0为LRU，1=Way1为LRU

// 命中检测
reg [WAY_CNT-1:0]             way_hit;        // 各路命中标记（0=Way0，1=Way1）
reg                           cache_hit;      // 缓存命中（任意一路命中）
reg                           hit_way;        // 命中路（0=Way0，1=Way1）

// 状态机
reg [2:0]                     dcache_state;   // 当前状态
reg [2:0]                     next_state;     // 下一状态

// 替换策略（LRU，优先替换无效路）
reg [REPLACE_WAY_WIDTH-1:0]   replace_way;    // 选中的替换路
reg                           has_invalid_way;// 是否存在无效路
reg [REPLACE_WAY_WIDTH-1:0]   invalid_way;    // 无效路

// 填充/写回相关
reg [REFILL_CNT_WIDTH-1:0]    refill_cnt;     // 填充计数（0~3，4个32位字）
reg [CACHE_ROW_WIDTH-1:0]     refill_buffer;  // 填充缓冲区（暂存AXI读数据）
reg [REFILL_CNT_WIDTH-1:0]    wback_cnt;      // 写回计数（0~3，4个32位字）
reg [CACHE_ROW_WIDTH-1:0]     wback_buffer;   // 写回缓冲区（暂存要写回的缓存行）
reg [`PC_WIDTH-1:0]           req_addr_reg;   // 锁存请求地址
reg                           req_we_reg;     // 锁存请求写使能
reg [31:0]                    req_wdata_reg;  // 锁存请求写数据
reg [1:0]                     req_size_reg;   // 锁存请求访问大小
reg                           req_valid_reg;  // 锁存请求有效
reg                           uncache_reg;    // 锁存非缓存访问标记

// 写选通信号
reg [3:0]                     wstrb;          // 写选通（字节使能）
reg [31:0]                    aligned_wdata;  // 对齐后的写数据（适配缓存行）

// ====================== 地址拆分 ======================
assign tag          = dcache_addr[31:(INDEX_WIDTH + OFFSET_WIDTH)];
assign index        = dcache_addr[(INDEX_WIDTH + OFFSET_WIDTH - 1):OFFSET_WIDTH];
assign offset       = dcache_addr[OFFSET_WIDTH-1:0];
assign word_offset  = offset[3:2];  // 128位行内的32位字偏移（0~3）
assign byte_offset  = offset[1:0];  // 32位字内的字节偏移（0~3）

// ====================== 命中检测 ======================
always @(*) begin
    // Way0命中：有效位为1 + 标签匹配
    way_hit[0] = valid_way0[index] && (tag_way0[index] == tag);
    // Way1命中：有效位为1 + 标签匹配
    way_hit[1] = valid_way1[index] && (tag_way1[index] == tag);
    // 缓存命中：任意一路命中 且 非缓存操作/非非缓存访问
    cache_hit = (|way_hit) && !dcacop_op_en && !uncache_en;
    // 命中路判断
    hit_way = way_hit[1] ? 1'b1 : 1'b0;
end

// ====================== LRU替换策略（与ICache一致） ======================
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

// 2. LRU状态更新（命中时更新，标记命中路为"最近使用"）
integer i;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 复位时LRU位初始化为0（Way0为LRU）
        for (i = 0; i < (1<<INDEX_WIDTH); i = i + 1) begin
            lru_bit[i]<= 1'b0;
        end
    end else if (dcache_state == DCACHE_LOOKUP && cache_hit) begin
        // Way0命中 → 标记Way1为LRU（lru_bit=1）
        if (way_hit[0]) begin
            lru_bit[index] <= 1'b1;
        end
        // Way1命中 → 标记Way0为LRU（lru_bit=0）
        else if (way_hit[1]) begin
            lru_bit[index] <= 1'b0;
        end
    end else if (dcache_state == DCACHE_LOOKUP && dcacop_op_en) begin
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

// ====================== AXI接口信号生成 ======================
// 读地址（缓存行起始地址，对齐到128位）
assign axi_araddr = {req_addr_reg[31:4], 4'b0};
// 写地址（缓存行起始地址，对齐到128位）
assign axi_awaddr = {req_addr_reg[31:4], 4'b0};
// AXI保护属性（数据访问，特权级0，普通访问）
assign axi_arprot = 3'b010;
assign axi_awprot = 3'b010;
// 读数据就绪（始终就绪）
assign axi_rready = 1'b1;
// 写数据（来自写回缓冲区或请求写数据）
assign axi_wdata = (dcache_state == DCACHE_WRITEBACK) ? wback_buffer[wback_cnt*32 + 31 -: 32] : aligned_wdata;
// 写选通（根据访问大小生成）
assign axi_wstrb = (dcache_state == DCACHE_WRITEBACK) ? STRB_WORD : wstrb;

// ====================== 写选通与写数据对齐 ======================
always @(*) begin
    // 写选通生成（根据访问大小和字节偏移）
    case (req_size_reg)
        2'b01: begin  // 字节访问
            case (byte_offset)
                2'b00: wstrb = STRB_BYTE << 0;
                2'b01: wstrb = STRB_BYTE << 1;
                2'b10: wstrb = STRB_BYTE << 2;
                2'b11: wstrb = STRB_BYTE << 3;
                default: wstrb = STRB_BYTE;
            endcase
        end
        2'b10: begin  // 半字访问（对齐到2字节）
            wstrb = (byte_offset[1] == 1'b0) ? STRB_HALFWORD << 0 : STRB_HALFWORD << 2;
        end
        2'b00: begin  // 字访问（对齐到4字节）
            wstrb = STRB_WORD;
        end
        default: wstrb = STRB_WORD;
    endcase

    // 写数据对齐（将32位写数据放到缓存行对应位置）
    aligned_wdata = req_wdata_reg;
    case (word_offset)
        2'b01: aligned_wdata = req_wdata_reg << 32;
        2'b10: aligned_wdata = req_wdata_reg << 64;
        2'b11: aligned_wdata = req_wdata_reg << 96;
        default: aligned_wdata = req_wdata_reg;
    endcase
end

// ====================== 状态机控制 ======================
// 1. 状态寄存器更新
always @(posedge clk or posedge reset) begin
    if (reset) begin
        dcache_state <= DCACHE_IDLE;
    end else begin
        dcache_state <= next_state;
    end
end

// 2. 下一状态逻辑（适配读写操作，与ICache状态机对齐）
always @(*) begin
    next_state = dcache_state;
    case (dcache_state)
        DCACHE_IDLE: begin
            // 空闲状态：有访存请求/缓存操作请求则进入查找状态
            if ((dcache_req && !core_stall) || dcacop_op_en) begin
                next_state = DCACHE_LOOKUP;
            end
        end
        DCACHE_LOOKUP: begin
            // 查找状态：
            if (tlb_excp_cancel_req || dcacop_op_en) begin
                // TLB异常/缓存操作 → 返回空闲
                next_state = DCACHE_IDLE;
            end else if (uncache_en) begin
                // 非缓存访问 → 读/写直接走AXI，无需填充
                next_state = DCACHE_IDLE;
            end else if (!cache_hit && dcache_req) begin
                // 缓存缺失：写操作且替换路脏 → 先写回，再填充；否则直接填充
                if (req_we_reg && ((replace_way == 1'b0 && dirty_way0[index]) || (replace_way == 1'b1 && dirty_way1[index]))) begin
                    next_state = DCACHE_WRITEBACK;
                end else begin
                    next_state = DCACHE_REFILL;
                end
            end else begin
                // 缓存命中 → 完成读写，返回空闲
                next_state = DCACHE_IDLE;
            end
        end
        DCACHE_REFILL: begin
            // 填充状态：AXI读完成（rlast）/异常取消 → 返回空闲
            if (tlb_excp_cancel_req || (axi_rvalid && axi_rlast)) begin
                next_state = DCACHE_IDLE;
            end
        end
        DCACHE_WRITEBACK: begin
            // 写回状态：AXI写完成（bvalid） → 进入填充状态
            if (axi_bvalid) begin
                next_state = DCACHE_REFILL;
            end
        end
        default: begin
            next_state = DCACHE_IDLE;
        end
    endcase
end

// ====================== 状态机输出逻辑 ======================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 复位初始化
        dcache_ack        <= 1'b0;
        dcache_rdata      <= 32'b0;
        dcache_miss       <= 1'b0;
        dcache_unbusy     <= 1'b1;
        axi_arvalid       <= 1'b0;
        axi_awvalid       <= 1'b0;
        axi_wvalid        <= 1'b0;
        refill_cnt        <= 2'b0;
        refill_buffer     <= 128'b0;
        wback_cnt         <= 2'b0;
        wback_buffer      <= 128'b0;
        req_addr_reg      <= 32'h80000000; // 复位地址，与流水线一致
        req_we_reg        <= 1'b0;
        req_wdata_reg     <= 32'b0;
        req_size_reg      <= 2'b00;
        req_valid_reg     <= 1'b0;
        uncache_reg       <= 1'b0;
        cache_miss_cnt_en <= 1'b0;
        dcacop_done       <= 1'b0;

        // 缓存存储体初始化（有效位、脏位清零，标签、数据置0）
        for (i = 0; i < (1<<INDEX_WIDTH); i = i + 1) begin
            valid_way0[i] <= 1'b0;
            valid_way1[i] <= 1'b0;
            dirty_way0[i] <= 1'b0;
            dirty_way1[i] <= 1'b0;
            tag_way0[i]   <= {TAG_WIDTH{1'b0}};
            tag_way1[i]   <= {TAG_WIDTH{1'b0}};
            data_way0[i]  <= {CACHE_ROW_WIDTH{1'b0}};
            data_way1[i]  <= {CACHE_ROW_WIDTH{1'b0}};
        end
    end else begin
        // 默认值（避免锁存器）
        dcache_ack        <= 1'b0;
        dcache_miss       <= 1'b0;
        dcacop_done       <= 1'b0;
        cache_miss_cnt_en <= 1'b0;
        axi_arvalid       <= 1'b0;
        axi_awvalid       <= 1'b0;
        axi_wvalid        <= 1'b0;

        case (dcache_state)
            DCACHE_IDLE: begin
                dcache_unbusy <= 1'b1;
                // 锁存请求信号（访存请求/缓存操作请求）
                if ((dcache_req && !core_stall) || dcacop_op_en) begin
                    req_addr_reg  <= dcacop_op_en ? cacop_op_addr : dcache_addr;
                    req_we_reg<= dcacop_op_en ? 1'b0 : dcache_we;
                    req_wdata_reg <= dcache_wdata;
                    req_size_reg  <= dcache_size;
                    req_valid_reg <= 1'b1;
                    uncache_reg   <= uncache_en;
                end else begin
                    req_valid_reg <= 1'b0;
                    uncache_reg   <= 1'b0;
                end
            end

            DCACHE_LOOKUP: begin
                dcache_unbusy <= 1'b0;
                if (tlb_excp_cancel_req) begin
                    // TLB异常取消 → 无响应，清空锁存信号
                    dcache_ack <= 1'b0;
                    req_valid_reg <= 1'b0;
                end else if (dcacop_op_en) begin
                    // 缓存操作（无效化/写回）
                    case (cacop_op_mode)
                        2'b00: begin  // 无效化指定路
                            if (replace_way == 1'b0) begin
                                valid_way0[index] <= 1'b0;
                                dirty_way0[index] <= 1'b0; // 无效化后脏位清零
                            end else begin
                                valid_way1[index] <= 1'b0;
                                dirty_way1[index] <= 1'b0;
                            end
                        end
                        2'b01: begin  // 无效化整个组
                            valid_way0[index] <= 1'b0;
                            valid_way1[index] <= 1'b0;
                            dirty_way0[index] <= 1'b0;
                            dirty_way1[index] <= 1'b0;
                        end
                        2'b10: begin  // 写回指定路
                            if (replace_way == 1'b0 && valid_way0[index] && dirty_way0[index]) begin
                                wback_buffer <= data_way0[index];
                                axi_awvalid  <= 1'b1;
                                wback_cnt    <= 2'b0;
                            end else if (replace_way == 1'b1 && valid_way1[index] && dirty_way1[index]) begin
                                wback_buffer <= data_way1[index];
                                axi_awvalid  <= 1'b1;
                                wback_cnt    <= 2'b0;
                            end
                        end
                    endcase
                    dcacop_done <= 1'b1;
                end else if (uncache_en) begin
                    // 非缓存访问：直接走AXI，不经过缓存
                    if (req_we_reg) begin
                        // 非缓存写：发起AXI写
                        axi_awvalid <= 1'b1;
                        axi_wvalid  <= 1'b1;
                        if (axi_awready && axi_wready) begin
                            dcache_ack <= 1'b1;
                        end
                    end else begin
                        // 非缓存读：发起AXI读
                        axi_arvalid <= 1'b1;
                        dcache_miss <= 1'b1;
                        if (axi_rvalid) begin
                            dcache_ack  <= 1'b1;
                            dcache_rdata <= axi_rdata;
                        end
                    end
                end else if (cache_hit) begin
                    // 缓存命中：处理读/写操作
                    dcache_ack <= 1'b1;
                    if (req_we_reg) begin
                        // 写操作：更新缓存数据，置位脏位
                        case (hit_way)
                            1'b0: begin
                                // 按写选通更新Way0数据
                                case (word_offset)
                                    2'b00: data_way0[index][31:0]   <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way0[index][31:0]);
                                    2'b01: data_way0[index][63:32]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way0[index][63:32]);
                                    2'b10: data_way0[index][95:64]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way0[index][95:64]);
                                    2'b11: data_way0[index][127:96] <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way0[index][127:96]);
                                endcase
                                dirty_way0[index] <= 1'b1; // 写操作置脏
                            end
                            1'b1: begin
                                // 按写选通更新Way1数据
                                case (word_offset)
                                    2'b00: data_way1[index][31:0]   <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way1[index][31:0]);
                                    2'b01: data_way1[index][63:32]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way1[index][63:32]);
                                    2'b10: data_way1[index][95:64]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way1[index][95:64]);
                                    2'b11: data_way1[index][127:96] <= (wstrb & aligned_wdata[31:0]) | (~wstrb & data_way1[index][127:96]);
                                endcase
                                dirty_way1[index] <= 1'b1; // 写操作置脏
                            end
                        endcase
                    end else begin
                        // 读操作：返回命中路的对应数据
                        if (hit_way == 1'b0) begin
                            case (word_offset)
                                2'b00: dcache_rdata <= data_way0[index][31:0];
                                2'b01: dcache_rdata <= data_way0[index][63:32];
                                2'b10: dcache_rdata <= data_way0[index][95:64];
                                2'b11: dcache_rdata <= data_way0[index][127:96];
                            endcase
                        end else begin
                            case (word_offset)
                                2'b00: dcache_rdata <= data_way1[index][31:0];
                                2'b01: dcache_rdata <= data_way1[index][63:32];
                                2'b10: dcache_rdata <= data_way1[index][95:64];
                                2'b11: dcache_rdata <= data_way1[index][127:96];
                            endcase
                        end
                    end
                end else begin
                    // 缓存缺失：发起AXI读（填充），计数使能
                    axi_arvalid <= 1'b1;
                    dcache_miss <= 1'b1;
                    cache_miss_cnt_en <= 1'b1;
                end
            end

            DCACHE_REFILL: begin
                dcache_unbusy <= 1'b0;
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
                        2'b10: refill_buffer[95:64]<= axi_rdata;
                        2'b11: refill_buffer[127:96]<= axi_rdata;
                    endcase
                    // 最后一拍数据 → 写入缓存存储体（替换路）
                    if (axi_rlast) begin
                        if (replace_way == 1'b0) begin
                            data_way0[index]  <= refill_buffer;
                            tag_way0[index]   <= tag;
                            valid_way0[index] <= 1'b1;
                            dirty_way0[index] <= req_we_reg; // 填充时若为写请求，置脏
                        end else begin
                            data_way1[index]  <= refill_buffer;
                            tag_way1[index]   <= tag;
                            valid_way1[index] <= 1'b1;
                            dirty_way1[index] <= req_we_reg;
                        end
                        // 若为读请求，返回数据；若为写请求，完成写操作
                        dcache_ack <= 1'b1;
                        if (!req_we_reg) begin
                            case (word_offset)
                                2'b00: dcache_rdata <= refill_buffer[31:0];
                                2'b01: dcache_rdata <= refill_buffer[63:32];
                                2'b10: dcache_rdata <= refill_buffer[95:64];
                                2'b11: dcache_rdata <= refill_buffer[127:96];
                            endcase
                        end else begin
                            // 填充后完成写操作（更新对应位置数据）
                            case (replace_way)
                                1'b0: begin
                                    case (word_offset)
                                        2'b00: data_way0[index][31:0]   <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[31:0]);
                                        2'b01: data_way0[index][63:32]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[63:32]);
                                        2'b10: data_way0[index][95:64]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[95:64]);
                                        2'b11: data_way0[index][127:96] <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[127:96]);
                                    endcase
                                end
                                1'b1: begin
                                    case (word_offset)
                                        2'b00: data_way1[index][31:0]   <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[31:0]);
                                        2'b01: data_way1[index][63:32]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[63:32]);
                                        2'b10: data_way1[index][95:64]  <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[95:64]);
                                        2'b11: data_way1[index][127:96] <= (wstrb & aligned_wdata[31:0]) | (~wstrb & refill_buffer[127:96]);
                                    endcase
                                end
                            endcase
                        end
                        refill_cnt <= 2'b0;
                    end
                end
                // TLB异常取消 → 撤销AXI请求，清空填充计数
                if (tlb_excp_cancel_req) begin
                    axi_arvalid <= 1'b0;
                    refill_cnt  <= 2'b0;
                end
            end

            DCACHE_WRITEBACK: begin
                dcache_unbusy <= 1'b0;
                // AXI写地址握手完成后，撤销写地址请求
                if (axi_awvalid && axi_awready) begin
                    axi_awvalid <= 1'b0;
                end
                // 写地址就绪后，发送写数据
                if (!axi_awvalid && wback_cnt < 2'b11) begin
                    axi_wvalid <= 1'b1;
                    if (axi_wready) begin
                        wback_cnt <= wback_cnt + 1'b1;
                    end
                end else if (wback_cnt == 2'b11 && axi_wready) begin
                    axi_wvalid <= 1'b0;
                    wback_cnt <= 2'b0;
                end
                // 写响应完成 → 清空替换路脏位
                if (axi_bvalid) begin
                    if (replace_way == 1'b0) begin
                        dirty_way0[index]<= 1'b0;
                    end else begin
                        dirty_way1[index] <= 1'b0;
                    end
                end
                // TLB异常取消 → 撤销AXI写请求，清空写回计数
                if (tlb_excp_cancel_req) begin
                    axi_awvalid <= 1'b0;
                    axi_wvalid  <= 1'b0;
                    wback_cnt   <= 2'b0;
                end
            end
        endcase
    end
end

endmodule