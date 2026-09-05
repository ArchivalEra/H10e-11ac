# Vendor U-Boot 2015.01 booti 排雷手册

> 平台：U-Boot 2015.01 gxl_p211_v1（当贝底包）。目标：booti 主线内核（CachyOS 7.x Image）。
> 结论先说：**排完下述五层雷后 booti 仍有一层无声失败**（疑似第六层），根治方案是改走
> boot.img/storeboot 路线（见 emmc-recipe.md）。本手册保留是因为 booti 排雷过程中产出的
> 全部 DTB/内核头知识都是 eMMC 配方的组成部分。

## 内存布局约定（实测验证）

| 地址 | 用途 |
|---|---|
| 0x01000000 | DTB（73K 填充版，内核不重定位时安全） |
| 0x01080000 | 内核 Image（**vendor 全家约定，避开 GXL 头 16MB hwrom 保留区**） |
| 0x10100000 | BL31（勿碰） |
| 0x10000000..0x10200000 | secmon/bl31 保留 |

**hwrom 是最隐蔽的雷**：内存头 16MB MMU 不映射。text_offset 改成 0x80000 会让 vendor
booti 把内核搬到 0x80000 直接 Translation fault（esr 0x96000210）。正确姿势：

- `text_offset = 0x1080000`（等于实际加载地址，跳过重定位），或
- 重编 `CONFIG_EFI_STUB=n` 的原生头内核

## 五层雷（按触发顺序）

### 层1：USB 存储

`usb start` 后 0 Storage = U 盘插错口。USB2（靠电源）才是 OTG。

### 层2：secmon 节点缺失

```
fdt_path_offset() returned FDT_ERR_NOTFOUND
[rsvmem] bl31 reserved memory set addr error
→ Synchronous Abort
```

vendor booti 启动前要在 DTB 根部找 `/secmon` 节点写 bl31 保留内存。修法——DTB 加根级节点：

```dts
secmon {
    compatible = "amlogic,secmon";
    memory-region = <&linux_secmon_pool>;
    in_base_func = <0x82000020>;
    out_base_func = <0x82000021>;
    reserve_mem_size = <0x200000>;
};
```

及 `reserved-memory/linux,secmon`（shared-dma-pool @0x10000000 size 0x400000）。
节点原形来自底包 `_aml_dtb`：gzip 壳内 AML_ 多合一容器，按 `d00dfeed`（FDT 魔数）切出。

### 层3：DTB 无 fixup 空间

```
libfdt fdt_setprop(): FDT_ERR_NOSPACE → Synchronous Abort
```

DTB 编译太紧凑，vendor booti 写属性没空间。修法：`dtc -p 32768` 加填充再重编译。

### 层4：EFI stub 头被误读

主线 7.x Image 带 EFI stub（头部 MZ/PE），vendor booti 把 PE 头字节当 ARM64 头读
`text_offset@0x08`、`image_size@0x10`——实测读到垃圾 `0x28d0000`（正是崩溃现场 x2/x3），
随后巨型 memcpy 落到未映射地址。

修法二选一：
- 重编 `CONFIG_EFI_STUB=n` 的原生头内核（推荐，见 `config/kernel-full.fragment`）
- 临时方案：RAM 里 `mw.l` 现场改头字段（`Image-vendorboot.bin` 补丁版思路）

### 层5：hwrom（见上，内存布局约定）

### 层6（未完全破案）

修完五层后 booti 仍可能无声失败返回 shell。怀疑残余在 vendor booti 私有逻辑。
**到此停止排雷**，改走 boot.img/storeboot 路线——vendor storeboot 天生认识 ANDROID!
格式，把内核做成它认识的形状比教它认识新形状便宜得多。

## 其他必知

- **自动引导链**：vendor u-boot 每次上电扫第一分区执行 `aml_autoscript`（uImage script）。
  脚本崩 → CPU reset → 再扫 = 上电死循环。拆引信：`setenv bootcmd 'echo manual-mode'; saveenv`
- **BL30 看门狗**：提示符停留 40–90 秒莫名重启。长操作一气呵成，或先想喂狗办法
- **串口洪灌**：2475 条 mw 连发打哑控制台（输入缓冲溢出），传文件用分块 + 间隔
- **主线 u-boot 替代**（B 计划，材料已囤）：p212 defconfig + clang 可编出 737KB u-boot.bin；
  FIP 打包用 `amlogic-boot-fip-e900v22c/build-fip.sh e900v22c <u-boot.bin>`；经 maskrom
  只刷 bootloader 分区。**未实测 BL1 是否接受**，启用前先小步验证
- u-boot 五件套/Armbian FAT 里的全套 bin 在 Armbian 镜像 p1（挂载 offset=4194304）
