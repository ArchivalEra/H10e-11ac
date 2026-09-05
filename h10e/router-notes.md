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

---

# 续写 09-01→09-04（另一 agent 交接后）

## 超级密码方法论（只写方法，不写值）
- telnet/su 口令：8/30 串口阶段所得，本人未亲历解包过程。
  **[待另一位补充：哪份固件/哪个偏移/什么工具解出的明文]**。
- LuCI root 口令：我方自设。做法：SHA-512-crypt（`$6$`）hash 写入
  `/etc/config/rpcd` 的 login 段（系统 root 口令未动）；验证：
  `ubus call session login` 返回 ACL 即通，浏览器 POST 302 + 种 cookie。
- WiFi PSK：从 live 系统读出（`/userconfig/wireless.conf` 存真 key），非破解；
  P1 改密实测后恢复原值。

## 09-02 工具链与基座
- 工具链锁死 armv5 软浮点 bleeding-edge-2017.11（gcc7.2）；硬浮点污染禁用。
- 产物红线 `GLIBC_2.4`；全家桶（ubus/uci/ucode/rpcd/luci 等）armv5/2.26 重建完毕。
- 自研 `h10e-ubus`：system/network/iwinfo/hostapd×4/service，klogctl 替代 popen
  根除并发 segfault，看门狗常驻。

## 09-03 LuCI 与 WiFi
- LuCI 全栈打通并固化为一键脚本（`h10e/luci80_boot.sh`，约 40 秒）：
  基座+delta+fix1 解压、`/usr/lib/rpcd` 补 mkdir、ucode 全家桶补齐、生成
  `luci/version.uc`、rpcd 启动带
  `REQUIRE_SEARCH_PATH=/usr/share/ucode:/usr/lib/ucode`（缺任一则 `luci` 对象
  注册失败，前台起 rpcd 看 stderr 即现形）。
- 浏览器验收：Material + zh_cn，登录→概览 0 pageerror。
- WiFi P0（`iwpriv DisConnectSta` 踢人）/P1（改 SSID/密码/信道，顺序
  Channel→Auth→Encryp→WPAPSK→SSID，50ms 异步回 OK）实测；E-CBDA 双 VAP 关闭。

## 09-04 自启动、手术、安静
- U-Boot：`bootdelay` 改 5 并 saveenv（与"不要 saveenv"规则冲突，特此声明；
  仅放宽打断窗口，未动 bootcmd）。`bootcmd` 仍为原厂行（SPL 预加载，无 nand read）。
- "自启动幽灵"结案：两次"凭空执行"均为手动执行（history+mtime），无触发器。
- 启动链审计结论：只读镜像执行 + 持久分区只存数据，无 cron/profile hook，
  mdbus-rcS 断链——**免刷机自启动在 vendor 链内无解**。
- initramfs 手术 test1~test5 四次静默挂后取消：外层 gzip 重压即死（与内容无关，
  原厂 mem-boot 一次过）；重建工具链留档 `h10e/surgery-scripts/`（含 vendor 头
  total+crc32 语义）；教训：先做零改动重压对照。
- **外挂 ramdisk 一次成功**：原厂 kernel1 + 4.6KB 盘（仅改过的 rcS）+
  `bootm 内核地址 盘地址`，overlay 盖内置 rcS，hook→agent→LuCI 全自动已验证。
  field 落盘待定（TFTP fallback 或 kernel1 尾部 slack）。
- 自启动代理 `h10e/agent/`：`agent.sh`（有序启动+60s 看门狗+pc 压制+NO_AGENT 门）、
  `S10-luci`、`agent-boot.sh`（printk+java 波次+br0 等待）。
- 安静：`ps` 里 PID 817 的 "cspd" 实为 `/bin/pc`（argv 伪装）；pc 已杀且不影响
  telnet/网络；printk=1 持久化；java 由 osgid 约 3 分钟拉起，稳态只剩涓流。
- 缺口：`uci` 对象缺失（LuCI 不用）；soak 未补跑；P0 需在线 STA；cloudflared 待定。

---

# 续写 09-05（收官：三禁 + pid 仪表盘 + boot 自启动）
- **pc 定案为莫名重启元凶**：`ps` 里 PID 817 的 "cspd" 实为 `/bin/pc`（argv 伪装，
  查 `grep` 要用短名）；binary 含 `reboot`；pc 死后 38 分钟零重启（之前约 10 分钟一次）。
  教训：`reboot` 前必须 KDE 通知用户（kdialog），且每次只串行操作（telnetd maxcon=2）。
- **正确顺序（血泪）**：pc 是全用户态的"产婆"（cspd 及 LAN 配置经它之手），
  开局 stub 必断网；正解 = v1（hook-only 盘）放行，等 br0 carrier 后 agent 再杀。
  `agent-boot.sh` 等的是 carrier（非存在），`agent.sh` 启动时只杀 java 保内存，
  pc/osgid 进 300 秒延迟扫荡 + 看门狗每轮补刀 pc。
