# H10E-11AC 攻坚战记（截至 2026-09-01）

双 SoC 融合网关：**Amlogic S905L3**（盒侧，2G RAM + 8G eMMC）+ **ZTE ZX279128S**（路由侧）。
两条战线：盒侧刷机解锁（Debian 13 eMMC 自启，社区首例）+ 路由侧接管（root shell / 全盘备份 / LuCI）。

## 时间线（浓缩）

**08-19~22 通宵侦察**
- 盒子半死不活：maskrom 恢复原厂 bootloader（`--parts=bootloader`）
- **BL1 排他铁律**：拒绝一切第三方 bootloader（unifreq/p212/e900v22c 全部 CHK:A0 循环），唯一能过 = 底包原厂
- **VBUS 陷阱**：双公头插电脑 = 盒子靠 5V 活着，"断电"必须拔 USB 线
- 囤货：Armbian s905l3 镜像、u-boot 五件套、当贝底包、FIP 仓库

**08-23 底包基线**
- vendor storeboot 第五层雷：无视传入 dtb，总从 `_aml_dtb` 分区读且要求 gzip AML_ 多合一容器
- imgread 实测 ANDROID! 格式可过校验；定制包工艺（改 PARTITION/删 VERIFY/sed commands.txt）全绿验证
- SanDisk dd Armbian s905l3 镜像备好

**08-29 盒子复活**
- Armbian 26.08 U 盘牙签引导成功 → **DTB 1G/2G 内存节点 = 此前一切崩溃真凶**（换 x7-5g-2g.dtb 一次点亮）
- eMMC 布局实锤：boot @0x4F400000（非加密可 dd）、_aml_dtb @0x4E400000（**加密，仅 maskrom 可写**）、Emmckey @37.8M
- Debian 13 rootfs 构建；FIP/主线 u-boot 材料囤货

**08-30 双线突破日**
- 盒侧：底包重刷基线 → vendor booti 四层雷排完（secmon 节点/DTB 填充/EFI-stub/hwrom 16MB）→ 战术转向 boot.img（喂 vendor 认识的 ANDROID! 格式）→ CachyOS 7.2.2 编译（clang/thinLTO/BBR3）→ **社区首例 eMMC 无人值守自启 Debian 13（上电 26 秒）**
- 路由侧：UART 焊接完成 → 串口四步绝杀 root shell → mtd1–13 全 NAND 备份 → telnet 8023 后门 + web 超管 → modded kernel 写回 NAND
- 夜：ImmortalWrt 战役发起（侦察：原厂 4.1.25 内核 + ARMv7 用户态重组）

**08-31 LuCI 战役（路由侧）**
- csp 用户无 chroot 权限逼出免 chroot 方案
- 交叉编译全链：json-c→libubox→ubus→uci→ucode→rpcd→libnl→iwinfo→lucihttp→lighttpd
- 七大雷：宿主代理 TUN 污染、编译期前缀烤入、静态库吞依赖、getrandom(GRND_INSECURE)、csp 用户、ACL 权限、ETXTBSY
- **LuCI 全链路打通（8090）**：登录 302 → Dashboard/System 200

**09-01 持久化与双救砖（路由侧）**
- 级联 cpio 注入失败（4.1 内核 initramfs 不支持 member2）
- kernel1 槽位真相：自动引导实际读 0x2200000，烧 /dev/mtdblockN 对号入座无效
- v12 烧 kernel1 → 砖 → **串口救砖×2**（原厂 mtd6.img + 精确长度引导）
- **手动引导公式**（100% 复现）：`nand read 0x44000000 0x2200000 0x1de5030` → `bootm 0x440001e0`
- 四步绝杀 root shell ×2；SGU 镜像头破译（image table @0x54）
- 终态：原厂内核恢复、服务全部恢复；v13（rcS 注入自启）打包链全通，烧写完成待验证

## 状态与未竟（截至 09-01）

- 盒侧：Debian 13 eMMC 自启运行中；显示栈黑名单待排查；fstab /boot 待清
- 路由侧：原厂系统恢复运行；v13 自启未验证；LuCI 资产在 /usr/data/iw（jffs2 持久）

## 目录

- `s905/` — 盒侧（S905L3）：刷机历程 + vendor u-boot 排雷实录
- `h10e/` — 路由侧（ZX279128S）：攻略笔记与救砖（截至 09-01 认知）
- `.agents/skills/s905l3-emmc-flash/` — S905 刷机 skill（触发式经验库）
