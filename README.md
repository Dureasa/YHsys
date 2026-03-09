# YHsys（银河sys） -- 国防科技大学全栈教学计算机系统

YHSys 是一套全栈自研的极简计算机系统，覆盖「RISC-V 32 位 CPU（硬件）+ 类 Unix 操作系统（内核）+ C 语言编译器（工具链）」三大核心模块，目标是从零实现 “高级语言 → 编译器 → 操作系统 → 自研 CPU 执行” 的全链路闭环，特别适用于计算机系统底层原理教学与全栈开发实践。

教I应用
### 适用课程
- 计算机组成原理
- 操作系统原理
- 编译原理
- 计算机系统综合设计

### 实验体系
```mermaid
graph LR
    A[数字逻辑实验] --> B[CPU设计]
    B --> C[指令集验证]
    C --> D[编译器开发]
    D --> E[操作系统移植]
```

## 快速开始
```bash
# 克隆项目
git clone https://github.com/NUDT-YHsys/YHsys.git

# 构建系统（需要RISC-V工具链）
make all

# 在模拟器运行教学案例
make run-teaching-demo
```

## 教学资源
- [实验指导手册](docs/LAB_GUIDE.md)
- [教学课件](docs/SLIDES/)
- [参考实现视频](docs/VIDEOS/)

## 如何参与
我们欢迎教育工作者和学生的贡献！请参考：
- [教学案例贡献指南](docs/TEACHING_CONTRIB.md)
- [问题追踪](https://github.com/NUDT-YHsys/YHsys/issues) - 报告教学相关BUG或提出改进建议

## 许可协议
本项目采用**GPL-3.0许可证**，详见[LICENSE](LICENSE)文件，教育使用请遵循相关条款。