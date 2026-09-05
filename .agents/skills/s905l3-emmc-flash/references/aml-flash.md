# aml-flash / maskrom 线刷工艺

## 进入 maskrom

1. HDMI 短接座插入 HDMI 口（**救砖专用，不接显示器**）
2. 双公头 USB 接盒子 **USB2（靠电源口）**——只有这个是 OTG，其余口不认
3. 盒子断电 → 上电 → 电脑识别 maskrom（lsusb `1b8e:c003 Amlogic GX-CHIP`）
4. **座子插着时每次冷启动都会进 maskrom**——拔座后冷启动才走正常引导

## 底包烧写（建立基线）

```bash
# 清残尸（并发残尸会卡 D 状态假死）
pkill -9 aml-flash

# 全量恢复（唯一可靠的烧写方式）
aml-flash --img=<底包>.img --parts=all --wipe
```

- 底包来源：当贝论坛"魔百盒固件合集 > 移动融合机 H10E-11AC"（当贝纯净桌面版可用，密码 10086）
- 底包 u-boot = `U-Boot 2015.01 gxl_p211_v1`，是 BL1 唯一认的可引导 loader

## 定制包工艺（在底包上换分区）

三处一体，缺一不可：

1. 替换包内对应 `.PARTITION` 文件（如 `boot`、`system`）
2. **删除同名 `.VERIFY` 文件**（否则校验失败拒绝写入）
3. `sed` 从 commands.txt 删除对应行

然后打包烧写：

```bash
amlimg pack   # 生成定制 .img
aml-flash --img=custom.img --parts=all --wipe
```

### 已验证的分区替换

| 分区 | 内容 | 制作方式 |
|---|---|---|
| bootloader | 保持原厂 | 不动 |
| _aml_dtb | 保持原厂 | 不动（加密区，Linux 侧做不了） |
| boot | 自制 boot.img（mkbootimg 产物） | 见 emmc-recipe.md |
| system | ext4 rootfs 镜像 | `mke2fs -F -L SYSTEM -d rootfs -m1 -O ^has_journal system.img 1280M` |

> ⚠️ **`--parts=all` 的真实含义是"包含 DDR 初始化"**，不是"全部分区"。只烧单分区（如 `--parts=boot`）会跳过 DDR init 导致写失败。定制包必须从全量包出发裁剪，保留 DDR 初始化命令行。

### 环境陷阱

- 双公头 VBUS 供电：**拔 USB 线才是真断电**（拔墙电无用，座子灯亮 = 还活着）
- 座子插着冷启动必进 maskrom：判断 bootloader 死活前先拔座
- 多个 aml-flash 残尸并发：`pkill -9 aml-flash` 清场
- 相关脚本（仓库 `scripts/`）：`aml-flash`、`mwrite-chunks.sh`

## 分区制作参考

```bash
# ext4 rootfs 镜像（保留 gpu 满血版 1.8G；瘦身后 847M 可减）
mke2fs -F -L SYSTEM -d rootfs/ -m1 -O ^has_journal system.img 1280M
e2fsck -f system.img   # 烧前校验
```

rootfs 内按当贝帖处理首连便利：`/etc/shadow` root 行 + `sshd_config` PermitEmptyPasswords yes + PermitRootLogin yes（装到 eMMC 后立刻 passwd 改口令）。
