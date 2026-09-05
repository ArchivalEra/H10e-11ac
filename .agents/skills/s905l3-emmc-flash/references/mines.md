# 雷区总表（S905L3 实测，全部踩过实物）

按"症状 → 根因 → 修法"组织。详细叙事见仓库 `docs/s905-flash-journey.md` §10。

## 烧录与供电类

| 症状 | 根因 | 修法 |
|---|---|---|
| `--parts=boot` 等部分烧写失败 | 跳过 DDR 初始化步骤 | 定制包一律 `--parts=all`（全量包基础上裁剪，保住 DDR init） |
| 明明断电了座子灯还亮 | 双公头 VBUS 给盒子供电 | 拔 USB 线才算真断电 |
| 冷启动直接进烧录模式 | 座子（HDMI 短接）插着就是 maskrom | 判 bootloader 死活前先拔座，别误判变砖 |
| aml-flash identify 卡 D 状态 | 多个残尸进程并发抢设备 | `pkill -9 aml-flash` 清场后再跑 |
| 定制包某分区被跳过/报错 | PARTITION/VERIFY/commands.txt 三处不同步 | 改 .PARTITION + 删同名 .VERIFY + sed 删 commands.txt 对应行，三处一体 |

## 串口与看门狗类

| 症状 | 根因 | 修法 |
|---|---|---|
| U-Boot 提示符停留后莫名重启 | BL30 硬件看门狗，40–90s 触发 | 长操作一气呵成；需要长停留先想办法喂狗或分段执行 |
| 串口控制台打哑 | mw 洪灌打爆输入缓冲（实测 2475 条） | 小文件传输分块 + 间隔，禁止洪灌 |
| 串口完全静默 | TX/RX 线松动（本机两次实战中招） | 先查物理线，再怀疑软件 |

## 引导与 DTB 类

| 症状 | 根因 | 修法 |
|---|---|---|
| 主线内核 Synchronous Abort（无明确报错） | DTB 内存节点 1G vs 实机 2G | 换 2G 内存节点 DTB（x7-5g-2g 系） |
| `fdt_path_offset FDT_ERR_NOTFOUND` + bl31 rsvmem 报错 → Abort | vendor booti 要 DTB 里有 /secmon 写 bl31 保留区 | 嫁接根级 secmon 节点 + reserved-memory/linux,secmon（原形从底包 _aml_dtb 按 d00dfeed 魔数切出） |
| `fdt_setprop FDT_ERR_NOSPACE` → Abort | DTB 紧凑无 fixup 空间 | `dtc -p 32768` 填充 |
| vendor slot5 DTB 引导主线内核 paging_init external abort | codec_mm_cma 指向 >2G 虚假内存 | 必须自制 2G DTB，vendor 的不能用 |
| booti 读 MZ/PE 头崩 | 主线 Image 带 EFI stub | `CONFIG_EFI_STUB=n` 重编，或 RAM `mw.l` 现场改头 |
| text_offset 改小后 Translation fault (esr 0x96000210) | GXL 头 16MB hwrom 保留区 MMU 不映射 | 内核必须落 0x1080000；text_offset=0x1080000（=实际加载地址，跳过重定位） |
| vendor u-boot 上电 reset 循环 | 分区1 aml_autoscript 脚本崩 → CPU reset → 再扫 | `setenv bootcmd 'echo manual-mode'; saveenv` 拆引信 |

## eMMC 类

| 症状 | 根因 | 修法 |
|---|---|---|
| 从 Linux 写 _aml_dtb 无效 | AML_RES 保留区加密 | 只认 maskrom 烧录协议；boot 分区（0x4F400000）才可 Linux dd |
| saveenv 报 partition not found | 当前 _aml_dtb 是 Frankenstein 容器无 /partitions 表 | 换 vendor slot5 DTB 作配置 DTB（但注意 codec_mm_cma 陷阱） |
| fatload 拒读某 FAT 文件 | 文件跨 37.8M 处 Emmckey 保护区间 | `store disprotect key`（运行时临时解锁，不持久） |
| eMMC 自启"没人成功过" | p1 FAT 引导链无先例 | 改喂 boot 分区（0x4F400000）ANDROID! 格式 + 原封 storeboot |

## 系统类

| 症状 | 根因 | 修法 |
|---|---|---|
| 7.2 内核 meson DRM/HDMI probe 挂死 | 组件与板不兼容（vdec 亦挂） | `module_blacklist=meson_drm,meson_vdec,meson_dw_hdmi` + CMDLINE_FORCE；KDE 前景 = 交互式 modprobe 逐个摘黑 |
| fstab /boot 挂载失败阻塞启动 | 烧录抹掉 p1 FAT | `systemd.mask=boot.mount` 临时绕 + 进系统 sed 清理 |
| 模块依赖缺失 | 裁剪后未重跑 | depmod 重跑 |
| 盒子 IP 漂移 | DHCP 租约变化 | ping 扫描 / mDNS `h10e-11ac.local` |