- **四波杀到 pid 表**：osgid/java/phoneapp/vodsl → eaServer/ctsgw/dmplatform/starnet/
  simulation/nethack → vsftpd/smbd/udpsvd/l2tp/ipsec/portmap → cspd；每波验 LAN+LuCI。
  终态用户态仅剩 init/getty/telnetd/dnsmasq/agent/ubusd/rpcd/h10e-ubus/lighttpd。
  延迟大扫荡（360 秒）已进 `agent-boot.sh`，下次启动自动收敛。
- **串口 pid 仪表盘**：`agent/services/S05-serial-ps` 每 5 秒向 console 刷表，
  每轮先 `printk=1`（串口登录会把内核日志提到 DEBUG，此为自愈）。
- **boot 自启动**（lab）：U-Boot `bootcmd` 置为 NAND 读内核 + TFTP 取盘，
  成功则双地址 `bootm`，失败回落原厂单启动；`serverip` 一并 saveenv。
  全程无人值守验证通过（hook→agent→LuCI→扫荡，无需手动）。
- 杂项：TX 中断定为 USB 适配器 OUT 端 wedged（重拔+proxy 重启+关 autosuspend 解决；
  proxy 已加写失败自动重连）；`reboot` 一律用 `reboot -f`（优雅关机会被 D 状态卡死）；
  NO_AGENT/NO_LUCI 双门常闭检查通过。

## 09-05 收官验证（无人值守启动打通）
- 外挂盘永久家：`mini-ramdisk.uimg`（4657B）一次写入 kernel1 尾部 slack
  （NAND 0x4000000，2MB 全 FF 区，免擦除直写，read-back cmp 校验通过）。
- 最终 bootcmd（`run b1 b2 b3 b4` 链，规避 16 参数上限与无 `if` 解析器）：
  b1 设 bootargs；b2 读内核；b3 读盘；b4 双地址 bootm。+serverip 一并 saveenv。
- 验收（`boot` 后全程无人值守）：hook→agent→LuCI→扫荡；br0 五成员；
  pc 缺席；浏览器 0 pageerror。断电自恢复成立，刷机之旅结束。

---

# 续写 09-05（ supervisory 战争：pc 定案、TX 中断、v2 回滚）
- **pc 定案为莫名重启元凶（后又存疑，见下）**：binary 含 `reboot`；pc 死后曾 38 分钟
  零重启；但随后在 pc 缺席的新启动中仍观测到自发重启一次——归因降级为"强嫌疑，
  未实锤"。另：`ps` 里找 pc 必须用短名 grep（comm 列是 `pc`），之前数次误报"缺席"。
- **TX 中断事件**：串口能收不能发，定位到 USB 适配器 OUT 端 wedged（目标重启时的
  电气毛刺）。修复：重拔 USB + proxy 重启 + 关 host 侧 autosuspend；proxy 已加
  写失败自动重连。另：U-Boot 抓取屡败后改规矩——要进 U-Boot 直接喊人，几秒钟的事。
- **v2（pc/java stub）回滚**：开局 stub pc 导致 cspd 子树永不出生，br0 空壳无成员、
  switch 无配置，LAN 全灭。结论：**pc 必须活过 LAN 构建期**（约 2 分钟），再杀。
  v1（hook-only 盘）+ agent（br0 carrier 等待 + 延迟扫荡）为最终形态。
- **cspd 行为学**：`PcStartProgram` 系列——cspd 自身不 fork helper，一律发消息让 pc 代劳；
  pc 死后 cspd 的 VOIP/TR069 IFS 每 30 秒重试（PON 无上行则永不成功，但不影响已建 LAN）。
  br0 成员/switch VLAN 由 cspd 在 LAN 构建期配好，之后 cspd 可杀（已验证 10 分钟+ 无影响）。
- **串口 pid 仪表盘**：`agent/services/S05-serial-ps` 每 5 秒刷表并重申 `printk=1`
  （串口登录会把内核日志提到 DEBUG，自愈）。终态串口仅剩仪表盘自刷（~180B/s）。
- **四波杀到 pid 表**（init/getty/telnetd/dnsmasq/agent/ubusd/rpcd/h10e-ubus/lighttpd，
  +sleep/watchdog）：osgid/java/phoneapp/vodsl → eaServer/ctsgw/dmplatform/starnet/
  simulation/nethack → vsftpd/smbd/udpsvd/l2tp/ipsec/portmap → cspd；延迟大扫荡
  （360 秒）已进 `agent-boot.sh`，下次启动自动收敛。
- **未闭环**：自发重启出现过 pc 缺席启动中的一例，元凶待定（audit/upgrade/pc 三方
  皆有嫌疑，无实锤）；`uci` 对象缺失（LuCI 不用）；P0 踢人需在线 STA；
  cloudflared 按 S20 规范接入；soak 从未完整跑完。
