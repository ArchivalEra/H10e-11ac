# 超级密码解包实录 — 固件解包链与凭据提取（2026-08-30）

> 补充 09-01~09-04 笔记中「[待另一位补充：哪份固件/哪个偏移/什么工具解出的明文]」一节。
> 本文只写方法与位置，不写明文值（约定同前；值在本地记忆库）。

## 0. 背景

08-30 串口四步绝杀拿到 `/#` root shell 后，目标立刻转向两个凭据：
1. **telnet 后门**（8023 端口的账号）——用于脱离串口的网络侧持久控制
2. **web 超管**（CMCCAdmin 账号）——用于夺权厂商管理面（80 端口）

两者都来自**同一个解包链**：把 kernel1 里的 initramfs rootfs 完整解包，从厂商出厂配置文件里翻出明文凭据。

## 1. 解包链（核心，全部偏移实测）

数据源：**kernel1 分区 TFTP 全量 dump**（`mtd6-full.bin`，33,554,432B）。
⚠️ 不要用串口拉的 kernel0 dump——实测有位损坏（gzip `invalid distance`，真机 gunzip 同数据零错误）。位完美原厂内核只有 kernel1 备份。

```
mtd6-full.bin (33,554,432B)
 ├─ 0x0000000: SGU 头（SGUV2.0.0B05）
 ├─ 0x006834: 外层 gzip ──gunzip──→ stage1（35,734,880B，zImage+initramfs）
 │    └─ 0x07BD40F: 内层 gzip ──gunzip──→ rootfs.cpio（66,859,881B，newc 格式）
 │         └─ cpio -idmv ──→ rootfs 树（/etc /bin /sbin /usr ...）
 └─ 0x1de3010: DTB（8219B，ZX279128S）
```

实操命令（本机 Linux 侧）：

```bash
# 定位内层 gzip（binwalk 或直接搜 gzip 魔数 1f 8b 08）
binwalk mtd6-full.bin
# 或 dd 出来逐段试
dd if=mtd6-full.bin of=stage1 bs=1 skip=$((0x6834)) 2>/dev/null
gunzip stage1                       # → 35MB zImage+initramfs 拼装体
# 内层：在 stage1 里搜 0x7BD40F 处的 gzip
dd if=stage1 of=rootfs.cpio.gz bs=1 skip=$((0x7BD40F)) 2>/dev/null
gunzip rootfs.cpio.gz               # → 66.8MB newc cpio
mkdir rootfs && cd rootfs
cpio -idmv < ../rootfs.cpio
```

## 2. 收获一：telnet 8023 后门凭据

解包后的 **`/etc/gponcfg/db_default_cfg.xml`**（明文 XML，厂商出厂默认配置）内含 `TelnetCfg` 表：

```
TS_Enable=1, Wan_Enable=1, Lan_Enable=1   ← 三路全开的固件级后门
TS_Port=8023
TS_UName=admin
TS_UPwd=（明文，即 telnet 密码）
```

**运营商没改这个固件级后门**——直接 `telnet 192.168.1.1 8023` 用该表账号密码即入 `~ $`（csp 用户，uid=108 busybox shell）。

## 3. 收获二：web 超管凭据

同一个 `db_default_cfg.xml` 里的 **`DevAuthInfo`** 段（ZTE 设备账号表）：
- 超管账号 CMCCAdmin + 出厂明文密码
- 直接登录 `http://192.168.1.1/` → start.ghtml 超管面板（设备认证/网络/语音/无线/安审全解锁）

**关键认知**：厂商出厂默认配置以明文随固件分发（rootfs 内 `/etc/gponcfg/`），而这些"出厂默认"在实机上**并未被运营商修改**——先拿明文默认值去试，命中了就不用碰加密活配置。

## 4. 活配置 db_user_cfg.xml（AES）——当时没走通、后来也不需要的路

/userconfig 分区（mtd5 jffs2）里的**当前**配置是加密的：

- 文件：`/userconfig/cfg/db_user_cfg.xml`（477,340B，头魔数 `01020304`）
- 格式：60B 头 + 12B 块头（dl==cl 等长）× N + **AES 等长加密块**（非压缩；info.py 报 Type 0 ZLIB 是幌子）
- 解密函数：`db_aes_decrypt` / `db_aes_set_decrypt_key` 在 **cspd**（/bin/cspd，2.98MB，依赖 libdb.so/libdbcorecfg.so 等 25 库）；密钥设备派生（`dbCreateOuterKey` 按 DB 字段生成），zcu 已知公开密钥全灭
- 调用方：`dbcCfgFileDecry @0x1eafb0`（cspd 反汇编已生成）

当时规划的路线（均未走到，因为出厂明文默认值直接命中）：
- A：cspd 单用户跑起来 dump 堆搜 `DevAuthInfo`
- B：zxic login 的 root DES 哈希 `QTu5DMlwYapGg`（/etc/passwd）john 弱口令——⚠️ 实测 `crypt("root")` ≠ 该哈希，明文 09-02~04 会话由另一 agent 破译（用于 `su` 提权，值脱敏）
- C：ImmortalWrt 移植（以月计，放弃）
- D：web 隐藏页 `telnetCfg_gch.gch`（超管权限才能开 telnet，拿到超密后可固化）

## 5. 工具与通道清单

| 用途 | 工具/通道 |
|---|---|
| kernel1 全量获取 | U-Boot + TFTP（笔记本 enp2s0 挂 192.168.1.100/24，18.6MiB/s） |
| 双层解包 | binwalk 定位 + dd skip + gunzip（**解包校验必须本机做，串口拉的 kernel0 有位损坏**） |
| rootfs 展开 | cpio -idmv |
| 凭据搜索 | grep/grep -r（TelnetCfg / DevAuthInfo 关键词） |
| DES 哈希验证 | openssl passwd -crypt / perl crypt（verifying only） |

## 6. 一句话复盘

**四步绝杀进 root → kernel1 dump 双层解包出明文出厂配置 → TelnetCfg 给网络侧持久 shell、DevAuthInfo 给管理面夺权**——全程不需要碰 AES 活配置；"出厂默认随固件明文分发且未被改"是这个机型凭证体系的最大软肋。
