.RECIPEPREFIX := >

K = kernel
U = user

BUILD  = out
OBJDIR = $(BUILD)/obj
BINDIR = $(BUILD)/bin
ASMDIR = $(BUILD)/asm
SYMDIR = $(BUILD)/sym
MAPDIR = $(BUILD)/map
IMGDIR = $(BUILD)/img
GENDIR = $(BUILD)/gen

KERNEL_ELF = $(BINDIR)/kernel/yhsys-kernel.elf
KERNEL_MAP = $(MAPDIR)/kernel/yhsys-kernel.map
KERNEL_ASM = $(ASMDIR)/kernel/yhsys-kernel.asm
KERNEL_SYM = $(SYMDIR)/kernel/yhsys-kernel.sym

FSIMG     = $(IMGDIR)/fs-system.img
MKFS_HOST = $(BINDIR)/host/mkfs
USYS_GEN  = $(GENDIR)/usys.S
USYS_OBJ  = $(OBJDIR)/user/usys.o

# riscv64-unknown-elf- or riscv64-linux-gnu-
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if riscv64-unknown-elf-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
 then echo 'riscv64-unknown-elf-'; \
 elif riscv64-elf-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
 then echo 'riscv64-elf-'; \
 elif riscv64-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
 then echo 'riscv64-linux-gnu-'; \
 elif riscv64-unknown-linux-gnu-objdump -i 2>&1 | grep 'elf64-big' >/dev/null 2>&1; \
 then echo 'riscv64-unknown-linux-gnu-'; \
 else echo "***" 1>&2; \
 echo "*** Error: Couldn't find a riscv64 version of GCC/binutils." 1>&2; \
 echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
 echo "***" 1>&2; exit 1; fi)
endif
$(info $(TOOLPREFIX))

QEMU = qemu-system-riscv32
MIN_QEMU_VERSION = 7.2

CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump

CFLAGS = -Wall -Werror -Wno-unknown-attributes -O -fno-omit-frame-pointer -ggdb -gdwarf-2
CFLAGS += -march=rv32gc
CFLAGS += -mabi=ilp32
CFLAGS += -mcmodel=medany
CFLAGS += -ffreestanding
CFLAGS += -fno-common -nostdlib
CFLAGS += -fno-builtin-strncpy -fno-builtin-strncmp -fno-builtin-strlen -fno-builtin-memset
CFLAGS += -fno-builtin-memmove -fno-builtin-memcmp -fno-builtin-log -fno-builtin-bzero
CFLAGS += -fno-builtin-strchr -fno-builtin-exit -fno-builtin-malloc -fno-builtin-putc
CFLAGS += -fno-builtin-free -fno-builtin-memcpy -Wno-main
CFLAGS += -fno-builtin-printf -fno-builtin-fprintf -fno-builtin-vprintf
CFLAGS += -I.
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)

ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
endif
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

DEPFLAGS = -MMD -MP
LDFLAGS = -z max-page-size=4096 -m elf32lriscv

KERNEL_C_SRCS = \
$(K)/start.c \
$(K)/console.c \
$(K)/printf.c \
$(K)/uart.c \
$(K)/kalloc.c \
$(K)/spinlock.c \
$(K)/string.c \
$(K)/bootflow.c \
$(K)/addrspace.c \
$(K)/taskmgr.c \
$(K)/irqtrap.c \
$(K)/syscall_gate.c \
$(K)/sysproc.c \
$(K)/sysfile.c \
$(K)/bio.c \
$(K)/fs.c \
$(K)/log.c \
$(K)/sleeplock.c \
$(K)/file.c \
$(K)/pipe.c \
$(K)/loader_exec.c \
$(K)/plic.c \
$(K)/virtio_disk.c

KERNEL_S_SRCS = \
$(K)/entry.S \
$(K)/swtch.S \
$(K)/trampoline.S \
$(K)/kernelvec.S

KERNEL_C_OBJS = $(patsubst $(K)/%.c,$(OBJDIR)/kernel/%.o,$(KERNEL_C_SRCS))
KERNEL_S_OBJS = $(patsubst $(K)/%.S,$(OBJDIR)/kernel/%.o,$(KERNEL_S_SRCS))
KERNEL_OBJS = $(KERNEL_C_OBJS) $(KERNEL_S_OBJS)

ULIB_SRCS = $(U)/ulib.c $(U)/printf.c $(U)/umalloc.c $(U)/div64.c
ULIB_OBJS = $(patsubst $(U)/%.c,$(OBJDIR)/user/%.o,$(ULIB_SRCS))

USER_APPS = \
cat banner echo forktest grep guess init kill ln ls mkdir rm rps sh usertests wc logstress forphan dorphan

USER_APP_OBJS = $(addprefix $(OBJDIR)/user/,$(addsuffix .o,$(USER_APPS)))
USER_BINS = $(addprefix $(BINDIR)/user/_,$(USER_APPS))

.SECONDARY: $(KERNEL_OBJS) $(ULIB_OBJS) $(USER_APP_OBJS) $(USYS_OBJ)

all: $(KERNEL_ELF) $(FSIMG)

$(KERNEL_ELF): $(KERNEL_OBJS) $(K)/kernel.ld
>mkdir -p $(dir $@) $(dir $(KERNEL_MAP)) $(dir $(KERNEL_ASM)) $(dir $(KERNEL_SYM))
>$(LD) $(LDFLAGS) -Map $(KERNEL_MAP) -T $(K)/kernel.ld -o $@ $(KERNEL_OBJS)
>$(OBJDUMP) -S $@ > $(KERNEL_ASM)
>$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(KERNEL_SYM)

