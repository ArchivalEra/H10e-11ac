# S905L3 侧刷机历程实录（2026-08-23 → 08-30）

> 设备：中国移动融合网关 H10E-11AC 的 **Amlogic S905L3（电视盒/安卓侧）**，2G RAM + 8G eMMC。
> 目标：在这颗从未有人成功 eMMC 启动 Linux 的盒子上，跑起 Debian 13 + 自编内核（社区首例）。
> 本文只写 S905 侧。路由器（ZX279128S）侧与本机的关系仅涉及网络拓扑，见 §12。
> 配套排雷细节：`docs/vendor-uboot-mines.md`；脚本：`scripts/`；本文是"历程"，那份是"地雷图"。

---

## 0. 结论先行

最终形态：**原厂 bootloader + 原厂 _aml_dtb（加密保留区）+ 自制 boot.img（ANDROID! 头 + CachyOS 7.2.2 gz 内核 + 自制 2G DTB）+ eMMC p2 Debian 13**，走原厂原封 `bootcmd=storeboot`，**上电 26 秒无人值守进 root 登录符**（串口 + SSH 待命）。全程不需要 U 盘、不需要牙签、不碰 env、不碰加密分区。

一句话配方（细节在后文逐条展开）：

```
原厂 bootloader（maskrom 烧当贝底包获得）
+ vendor slot5 DTB 换成我们自己的 x7-5g-2g-secmon-padded（64KB 垫）
+ boot.img = mkbootimg(gz -9 内核, kernel_offset=0x1080000, second=DTB, tags=0x100, pagesize=2048)
+ 内核 CONFIG_CMDLINE_FORCE 强制 root=/dev/mmcblk2p2 + module_blacklist=meson_drm,meson_vdec...
烧录：maskrom + aml-flash 定制包，**必须 --parts=all**（触发 DDR init）
```

---

## 1. 背景与硬件拓扑

- H10E-11AC 是**双 SoC 一板**：Amlogic S905L3（安卓/盒侧，本文主角）+ ZTE ZX279128S（路由侧）。
- **网络关系（仅此与路由侧有关）**：盒子所有 RJ45 网口都接在路由侧的交换芯片后面。S905 自己的网口是 `meson8b-dwmac + GXL 内部 PHY`（RMII 100M 全双工），DHCP 从路由侧拿 192.168.2.x。笔记本插盒子 **LAN 口**（不是 WAN）配 `nmcli box-lan`（never-default，不抢 wifi 默认路由）→ 192.168.2.3 → `sshpass -p 10086 ssh root@192.168.2.2`。
- 盒子 HDMI 口**唯一用途是短接救砖**（进 maskrom），无显示输出需求。
- 社区背景：**这台机型从没人在 eMMC 上正常启动过 Linux**，全网都跑 U 盘。当贝安卓能起（工厂烧录）——这就是我们唯一的"已知可引导基线"。

## 2. 军火与情报（开战前囤货）

- 当贝底包：`移动融合H10e-11ac线刷包.img`（1.8G，Platform 0x0811，含 DDR.USB/UBOOT.USB/_aml_dtb/boot/bootloader/dtbo/logo/odm/product/recovery/system/vbmeta/vendor 分区）——来自当贝论坛"魔百盒固件合集 > 移动融合机 H10E-11AC"。
- Armbian 26.08 s905l3 ophub 镜像（3.5G）：其 FAT p1 里有全套 u-boot bin（**p212 就是 s905l3 的社区钦定型号**，别看文件名叫 s905l2）和 `meson-gxl-s905l2-x7-5g.dtb`。
- FIP 仓库 `amlogic-boot-fip-e900v22c`（含 GXLX2 bl2/bl30/bl31/acs 与加密工具）——为"换主线 u-boot"的 B 计划准备的，最终没用上。
- 烧录工具：`aml-flash`（脚本封装 USB Burning Tool 协议）+ `amlimg pack`（定制线刷包）。
- 完整 eMMC 7.75G 备份镜像（分区扫描的原始依据）。

## 3. 阶段一：maskrom 线刷底包，建立可引导基线

**流程**：HDMI 短接座插 HDMI 口 → 双公头 USB 接盒子 **USB2（靠电源口那个才是 OTG）** → 电脑 → 盒子断电 → 上电 → maskrom 识别 → `aml-flash --img=底包.img --parts=all --wipe` → 完成拔座。

