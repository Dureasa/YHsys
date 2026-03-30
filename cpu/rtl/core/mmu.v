
module mmu(
/*
 * RV32 Sv32 MMU 模块
 * 功能：虚拟地址(VA) -> 物理地址(PA) 转换，权限检查，缺页异常
 * 页大小：4KB，两级页表，RISC-V特权架构标准
 */

    // 时钟与复位
    input  wire        clk,
    input  wire        rst_n,
    
    // 处理器核心接口
    input  wire [31:0] va,           // 输入虚拟地址
    input  wire        inst_en,      // 指令取指访问使能
    input  wire        load_en,      // 数据加载访问使能
    input  wire        store_en,     // 数据存储访问使能
    input  wire [1:0]  priv_mode,    // 特权模式 00=用户U 01=监督者S 11=机器M
    
    // 内存控制器接口（读取页表）
    output reg  [31:0] pt_raddr,     // 页表读取地址
    input  wire [31:0] pt_rdata,     // 页表读取数据
    input  wire        pt_ready,     // 页表读取完成
    
    // 控制寄存器接口
    input  wire [31:0] satp,         // SATP寄存器（Sv32使能+根页表基地址）
    
    // MMU输出结果
    output reg  [31:0] pa,           // 输出物理地址
    output reg         mmu_ready,    // 转换完成
    output reg         mmu_fault,    // 转换异常（缺页/权限错误）
    output reg  [3:0]  fault_cause   // 异常原因
);

// ==================== 常量定义 ====================
localparam PAGE_OFFSET_WIDTH = 12;   // 4KB页偏移
localparam VPN_WIDTH         = 10;   // 虚拟页号宽度
localparam PTE_WIDTH         = 32;   // 页表项宽度
localparam PAGE_SIZE         = 1 << PAGE_OFFSET_WIDTH; // 4096字节

// 页表项(PTE)位定义（RISC-V Sv32标准）
localparam PTE_V      = 0;  // 有效位
localparam PTE_R      = 1;  // 可读位
localparam PTE_W      = 2;  // 可写位
localparam PTE_X      = 3;  // 可执行位
localparam PTE_U      = 4;  // 用户可访问位
localparam PTE_PPN_H  = 31; // 物理页号高位
localparam PTE_PPN_L  = 10; // 物理页号低位

// 异常原因编码
localparam CAUSE_INSTR_PAGE_FAULT = 4'd1;  // 指令缺页
localparam CAUSE_LOAD_PAGE_FAULT  = 4'd2;  // 加载缺页
localparam CAUSE_STORE_PAGE_FAULT = 4'd3;  // 存储缺页
localparam CAUSE_PERM_FAULT       = 4'd4;  // 权限错误

// 特权模式编码
localparam PRIV_U = 2'b00; // 用户模式
localparam PRIV_S = 2'b01; // 监督者模式
localparam PRIV_M = 2'b11; // 机器模式

// ==================== 内部信号 ====================
// 虚拟地址拆分
wire [VPN_WIDTH-1:0] va_vpn1;
wire [VPN_WIDTH-1:0] va_vpn0;
wire [PAGE_OFFSET_WIDTH-1:0] va_offset;

// SATP寄存器拆分
wire        mmu_enable;  // MMU使能（satp.mode=1=Sv32）
wire [21:0] satp_ppn;    // 根页表物理页号

// 页表项
reg  [PTE_WIDTH-1:0] pte1;  // 第一级页表项
reg  [PTE_WIDTH-1:0] pte0;  // 第二级页表项

// 状态机
reg [2:0] current_state;
reg [2:0] next_state;

localparam IDLE        = 3'd0; // 空闲
localparam READ_PTE1   = 3'd1; // 读取第一级页表
localparam CHECK_PTE1  = 3'd2; // 检查第一级页表项
localparam READ_PTE0   = 3'd3; // 读取第二级页表
localparam CHECK_PTE0  = 3'd4; // 检查第二级页表项
localparam TRANSLATE   = 3'd5; // 地址转换完成
localparam FAULT       = 3'd6; // 异常处理

// ==================== 地址拆分 ====================
// 虚拟地址拆分
assign va_vpn1   = va[31:22];
assign va_vpn0   = va[21:12];
assign va_offset = va[11:0];