$(OBJDIR)/kernel/%.o: $(K)/%.c
>mkdir -p $(dir $@)
>$(CC) $(CFLAGS) $(DEPFLAGS) -c -o $@ $<

$(OBJDIR)/kernel/%.o: $(K)/%.S
>mkdir -p $(dir $@)
>$(CC) -march=rv32gc -mabi=ilp32 -g $(DEPFLAGS) -c -o $@ $<

$(USYS_GEN): $(U)/usys.pl
>mkdir -p $(dir $@)
>perl $< > $@

$(USYS_OBJ): $(USYS_GEN)
>mkdir -p $(dir $@)
>$(CC) $(CFLAGS) $(DEPFLAGS) -c -o $@ $<

$(OBJDIR)/user/usertests.o: $(U)/usertests.c
>mkdir -p $(dir $@)
>$(CC) $(CFLAGS) $(DEPFLAGS) -Wno-int-to-pointer-cast -Wno-pointer-to-int-cast -Wno-overflow -c -o $@ $<

$(OBJDIR)/user/forphan.o: $(U)/orphan_keeper.c
>mkdir -p $(dir $@)
>$(CC) $(CFLAGS) $(DEPFLAGS) -c -o $@ $<

$(OBJDIR)/user/dorphan.o: $(U)/orphan_keeper.c
>mkdir -p $(dir $@)
>$(CC) $(CFLAGS) $(DEPFLAGS) -c -o $@ $<

$(OBJDIR)/user/%.o: $(U)/%.c
>mkdir -p $(dir $@)
>$(CC) $(CFLAGS) $(DEPFLAGS) -c -o $@ $<

$(BINDIR)/user/_%: $(OBJDIR)/user/%.o $(ULIB_OBJS) $(USYS_OBJ) $(U)/user.ld
>mkdir -p $(dir $@) $(ASMDIR)/user $(SYMDIR)/user
>$(LD) $(LDFLAGS) -T $(U)/user.ld -o $@ $< $(ULIB_OBJS) $(USYS_OBJ)
>$(OBJDUMP) -S $@ > $(ASMDIR)/user/$*.asm
>$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(SYMDIR)/user/$*.sym

$(BINDIR)/user/_forktest: $(OBJDIR)/user/forktest.o $(OBJDIR)/user/ulib.o $(USYS_OBJ)
>mkdir -p $(dir $@) $(ASMDIR)/user $(SYMDIR)/user
>$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $^
>$(OBJDUMP) -S $@ > $(ASMDIR)/user/forktest.asm
>$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(SYMDIR)/user/forktest.sym

$(MKFS_HOST): mkfs/mkfs.c $(K)/fs.h $(K)/param.h
>mkdir -p $(dir $@)
>gcc -Wno-unknown-attributes -I. -o $@ $<

$(FSIMG): $(MKFS_HOST) README $(USER_BINS)
>mkdir -p $(dir $@)
>$(MKFS_HOST) $@ README $(USER_BINS)

.PHONY: qemu qemu-gdb clean print-layout kernel/kernel fs.img mkfs/mkfs

kernel/kernel: $(KERNEL_ELF)
fs.img: $(FSIMG)
mkfs/mkfs: $(MKFS_HOST)

ifndef CPUS
CPUS := 1
endif

QEMUOPTS = -machine virt -bios none -kernel $(KERNEL_ELF) -m 128M -smp $(CPUS) -nographic
QEMUOPTS += -global virtio-mmio.force-legacy=false
QEMUOPTS += -drive file=$(FSIMG),if=none,format=raw,id=x0
QEMUOPTS += -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0

qemu: check-qemu-version $(KERNEL_ELF) $(FSIMG)
>$(QEMU) $(QEMUOPTS)

# try to generate a unique GDB port
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
 then echo "-gdb tcp::$(GDBPORT)"; \
 else echo "-s -p $(GDBPORT)"; fi)

.gdbinit: .gdbinit.tmpl-riscv
>sed "s/:1234/:$(GDBPORT)/" < $^ > $@

qemu-gdb: $(KERNEL_ELF) .gdbinit $(FSIMG)
>@echo "*** Now run 'gdb' in another window." 1>&2
>$(QEMU) $(QEMUOPTS) -S $(QEMUGDB)

print-gdbport:
>@echo $(GDBPORT)

print-layout:
>@echo "kernel elf: $(KERNEL_ELF)"
>@echo "fs image  : $(FSIMG)"
>@echo "apps      : $(USER_BINS)"

QEMU_VERSION := $(shell $(QEMU) --version | head -n 1 | sed -E 's/^QEMU emulator version ([0-9]+\.[0-9]+)\..*/\1/')
check-qemu-version:
>@if [ "$(shell echo "$(QEMU_VERSION) >= $(MIN_QEMU_VERSION)" | bc)" -eq 0 ]; then \
>echo "ERROR: Need qemu version >= $(MIN_QEMU_VERSION)"; \
>exit 1; \
>fi

clean:
>rm -rf $(BUILD) .gdbinit

-include $(KERNEL_OBJS:.o=.d) $(ULIB_OBJS:.o=.d) $(USER_APP_OBJS:.o=.d) $(USYS_OBJ:.o=.d)