**本阶段踩的坑（每颗都疼）**：

1. **`--parts=all` 不是"全部分区"，是"包含 DDR 初始化"**。用 `--parts=boot` 只烧 boot 分区会因跳过 DDR init 而写失败。定制包必须从全量包改，保住 DDR 初始化步骤。
2. **定制包工艺**：改对应 `.PARTITION` 文件 + 删同名 `.VERIFY` 文件 + `sed` 删 commands.txt 对应行 → `amlimg pack`。三处不同步 = 烧录器静默跳过或报错。
3. **双公头 VBUS 会给盒子供电**："断电"必须拔 USB 线才有效，拔墙电没用。**座子插着时冷启动必进 maskrom**——判断 bootloader 死活前先拔座子，别把"进烧录模式"误判成"变砖"。
4. **多个 aml-flash 残尸并发**会抢设备导致 identify 卡 D 状态假死。每次开跑前 `pkill -9 aml-flash` 清场。
5. 底包的 u-boot 是 **U-Boot 2015.01 gxl_p211_v1**——唯一被 BL1 认的可引导 loader，后续一切引导实验都在它身上做。

## 4. 阶段二：U 盘引导 Armbian——DTB 1G/2G 真相

拿到基线后走社区成熟路：SanDisk dd 入 Armbian s905l3 镜像 → 牙签引导（按住背面复位孔上电 10s）→ vendor u-boot 手动：

```
usb start
fatload usb 0 1020000 s905_autoscript
autoscr 1020000        # → booti zImage + uInitrd + DTB
```

Armbian 完整启动成功。**这一阶段最大的情报收获**：

- 初期"vendor u-boot 与主线内核结构性不兼容"是**误判**。真因是 **DTB 内存节点配置**：镜像自带的 `meson-gxl-s905l2-x7-5g.dtb` 只认 **1G 内存**，而这台盒子是 **2G**。换成我们自己改的 `x7-5g-2g.dtb`（`memory@0 reg = 0x80000000`，即 2G）**一次点亮**。
- 教训：**报 Synchronous Abort 先怀疑 DTB 内容，别怀疑"结构性不兼容"**。DTB 是最便宜的可变量。

## 5. 阶段三：vendor booti 排雷（为 eMMC 自启铺路）

想在 vendor u-boot 里直接 `booti` 我们的 7.2 内核（从 eMMC/U 盘），连环踩雷，每颗都有明确修法（完整记录见 `docs/vendor-uboot-mines.md`）：

| # | 症状 | 根因 | 修法 |
|---|---|---|---|
| 1 | `usb start` 后 0 Storage | 插错口 | 只有 USB2 是 OTG |
| 2 | `fdt_path_offset FDT_ERR_NOTFOUND` + bl31 rsvmem 报错 → Abort | vendor booti 要在 DTB 找 `/secmon` 写 bl31 保留区 | DTB 嫁接 secmon 节点 + `reserved-memory/linux,secmon`（原形从底包 `_aml_dtb` gzip 壳里按 `d00dfeed` 魔数切出） |
| 3 | `fdt_setprop FDT_ERR_NOSPACE` → Abort | DTB 编译太紧凑，fixup 没空间 | `dtc -p 32768` 填充 |
| 4 | 无报错 Abort，x1=头字段值 | 主线 Image 带 EFI stub（MZ/PE 头），vendor booti 把 PE 头当 ARM64 头读 text_offset/image_size 读到垃圾 | 重编 `CONFIG_EFI_STUB=n` 或 RAM 里 `mw.l` 现场改头 |
| 5 | text_offset 修正后 Translation fault | **GXL 内存头 16MB 是 hwrom 保留区，MMU 不映射**，全家约定内核必须落 `0x1080000` | `text_offset=0x1080000`（等于实际加载地址，跳过重定位） |

另有两条环境级地雷：

- **自动引导链死循环**：vendor u-boot 每次启动扫第一分区跑 `aml_autoscript`，脚本崩 → CPU reset → 再扫。拆引信：`setenv bootcmd 'echo manual-mode'; saveenv`。
- **BL30 硬件看门狗**：在 U-Boot 提示符停留 40-90 秒会莫名重启。**所有长操作必须一气呵成，串口粘贴大段命令前先想清楚**（串口 mw 洪灌 2475 条会直接打哑控制台）。

