# zigpal

仙剑奇侠传 DOS 版的 Zig 重写，作为 [libretro](https://www.libretro.com/) 核心运行（如 RetroArch）。基于 [SDLPAL](https://github.com/sdlpal/sdlpal) 的算法和数据格式还原，但代码用 Zig 从零写就。

## 状态

可玩——开场动画、片头、剧情、战斗、地图、菜单、商店、当铺、存档、片尾全跑通。
**音频** 还没接入；等 RIX/AdPlug 集成后会变成完整体验。

## 构建（macOS）

需要 [Zig 0.16.0](https://ziglang.org/download/)。

```sh
zig build -Doptimize=ReleaseFast
```

产物：`zig-out/lib/libzigpal_libretro.dylib`

## 安装到 RetroArch

1. 把 `libzigpal_libretro.dylib` 放到 RetroArch 的 cores 目录（macOS：`~/Library/Application Support/RetroArch/cores/`）
2. 把仙剑游戏数据文件放到 RetroArch 的 system/pal/ 目录：
   ```
   ~/Documents/RetroArch/system/pal/
   ├── ABC.MKF
   ├── BALL.MKF
   ├── DATA.MKF
   ├── F.MKF
   ├── FBP.MKF
   ├── FIRE.MKF
   ├── GOP.MKF
   ├── M.MSG
   ├── MAP.MKF
   ├── MGO.MKF
   ├── PAT.MKF
   ├── RGM.MKF
   ├── RNG.MKF
   ├── SSS.MKF
   ├── WOR16.ASC
   ├── WOR16.FON
   ├── WORD.DAT
   ├── desc.json   ← 物品/法术描述（本仓库 resources/desc.json）
   └── zpix.bdf    ← 屏幕字体（从下方链接下载）
   ```
   `zpix.bdf` 从 [SolidZORO/zpix-pixel-font v3.1.11](https://github.com/SolidZORO/zpix-pixel-font/releases/tag/v3.1.11) 下载（任意更高版本应也兼容）。

3. RetroArch → Load Core → 选 zigpal → Start Core

## 开发参考

- [SDLPAL 上游 C 源码](https://github.com/sdlpal/sdlpal) —— 移植参考
- [`plan/SDLPAL_XREF.md`](plan/SDLPAL_XREF.md) —— zig 函数 ↔ SDLPAL C 函数的逐行对照表
- [`plan/SDLPAL_DEVIATIONS.md`](plan/SDLPAL_DEVIATIONS.md) —— 与 SDLPAL 实现不同之处的记录
- [`plan/thread-architecture.md`](plan/thread-architecture.md) —— libretro 线程模型说明

## 兄弟项目

- [bitmori/PalLibrary](https://github.com/bitmori/PalLibrary) —— 仙剑数据格式 codec 库（YJ1/YJ2/RLE/RNG），用于将来的 mod 编辑器

## 协议

GPL v3（与 SDLPAL 保持一致）。详见各源文件 header。
