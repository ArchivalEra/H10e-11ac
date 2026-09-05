# eMMC 无人值守自启配方（社区首例，2026-08-30 实战验证）

> 目标：H10E-11AC 盒侧 S905L3 上电即起 Debian 13（26 秒到 root 登录符），零人工干预。
> 前置：已按 aml-flash.md 刷好底包基线；已按 vendor-booti.md 排雷（其产出 DTB/内核头知识是本配方组件）。

## 核心思路

**不哄 vendor loader 认识新格式，而是把内核做成 vendor storeboot 天生认识的 ANDROID! boot.img 喂回它**。原厂 bootcmd（storeboot）一个字不改，env 不碰，加密分区不碰。

## eMMC 布局要点（实测）

| 偏移 | 内容 | 性质 |
|---|---|---|
| 0x0 – ~40M | bootloader/密钥区 | 不碰 |
| 0x4E400000 | AML_RES 保留区（dtb+env+keys） | **加密**，只有 maskrom 能写 |
| ~0x4D3F9000 | env 数据 | _find_partition_by_name("env") 失败根因 |
| **0x4F400000** | **boot 分区（ANDROID! 头）** | **非加密，Linux dd 直写 ← 全案要害** |
| ~37.8M | Emmckey 保护区间 | FAT 跨它拒读；store disprotect key 临时解锁 |

Linux 侧分区（当时的拼装态）：p1 FAT（4M–516M）、p2 ext4 6G（Debian 13 rootfs）。
**最终方案不依赖 p1**（p1 引导无先例），boot.img 直接进 0x4F400000 的 boot 分区。

## 步骤一：内核（CachyOS 7.2.2-1 官方树）

- clang+lld + thinLTO；BBR + BBR3 内建；`DEBUG_INFO_NONE`；nouveau/tegra 裁剪
- **`CONFIG_CMDLINE_FORCE=y`（无人值守的基石）**，强制参数：
  ```
  earlycon=meson,mmio32,0xc81004c0 root=/dev/mmcblk2p2 console=ttyAML0,115200
  module_blacklist=meson_vdec,meson_drm,meson_dw_hdmi systemd.mask=boot.mount
  ```
  - `module_blacklist`：7.2 的 meson DRM/HDMI（vdec 亦挂）probe 在此板挂死，显示栈全禁闭（.ko 保留，修好后交互摘除）
  - `systemd.mask=boot.mount`：p1 FAT 被烧录抹掉而 fstab 有 /boot 行，绕过
- 产物 Image ≈ 39.7MB → `gzip -9`

## 步骤二：DTB（三嫁接点缺一不可）

以 `x7-5g-2g.dtb`（2G 内存节点）为基础：

1. `memory@0 reg = 0x80000000`（2G）——vendor slot5 DTB 的 codec_mm_cma 指向 >2G 虚假内存，**不能用 vendor 的**
2. 根级 `secmon` 节点 + `reserved-memory/linux,secmon`（vendor-booti.md 层2 的 dts 片段）
3. `dtc -p 32768` 填充（层3）

## 步骤三：boot.img

```bash
mkbootimg \
  --kernel Image.gz \            # gzip -9 的 CachyOS Image
  --kernel_offset 0x1080000 \    # hwrom 铁律
  --second dtb-padded.dtb \      # DTB 放 second 区，vendor 从这取
  --second_offset 0xF0000000 \
  --tags_offset 0x100 \
  --pagesize 2048 --base 0x0 \
  -o boot.img
```

参数来源：底包 boot 分区 ANDROID! 头解析。

## 步骤四：烧录

maskrom 定制包（`--parts=all` 铁律）：bootloader=原厂、_aml_dtb=原厂、boot=自制 boot.img、
其余 Android 分区照底包。**烧录协议会正确加密写入 _aml_dtb**——这是 Linux 侧 dd 做不到的。

## 步骤五：验证

拔座 → 上电 → 26 秒 → 串口 root 登录符 + `h10e-11ac.local` SSH 待命。

## 遗留尾巴（不影响自启）

- depmod 重跑（模块裁剪后）
- meson DRM 挂死真凶待交互式 modprobe 排查（KDE/显示前景）
- fstab /boot 行 sed 清理（当前靠 systemd.mask 绕过）
- p1 FAT 的 Create partitions 已被烧录抹掉

## U 盘应急方案（eMMC 方案的降级备份）

1. SanDisk dd 入 Armbian s905l3 镜像
2. 牙签引导（背面复位孔按住上电 10s）
3. vendor u-boot：`usb start; fatload usb 0 1020000 s905_autoscript; autoscr 1020000`
4. `armbian-install`（选 mmcblk2 + ext4）→ 换自编内核