结论：vendor booti 排到最后仍有一层无声失败（第四层雷疑似还有残留），**根治 = 放弃哄 vendor loader，改走"喂给它它认识的格式"**——这就是阶段六的 boot.img 路线。

## 6. 阶段四：eMMC 布局侦察（谁都没走过的黑区）

7.75G 全盘备份镜像扫描 + U-Boot 实测得出的真实布局（**分区不在 0 起点，前 40M+ 是 bootloader/密钥区**）：

| 偏移 | 内容 | 关键性质 |
|---|---|---|
| 0x0 – ~40M | bootloader/密钥区 | 别碰 |
| 0x4E400000 | **AML_RES 保留区**（dtb+env+keys） | **加密的**（platform.conf Encrypt_reg），Linux 侧裸写无效，**只有 maskrom 烧录协议能正确加密写入**。从 Linux 写 _aml_dtb 是死路。 |
| ~0x4D3F9000 | env 数据 | `_find_partition_by_name("env")` 找不到（当前 _aml_dtb 是 Frankenstein 容器），saveenv 失败根因 |
| 0x4F400000 | **boot 分区（ANDROID! 头）** | **非加密，可从 Linux 侧 dd 直写** ← 整个方案的要害 |
| ~37.8M 处 | Emmckey 保护区间 | FAT 文件跨它则 fatload 拒读；`store disprotect key` 运行时解锁（不持久） |

eMMC 当时状态：p1 FAT（4M~516M，boot 文件齐）+ p2 ext4 6G（Debian 13 rootfs 已就位）。p1 引导属于"没人成功过"的路线，所以最终放弃了 p1，改喂 boot 分区。

## 7. 阶段五：内核构建（CachyOS 7.2.2 官方树）

用户要求 clang 工具链、全功能 <100M、EEVDF + BBR3/BBR/FQ。用 CachyOS 7.2.2-1 官方树重编：

- **clang+lld** 编译，thinLTO。
- BBR + BBR3 双内建（`CONFIG_TCP_CONG_BBR=y` + BBR3 patch 已在 CachyOS 树）。
- `DEBUG_INFO_NONE`（瘦 Image）；nouveau/tegra 等无关模块裁剪。
- 产出 Image 39.7MB（gz -9 后进 boot.img 尺寸合格）。
- **决定性配置：`CONFIG_CMDLINE_FORCE`**，强制：
  ```
  earlycon=meson,mmio32,0xc81004c0 root=/dev/mmcblk2p2 console=ttyAML0,115200
  module_blacklist=meson_vdec,meson_drm,meson_dw_hdmi systemd.mask=boot.mount
  ```
  其中 `module_blacklist` 的来历：**7.2 的 meson DRM/HDMI 组件 probe 在这块板挂死**（vdec 也挂），staging 显示栈全部开机禁闭。.ko 都在，将来修好可交互式 modprobe 逐个摘黑名单。`systemd.mask=boot.mount` 是因为烧录抹掉了 p1 FAT 而 fstab 里 /boot 行还在——绕过它。
- 教训：**cmdline-force 是无人值守的基石**——不依赖任何 boot 脚本/env 传参，引导链里谁能把内核搬到内存谁就是 loader，参数我们自己带。

## 8. 阶段六：boot.img 与无人值守 eMMC 自启（终局）

思路转变：不再哄 vendor booti 解析主线镜像，而是**做成 vendor storeboot 天然认识的 Android boot.img 喂回它**——原厂 bootcmd 一个字都不改。

**boot.img 构成**（参数从底包头解析得出）：

```
mkbootimg --kernel Image.gz(-9) --kernel_offset 0x1080000 \
          --second DTB --second_offset 0xF0000000 \
          --tags_offset 0x100 --pagesize 2048 --base 0x0
```

- **DTB = x7-5g-2g-secmon-padded**：2G 内存节点（阶段二的教训）+ secmon/bl31 保留区（阶段三的雷 2）+ `-p 32768` 填充（雷 3）。**vendor slot5 DTB 的 codec_mm_cma 指向 >2G 虚假内存，会让主线内核 paging_init external abort——必须用自己的 2G DTB，这条必须死记**。
- DTB 放 boot.img 的 **second 区**，vendor storeboot 从这里取。

