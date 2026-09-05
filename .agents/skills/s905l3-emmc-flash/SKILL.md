---
name: s905l3-emmc-flash
description: Amlogic S905L3（含 H10E-11AC 融合网关盒侧）eMMC 刷机/引导/内核经验库。凡涉及 S905/S905L3/GXL 盒子刷机、maskrom 线刷、aml-flash 定制包、vendor u-boot booti 排雷、DTB secmon/内存节点问题、mkbootimg 制作、eMMC 自启 Linux（Debian/Armbian）、CachyOS/主线内核在此平台编译部署——即使用户没提"刷机"二字——都应加载本 skill 再动手。
---

# S905L3 eMMC 刷机经验库

本机实测平台：H10E-11AC 盒侧 Amlogic S905L3（2G RAM + 8G eMMC，U-Boot 2015.01 gxl_p211_v1，GXL 内存头 16MB hwrom 不映射）。**已实现社区首例纯 eMMC 无人值守启动 Debian 13**。路由侧（ZX279128S）不在本 skill 范围，仅网络拓扑相关时提及。

## 操作前必读

按任务类型读对应参考文档（本 skill 目录下 `references/`）：

1. 任何烧写/引导动作前 → 先读 `references/mines.md`（雷区总表，15+ 颗实测雷）
2. 要做定制线刷包或 maskrom 烧写 → 再读 `references/aml-flash.md`
3. 要在 vendor u-boot 里 booti 主线内核 → 再读 `references/vendor-booti.md`
4. 要复现 eMMC 无人值守自启 → 再读 `references/emmc-recipe.md`

详细历程叙事在仓库 `docs/s905-flash-journey.md`（写背景/写文章时参考）。

## 十条铁律（每条都踩过实物）

1. **aml-flash 定制包必须 `--parts=all`**——跳过 DDR init 的部分烧写（如 `--parts=boot`）必失败。
2. **双公头 VBUS 给盒子供电**：断电 = 拔 USB 线；座子插着冷启动必进 maskrom，别误判变砖。
3. **DTB 内存节点优先排查**：报 Synchronous Abort 先怀疑 DTB（1G/2G、secmon 节点缺失、紧凑无 fixup 空间），别怀疑"结构性不兼容"。
4. **GXL 头 16MB 是 hwrom 保留区（MMU 不映射）**：内核必须落在 0x1080000，`text_offset` 乱改即 Translation fault。
5. **主线 Image 要 `CONFIG_EFI_STUB=n`**：vendor booti 把 MZ/PE 头当 ARM64 头解析，读出垃圾 text_offset 后巨型 memcpy 即崩。
6. **vendor slot5 DTB 的 codec_mm_cma 指向 >2G 虚假内存**：用它引导主线内核 paging_init 必崩，必须自制 2G DTB。
7. **_aml_dtb 保留区是加密的**：只有 maskrom 烧录协议能正确写入，Linux 侧 dd 是死路。
8. **boot 分区（0x4F400000）非加密可 Linux dd 直写**——eMMC 自启方案的要害通道。
9. **BL30 看门狗**：U-Boot 提示符停留 40–90s 自动重启；长操作一气呵成，串口禁止洪灌（2475 条 mw 打哑控制台）。
10. **vendor u-boot 每次上电扫分区 1 跑 `aml_autoscript`**：脚本异常 = reset 循环；拆引信 `setenv bootcmd 'echo manual-mode'; saveenv`。

## 已验证终局配方（eMMC 无人值守自启，浓缩）

```
boot.img = mkbootimg(
    kernel = Image.gz(-9, CONFIG_CMDLINE_FORCE + module_blacklist=meson_drm,meson_vdec,meson_dw_hdmi),
    kernel_offset = 0x1080000, second = DTB(2G+secmon, dtc -p 32768),
    second_offset = 0xF0000000, tags_offset = 0x100, pagesize = 2048, base = 0x0)
烧录 = maskrom + 定制包(bootloader/_aml_dtb 用原厂, boot 用上者, --parts=all)
启动 = 原厂 storeboot 原封不动 → 上电 26s 进 root shell
```

DTB 三个嫁接点缺一不可：`memory@0 reg=0x80000000`（2G）、根级 `secmon` 节点（bl31 in/out func + reserve_mem_size=0x200000）、`reserved-memory/linux,secmon` shared-dma-pool @0x10000000 size 0x400000。

## 常用命令速查

```bash
# 烧录（清残尸先）
pkill -9 aml-flash
aml-flash --img=<包>.img --parts=all --wipe

# 定制包（改 PARTITION 文件 + 删同名 VERIFY + sed commands.txt 后）
amlimg pack

# 串口 U-Boot 手动引导 U 盘
usb start; fatload usb 0 1020000 s905_autoscript; autoscr 1020000

# 主线 u-boot 编译（B 计划材料，未启用）
make CROSS_COMPILE=aarch64-linux-gnu- p212_defconfig; make -j$(nproc)
```

## 平台事实速记

- 盒子网口 = meson8b-dwmac + GXL 内部 PHY（RMII 100M），物理挂路由侧交换芯片后；DHCP 192.168.2.x，IP 会漂。
- 社区钦定映射：s905l3 用 **p212** u-boot / `meson-gxl-s905l2-x7-5g.dtb`（文件名带 l2 别纠结）。
- eMMC = /dev/mmcblk2（8G）；boot 分区 @ 0x4F400000；AML_RES @ 0x4E400000（加密）；Emmckey 保护 @ ~37.8M。
- 内核基线：CachyOS 7.2.2-1 官方树 + clang/lld + thinLTO + BBR/BBR3 内建 + DEBUG_INFO_NONE，Image gz 后进 boot.img 合格。
