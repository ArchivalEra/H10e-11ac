# H10E-11AC 自研启动件维护条例 v1.0（2026-09-05）

> 适用范围：路由侧（ZX279128S）一切非原厂启动逻辑。
> 总原则：**只读镜像不动内核；只写空白区；任何改动先备回滚。**

## 1. 启动链（记住这个顺序，出问题按序查）
1. U-Boot（已存 env）：`bootcmd=run b1 b2 b3 b4`
   → b1 设 bootargs → b2 从 NAND 读原厂 kernel1 → b3 从 NAND slack 读外挂盘
   → b4 双地址 `bootm`。无网络依赖、无条件分支（本 U-Boot 无 `if` 解析器）。
2. initramfs rcS → 外挂盘 overlay 同名 `rcS`（hook + proof marker）。
3. hook 等 br0 **carrier**（180 秒上限）→ 起 `agent-boot.sh`：
   printk=1 → java 波次（保 provision 内存）→ 起 agent。
4. agent：S05（串口 pid 仪表盘）→ S10（LuCI 全栈）→ 看门狗 60 秒轮询
   → 300 秒延迟扫荡（pc/osgid/voice/mgmt）→ 360 秒大扫荡（收敛到 pid 表）。

## 2. 文件清单（三处，缺一不可，改完要对 md5）
| 位置 | 文件 | 说明 |
|---|---|---|
| 设备 /userconfig | `agent-boot.sh` | 启动总控（含延迟扫荡） |
| 设备 /userconfig | `agent/agent.sh` + `services/S05-serial-ps` + `services/S10-luci` | 代理本体 |
| 设备 /userconfig | `luci80_boot.sh` | LuCI 一键重建（约 40 秒） |
| 设备 /userconfig | `httpd.shadow` | :80 让位楔子 |
| 设备 /usr/data | `iw-luci-final/delta-226/luci-fix1/agent.tar.gz` | 栈与备份 |
| 设备 NAND 0x4000000 | 外挂盘 8KB（`mini-ramdisk.uimg` 内容） | hook 载体，只占空白区 |
| 设备 U-Boot env | bootcmd/b1..b4/serverip | 已 saveenv |
| Host tftpboot | 上述全部 master + `mini-ramdisk.uimg` + `kernel1-stock.bin` | 以 host 为准 |
| 仓库 h10e/ | `agent/`、`luci80_boot.sh` 同步副本 + 本文档 | 以仓库为准归档 |

## 3. 日常操作
- 看状态：`agent.sh status`（UP/OFF/DOWN）；串口每 5 秒 pid 表。
- 停某服务：`chmod -x services/SNN-xxx`（60 秒内生效，无需重启）。
- 全停：建 `/userconfig/NO_AGENT`（agent 自退）或逐个 `stop`。
- 重建 LuCI：`sh /userconfig/luci80_boot.sh`（40 秒，幂等）。
- 加新服务（如 cloudflared）：仿 S10 写 `S20-xxx` 实现 `start|stop|check`，
  `chmod +x`，先手动 `start` 验证再入库（host→tftp→设备→`/usr/data` 备份→repo）。

## 4. Kill 清单与红线（谁动谁死，顺序不能乱）
- **必须活过 LAN 构建期（约 2 分钟）**：pc、cspd 全家。pc 是全用户态的产婆，
  开局杀必断网（血泪：v2 回滚）。
- **建成后杀**（延迟扫荡，顺序）：pc → osgid/java → phoneapp/vodsl →
  eaServer/ctsgw/dmplatform/starnet/simulation/nethack → vsftpd/smbd/udpsvd/
  l2tp/ipsec/portmap → cspd。每批之间验 LAN+LuCI。
- **永远保留**：init、getty、telnetd、dnsmasq、portmap？（已杀，无影响，保留条目备查）、
  我方 ubusd/rpcd/h10e-ubus/lighttpd/agent。
- **禁止**：`saveenv` 前必须 `printenv` 核对；禁止 `nand erase/write` 非 slack 区；
  禁止改 kernel1 内核区；禁止在 U-Boot 用含 `;` 未加引号的 setenv（16 参数上限，
  用 `run` 链拆分）。

## 5. 故障恢复（按序）
1. LuCI 不通：`ubus list | grep ^luci$` 缺失 → 查 rpcd 三要素
   （`/usr/lib/ucode/*.so`、version.uc、REQUIRE_SEARCH_PATH），重跑一键脚本。
2. LAN 不通：`brctl show` 看成员 → `cat /sys/class/net/br0/carrier` →
   缺成员则 cspd 树没建完（等/查 pc 是否过早被杀）。
3. 串口刷屏：先看是不是自己的 pid 仪表盘；再 `printk=1`（串口登录会提到 DEBUG）；
   再按 §4 查漏杀。
4. 不明重启：先数 `Restarting system` 并看前文有无 SIGKILL（有=被命令的，无=查 pc/
   audit/upgrade）；每次 reboot 前 KDE 通知用户。
5. 变砖（U-Boot 还在）：`nand read + bootm` 手动起；U-Boot 没了：找另一位（盒侧 skill）。

## 6. 变更流程
host 改 → 语法校验（`sh -n`）→ tftp 上设备 → 设备验证 → `sync` →
`/usr/data` 备份 → repo（`h10e/` 下）commit+push。U-Boot env/NAND 改动另起
msgbox 级通知（需第二人停 U-Boot 或断电配合）。