**烧录**：maskrom + 定制包（bootloader=原厂、_aml_dtb=原厂、boot=我们的 boot.img，其余 Android 分区照旧），`--parts=all`。

**结果**：上电 → vendor storeboot → imgread 认 ANDROID! 内容 → 解压内核 → CMDLINE_FORCE 直指 eMMC p2 → **26 秒 Debian 13 trixie root 登录符**。社区首例纯 eMMC 自启 Linux 的 H10E-11AC。

## 9. 当日终局清单（8-30 晚）

1. CachyOS 7.2.2-1 官方树重编完成（boot-emmc.img 15.8MB 待烧 TFTP 目录）。
2. Debian 13 rootfs 在 eMMC p2 运行中（fstab /boot 行靠 systemd.mask 绕过，待 sed 清理）。
3. depmod 需重跑（裁剪后）；meson DRM 挂死真凶待交互式排查。
4. 内核侧 BBR+FQ 落点即本机（路由器 4.1.25 锁 vermagic 装不了）。

## 10. 雷区总表（一句话版）

| 雷 | 一句话 |
|---|---|
| --parts=boot 写失败 | 必须 --parts=all 才有 DDR init |
| VBUS 假断电 | 拔 USB 线才算断电 |
| 座子=maskrom | 判 bootloader 死活前先拔座 |
| aml-flash 假死 | 先清残尸 |
| DTB 1G 崩溃 | 换 2G 节点 x7-5g-2g |
| bl31/secmon Abort | DTB 嫁接 secmon 节点 |
| FDT_ERR_NOSPACE | dtc -p 32768 |
| EFI stub 头被误读 | EFI_STUB=n 或补丁头 |
| text_offset 乱写即炸 | GXL 头 16MB hwrom 不映射，内核必须 0x1080000 |
| codec_mm_cma >2G | vendor slot5 DTB 陷阱，必须自制 2G DTB |
| aml_autoscript 死循环 | 拆 bootcmd 或喂正确脚本 |
| BL30 看门狗 | U-Boot 提示符停留 40-90s 必重启，长操作一气呵成 |
| 串口洪灌 | 2475 条 mw 打哑控制台 |
| _aml_dtb 加密 | 只认 maskrom 写入，Linux 侧死路 |
| Emmckey 保护 | FAT 跨 37.8M 拒读，store disprotect key 临时解锁 |

## 11. 可复现步骤（浓缩版，按序执行）

1. `aml-flash --img=当贝底包.img --parts=all --wipe`（建立基线，拔座）
2. U 盘 Armbian 牙签引导（可选，用于侦察；已有 eMMC 方案可跳）
3. 构建内核：CachyOS 树 + clang + `CONFIG_CMDLINE_FORCE` + `module_blacklist=meson_drm,meson_vdec,meson_dw_hdmi` + `DEBUG_INFO_NONE`
4. DTB：x7-5g-2g + secmon 节点嫁接 + `dtc -p 32768`
5. `mkbootimg`（§8 参数）→ 定制包（只换 boot 分区文件 + 删 VERIFY + sed commands.txt）→ `amlimg pack`
6. maskrom 烧入（`--parts=all`）→ 拔座 → 上电 → 26 秒 SSH

## 12. 与路由侧的网络关系（仅网络部分）

- 盒子网口物理上挂路由侧交换芯片后；S905 自己的 PHY 从路由侧 DHCP 拿 192.168.2.x。
- 笔记本→盒子：插 LAN 口 + `box-lan` profile（never-default）→ 192.168.2.3 → SSH 10086。
- 盒子 Debian 侧跑 BBR3/FQ（内核已带）；路由器 4.1.25 锁 vermagic 装不了新拥塞控制。
- 盒子 DHCP IP 会漂（.2→.4→.5），找 IP 用 ping 扫描或 mDNS `h10e-11ac.local`。
- 更深的路由侧系统内容不在本文范围（见 `hisi-router-side.md` 与 `docs/vendor-uboot-mines.md` 的路由侧部分）。