// SATP寄存器解析（Sv32：mode[31:30]=01启用MMU）
assign mmu_enable = (satp[31:30] == 2'b01);
assign satp_ppn   = satp[21:0];

// ==================== 状态机时序逻辑 ====================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// ==================== 状态机组合逻辑 ====================
always @(*) begin
    next_state = current_state;
    case(current_state)
        IDLE: begin
            // 有访问请求且MMU使能，开始转换
            if((inst_en || load_en || store_en) && mmu_enable)
                next_state = READ_PTE1;
            // MMU关闭，直接直通地址
            else if((inst_en || load_en || store_en) && !mmu_enable)
                next_state = TRANSLATE;
        end
        
        READ_PTE1: begin
            // 等待页表读取完成
            if(pt_ready) next_state = CHECK_PTE1;
        end
        
        CHECK_PTE1: begin
            // PTE1无效 → 缺页
            if(!pt_rdata[PTE_V]) next_state = FAULT;
            // PTE1是叶子节点 → 直接转换
            else if(pt_rdata[PTE_R] || pt_rdata[PTE_X]) next_state = TRANSLATE;
            // PTE1是页表指针 → 读取PTE0
            else next_state = READ_PTE0;
        end
        
        READ_PTE0: begin
            if(pt_ready) next_state = CHECK_PTE0;
        end
        
        CHECK_PTE0: begin
            if(!pt_rdata[PTE_V]) next_state = FAULT;
            else next_state = TRANSLATE;
        end
        
        TRANSLATE: next_state = IDLE;
        
        FAULT: next_state = IDLE;
    endcase
end

// ==================== 地址转换与控制逻辑 ====================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pa <= 32'd0;
        pt_raddr <= 32'd0;
        mmu_ready <= 1'b0;
        mmu_fault <= 1'b0;
        fault_cause <= 4'd0;
        pte1 <= 32'd0;
        pte0 <= 32'd0;
    end
    else begin
        case(current_state)
            IDLE: begin
                mmu_ready <= 1'b0;
                mmu_fault <= 1'b0;
                fault_cause <= 4'd0;
                // MMU关闭：虚拟地址=物理地址（直通模式）
                if(!mmu_enable && (inst_en || load_en || store_en)) begin
                    pa <= va;
                    mmu_ready <= 1'b1;
                end
            end
            
            // 读取第一级页表：根页表地址 = satp_ppn << 12 | vpn1 << 2
            READ_PTE1: begin
                pt_raddr <= {satp_ppn, 12'b0} + {va_vpn1, 2'b0};
            end
            
            CHECK_PTE1: begin
                pte1 <= pt_rdata;
            end
            
            // 读取第二级页表：pte1.ppn << 12 | vpn0 << 2
            READ_PTE0: begin
                pt_raddr <= {pte1[31:10], 12'b0} + {va_vpn0, 2'b0};
            end
            
            CHECK_PTE0: begin
                pte0 <= pt_rdata;
            end
            
            TRANSLATE: begin
                mmu_ready <= 1'b1;
                // 权限检查 + 物理地址生成
                if(pte0[PTE_V]) begin
                    // 物理地址 = PPN << 12 | 页内偏移
                    pa <= {pte0[31:10], va_offset};
                    // 权限校验
                    if(inst_en && !pte0[PTE_X]) begin // 指令执行无权限
                        mmu_fault <= 1'b1;
                        fault_cause <= CAUSE_PERM_FAULT;
                    end
                    else if(load_en && !pte0[PTE_R]) begin // 加载无权限
                        mmu_fault <= 1'b1;
                        fault_cause <= CAUSE_PERM_FAULT;
                    end
                    else if(store_en && !pte0[PTE_W]) begin // 存储无权限
                        mmu_fault <= 1'b1;
                        fault_cause <= CAUSE_PERM_FAULT;
                    end
                    else if(priv_mode == PRIV_U && !pte0[PTE_U]) begin // 用户访问内核页
                        mmu_fault <= 1'b1;
                        fault_cause <= CAUSE_PERM_FAULT;
                    end
                end
                else begin // 页表项无效 → 缺页异常
                    mmu_fault <= 1'b1;
                    fault_cause <= inst_en ? CAUSE_INSTR_PAGE_FAULT :
                                  load_en  ? CAUSE_LOAD_PAGE_FAULT :
                                  CAUSE_STORE_PAGE_FAULT;
                end
            end
            
            FAULT: begin
                mmu_ready <= 1'b1;
                mmu_fault <= 1'b1;
            end
        endcase
    end
end

endmodule