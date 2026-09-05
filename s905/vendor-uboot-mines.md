# Vendor U-Boot 2015.01（当贝底包）排雷实录

> 盒子：H10E-11AC / S905L3，bootloader 为 `U-Boot 2015.01 (Aug 15 2023) gxl_p211_v1`。
> 本文记录用主线 7.2 内核从 USB 引导时踩中的每一颗雷与修法，供复现。

## 雷区地图（按触发顺序）

1. **`usb start` 后 0 Storage**：U 盘没插/插错口。USB2（靠电源口）才是 OTG。
2. **`fdt_path_offset() returned FDT_ERR_NOTFOUND` + `[rsvmem] bl31 reserved memory set addr error` → Synchronous Abort**
   vendor `booti` 启动前要在 DTB 根部找 `/secmon` 节点写 bl31 保留内存。
   修法：DTB 加根级节点
   ```dts
   secmon {
       compatible = "amlogic,secmon";
       memory-region = <&linux_secmon_pool>;
       in_base_func = <0x82000020>;
       out_base_func = <0x82000021>;
       reserve_mem_size = <0x200000>;
   };
   ```
   及 `reserved-memory/linux,secmon`（shared-dma-pool @0x10000000 size 0x400000）。节点原形来自底包 `_aml_dtb`（gzip 壳内 AML_ 多合一容器，可按 `d00dfeed` 魔数切出）。
3. **`libfdt fdt_setprop(): FDT_ERR_NOSPACE` → Synchronous Abort**
   DTB 编译太紧凑，fixup 写属性没空间。修法：`dtc -p 32768` 加填充。
4. **无报错 Synchronous Abort，寄存器 x1=头字段值**
   主线 7.2 Image 带 EFI stub（头部是 MZ/PE），vendor booti 把 PE 头字节当
   `text_offset@0x08`、`image_size@0x10` 读——实测读到垃圾 `0x28d0000`
   （正是崩溃现场 x2/x3），随后巨型 memcpy 落到未映射/非对齐地址。
5. **text_offset 修正后仍 Translation fault（esr 0x96000210）**
   GXL 内存头 **16MB 是 hwrom 保留区**，MMU 不映射——所以全家约定内核必须落在
   `0x1080000`。把 text_offset 改成 `0x80000` 会让它搬内核到 0x80000 直接炸。
   正确姿势：`text_offset = 0x1080000`（等于实际加载地址，跳过重定位），
   或干脆重编 `CONFIG_EFI_STUB=n` 的原生头内核。

## 内存布局约定（本次实战验证）

| 地址 | 用途 |
|---|---|
| 0x01000000 | DTB（73K 填充版，内核不重定位时安全） |
| 0x01080000 | 内核 Image（vendor 约定，避开 hwrom） |
| 0x10100000 | BL31（勿碰） |
| 0x10000000..0x10200000 | secmon/bl31 保留 |

## 自动引导链

vendor u-boot 每次启动会扫 usb/mmc 第一分区执行 `aml_autoscript`（uImage script）。
死循环 = 脚本崩 → CPU reset → 再扫。拆引信：
```
setenv bootcmd 'echo manual-mode'; saveenv
```

## 已知坑位与状态

- [x] secmon 节点 —— 已嫁接进 `patches/amlogic-s905l3/`（见 x7-5g-2g-secmon.dts）
- [x] DTB 填充 —— `-p 32768`
- [x] EFI-stub 头 —— `Image-vendorboot.bin`（text_offset=0x1080000 补丁版）+ RAM 内 `mw.l` 现场改头
- [ ] booti 最终仍无声失败返回 shell —— 怀疑还有第四层；根治方案为换 community u-boot
      （unifreq/ophub 系，天生支持主线镜像），经 maskrom 只刷 bootloader 分区
- [ ] 硬件看门狗嫌疑：在提示符停留 ~40-90s 会莫名重启（BL30 WDT），长操作要一气呵成

## 明日工具箱（已囤 /mnt/hdd/xz/）

- `h10e-arsenal/`：补丁版 Image、全部候选 DTB、v4 autoscript、u-boot help 全文、amlimg
- `uboot-s905x-s912-{unifreq,ophub}.bin`：community u-boot（maskrom 刷 bootloader 用）
- `Armbian_26.08.0_amlogic_s905l3_resolute_6.18.44_server_2026.08.15.img.gz`：
  ophub 官方 s905l3 镜像（保险引导链）
- `Amlogic.USB.Burning.Tool.v3.1.0.exe`：Windows 兜底烧录
- `ophub-kernel-6.18.44.tar.gz`：保险内核包
- `h10e-rootfs-backup.tar`：Debian 13 rootfs 全量备份
