# H10E-11AC 路由侧（ZX279128S）攻略笔记 — 截至 2026-09-01

> 交接前认知快照。2026-09-02 后的修正（如 SGU 端序）不在本文范围。
> 凭据（telnet/web/ssh）已获取并存于本地记忆库，不入仓库。

## 四步绝杀（串口 root shell，100% 复现）

1. 断电重启瞬间狂敲回车拦 autoboot → `=>`（U-Boot 2013.04）
2. `mtddebug read 0x44000000 kernel 0 0x2000000`（拦下 autoboot 后 RAM 是空的，必须先读）
3. `setenv versioninfo ignore=`（灵魂步骤：固件每次启动把 versioninfo 强拼进 bootargs，不排毒 rdinit 必失效）+ `setenv bootargs console=ttyAMA0,115200n8 mem=512M rdinit=/bin/ash dummy=`（**用 /bin/ash**；dummy= 吸收尾部拼接垃圾）
4. `bootm 0x440001e0` → `/ #` root shell

**注意**：setenv 只改内存，**不要 saveenv**；reset 命令无效，只有断电能回 U-Boot；OS 控制台无 shell。

## 已拿到的东西（截至 09-01）

- telnet 8023 后门（csp 用户，uid=108，busybox shell，无 chroot/reboot 权限）
- web 超管面板（CMCCAdmin 账号，凭据在记忆库）
- mtd1–mtd13 全 NAND 分区备份（TFTP 通道已验证）
- modded kernel（telnetd 注入）写回 NAND 成功过
- dropbear 静态二进制（ARMv5t 软浮点）

## 持久化攻坚（09-01 当日，半途）

- 级联 cpio 注入失败：vendor 4.1.25 内核 initramfs 不支持 member2
- **kernel1 槽位真相**：自动引导实际读 0x2200000（= Linux /proc/mtd 的 mtd6），烧 /dev/mtdblockN 对号入座无效
- v12 烧 kernel1 覆盖好内核 → 砖 → 救砖×2（原厂 mtd6.img + 精确长度引导）
- **手动引导公式**（100% 复现）：`nand read 0x44000000 0x2200000 0x1de5030` → `bootm 0x440001e0`
- SGU 镜像头破译：0x54 起 image table `[time][size][entry][crc]`（当日按 BE 解读；端序问题 09-02 才发现）
- 终态：原厂内核写回 0x2200000，web80/8023 全恢复；v13（rcS 注入 telnetd+LuCI 自启）打包烧写完成，**引导结果未验证**

## LuCI chroot 资产（/usr/data/iw，jffs2 持久分区）

交叉编译全链（ARMv7 软浮点）：json-c→libubox→ubus→uci→ucode→rpcd→libnl→iwinfo→lucihttp→lighttpd。
七大雷：宿主代理 TUN 污染、编译期前缀烤入、静态库吞依赖、getrandom(GRND_INSECURE)、csp 用户缺 getpwuid、ACL 文件属主/权限、ETXTBSY。
曾验证：登录 302 → Dashboard/System 200（8090）。

## 待办（09-01 时点）

- v13 自启验证；LuCI 资产随 root 部署；web 夺权 80；kernel-v14 持久化注入
