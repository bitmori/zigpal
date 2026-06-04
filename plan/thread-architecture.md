# 方案：阻塞线程 + retro_run 无锁架构

## 动机

SDLPAL 的所有游戏逻辑（菜单、对话、战斗、脚本延迟）都是阻塞式同步代码。把它展开成状态机工作量巨大且容易出错。SDLPAL libretro 版本的方案是用独立线程自由运行游戏逻辑，主线程只负责采样画面和注入输入。我们采用同样的架构，这样可以逐行翻译 SDLPAL 的 C 代码到 Zig。

## 架构概览

```
游戏线程（自由运行）：               主线程（retro_run，60fps）：
┌─────────────────────────┐        ┌───────────────────────────┐
│ PAL_GameMain:           │        │ retro_run():              │
│   while (true):         │        │   input_poll()            │
│     PAL_DelayUntil()  ←─╋──tick──╋── pumpJoypadInput()      │
│     PAL_LoadResources() │        │   video_cb(framebuffer) ←─╋── 直接读
│     PAL_StartFrame()    │        │                           │
│       PAL_GameUpdate()  │        │ frame_time_callback():    │
│       PAL_MakeScene()   │        │   ticks += usec/1000     │
│       UpdateScreen() ──→╋──写──→ │                           │
│       if (menu):        │        └───────────────────────────┘
│         PAL_InGameMenu()│
│           (阻塞循环)    │
│           UpdateScreen()│──写→ framebuffer
└─────────────────────────┘
```

无 mutex，无 condvar，无帧同步。和 SDLPAL libretro 版完全一致。

## 线程模型（照抄 SDLPAL libretro）

**无帧同步，游戏线程自由运行。** 和 SDLPAL libretro 版完全一致：

- 游戏线程用虚拟时间 (`getTicks()`) 自己做帧率控制
- `retro_run()` 只是采样当前 framebuffer 内容发给前端
- 两个线程之间没有 mutex/condvar 同步
- 游戏线程通过 `VIDEO_UpdateScreen` 把渲染结果 blit 到共享的 RGB565 surface
- `retro_run()` 直接读这个 surface 发给前端（可能偶尔采样到半帧，但 60fps 下不明显）

```
游戏线程：                        主线程：
┌─────────────────────┐          ┌──────────────────────┐
│ while(true):        │          │ retro_run():         │
│   PAL_DelayUntil()  │←tick控制 │   input_poll()       │
│   PAL_StartFrame()  │          │   pump_joypad()      │
│     渲染到 screen   │          │   RefreshVideo()     │←直接读surface
│     UpdateScreen()  │──blit──→ │   video_cb(surface)  │
│     处理输入        │←事件注入─│                      │
└─────────────────────┘          └──────────────────────┘
```

## 共享数据

游戏线程和主线程通过以下共享数据通信（无锁，和 SDLPAL 一致）：

| 数据 | 写入方 | 读取方 | 说明 |
|------|--------|--------|------|
| `surface[320×200] u16` | 游戏线程 | 主线程 | RGB565 最终帧缓冲 |
| SDL 事件队列 | 主线程 | 游戏线程 | 输入事件通过 `SDL_PrivateKeyboard` 注入 |

- 游戏线程在 `VIDEO_UpdateScreen` 时把 8-bit screen + palette 转换为 RGB565 写入 surface
- 主线程在 `retro_run` 时直接读 surface 发给前端
- 输入通过注入 SDL 键盘事件传递（游戏线程用 SDL 事件循环读取）

由于我们不用 SDL，简化为：
| 数据 | 写入方 | 读取方 | 说明 |
|------|--------|--------|------|
| `framebuffer[320×200] u16` | 游戏线程 | 主线程 | RGB565 帧 |
| `palette565[256] u16` | 游戏线程 | 游戏线程 | 预计算 RGB565 调色板 |
| `input_keys: u32` | 主线程 | 游戏线程 | 当前按键状态位图 |
| `prev_keys: u32` | 游戏线程 | 游戏线程 | 上一帧按键（边沿检测） |

### 调色板优化

调色板直接存储 RGB565 格式（`[256]u16`），而不是 RGB888。这样 `VIDEO_UpdateScreen` 每像素只需一次查表，无需逐像素做颜色转换：

```zig
// VIDEO_UpdateScreen 核心循环
for (0..320 * 200) |i| {
    framebuffer[i] = palette565[screen[i]];
}
```

RGB888 → RGB565 转换只在调色板变化时做一次（`setPalette` / fade 每步）：
```zig
pub fn setPalette(rgb: [256]Color) void {
    for (0..256) |i| {
        palette565[i] = (@as(u16, rgb[i].r >> 3) << 11) |
                        (@as(u16, rgb[i].g >> 2) << 5) |
                        @as(u16, rgb[i].b >> 3);
    }
}
```

## 时间系统

SDLPAL libretro 版用 `RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK` 获取每帧经过的微秒数，累加到 `ticks` 变量。`SDL_GetTicks()` 被重定向到读这个变量（通过 `pal_config.h` 里的宏 `#define SDL_GetTicks SDL_GetTicksReal`）。

我们的实现：

```zig
var ticks: u32 = 0;
var speed_scale: f64 = 1.0;

// retro_run 中调用（由 frame_time_callback 驱动）
pub fn frameTick(usec: i64) void {
    ticks += @intFromFloat(speed_scale * @as(f64, @floatFromInt(usec)) / 1000.0);
}

// 替代 SDL_GetTicks — 游戏线程调用
pub fn getTicks() u32 {
    return ticks;
}
```

`PAL_DelayUntil(dwTime)` 的实现（游戏线程中）：
```zig
pub fn delayUntil(target: u32) void {
    while (getTicks() < target) {
        // 让出 CPU 时间片，等主线程推进 ticks
        std.Thread.yield() catch {};
    }
}
```

关键：游戏线程的帧率完全由虚拟时间控制。`FRAME_TIME = 100ms`（10fps），每次 retro_run 推进约 16ms。所以游戏线程每 ~6 次 retro_run 调用后才会有足够的虚拟时间完成一帧游戏逻辑。

## 分层结构

两层分离设计：

```
┌───────────────────────────────────────────┐
│  Layer 1: libretro shim (薄层)             │
│  src/libretro_core.zig                    │
│  - libretro API exports                   │
│  - 创建游戏线程                            │
│  - pump joypad → 写入共享 input           │
│  - 读 framebuffer → video_cb              │
│  - frame_time_callback → 推进虚拟时间      │
└───────────────────────────────────────────┘
                    ↕ 调用 PAL API
┌───────────────────────────────────────────┐
│  Layer 2: SDLPAL 完整 Zig 翻译            │
│  (纯游戏逻辑，不知道 libretro 的存在)      │
│                                           │
│  main.zig          — PAL_GameMain          │
│  play.zig          — PAL_StartFrame        │
│  script.zig        — PAL_RunTrigger/Auto   │
│  menu.zig          — PAL_InGameMenu        │
│  battle.zig        — PAL_StartBattle       │
│  fight.zig         — 战斗动作              │
│  ui.zig            — PAL_CreateBox 等      │
│  global.zig        — 全局状态/数据结构      │
│  res.zig           — PAL_LoadResources     │
│  scene.zig         — PAL_MakeScene         │
│  video.zig         — VIDEO_UpdateScreen    │
│  input.zig         — PAL_ProcessEvent      │
│  util.zig          — UTIL_Delay 等         │
│  text.zig          — PAL_ShowDialogText    │
│  palette.zig       — PAL_FadeIn/Out        │
└───────────────────────────────────────────┘
                    ↕ 使用基础设施
┌───────────────────────────────────────────┐
│  基础设施（已有，保留）                     │
│  src/palcommon.zig  — MKF, Surface, RLE   │
│  src/yj1.zig       — YJ1 解压            │
│  src/map.zig       — 地图加载/瓦片        │
│  src/font.zig      — Big5 字体           │
│  src/bdf.zig       — BDF 字体            │
└───────────────────────────────────────────┘
```

**Layer 2 的设计原则：**
- 和 SDLPAL 的 C 代码一一对应，同样的函数名、同样的逻辑流
- 通过一个 "platform" 接口与外界通信（获取时间、读输入、输出画面）
- 可以脱离 libretro 独立测试（比如对接一个 SDL 窗口或命令行 dump）

**Platform 接口（Layer 2 对外部的依赖）：**
```zig
pub const Platform = struct {
    getTicks: *const fn () u32,
    processEvents: *const fn () void,  // 处理输入事件
    getInput: *const fn () InputState,
    updateScreen: *const fn (surface: *Surface) void, // 输出一帧
    delay: *const fn (ms: u32) void,
};
```

Layer 1 (libretro shim) 提供这些函数的具体实现。

## 文件结构

所有文件平铺在 `src/` 下，`libretro_core.zig` 是 shim 入口，其余是 SDLPAL 翻译和基础设施：

```
src/
├── libretro_core.zig     # Layer 1: libretro shim
│
│  # Layer 2: SDLPAL Zig 翻译
├── main.zig              # PAL_GameMain, 游戏线程入口
├── play.zig              # PAL_StartFrame, PAL_GameUpdate, PAL_Search
├── script.zig            # PAL_RunTriggerScript, PAL_RunAutoScript, 全部opcode
├── menu.zig              # PAL_InGameMenu 及所有子菜单
├── battle.zig            # PAL_StartBattle, PAL_BattleMain
├── fight.zig             # 战斗动作执行
├── ui.zig                # PAL_CreateBox, PAL_ReadMenu, 数字绘制
├── global.zig            # 全局状态结构 (GlobalVars, Object, etc.)
├── res.zig               # PAL_LoadResources
├── scene.zig             # PAL_MakeScene, PAL_UpdateParty
├── video.zig             # VIDEO_UpdateScreen
├── input.zig             # PAL_ClearKeyState, PAL_ProcessEvent
├── text.zig              # PAL_ShowDialogText, 对话系统
├── palette.zig           # PAL_FadeIn, PAL_FadeOut, PAL_SetPalette
├── util.zig              # UTIL_Delay, 随机数等
│
│  # 基础设施
├── palcommon.zig         # MKF, Surface, RLE sprite
├── yj1.zig              # YJ1 解压
├── map.zig              # 地图加载（被 scene.zig 使用）
├── font.zig             # Big5 字体
└── bdf.zig              # BDF 字体（debug用）
```

删除的文件（旧状态机实现）：
- `game.zig`, `field.zig` — 被 `main.zig` + `play.zig` 替代
- `game_context.zig` — 数据结构移入 `global.zig`
- 旧 `script.zig` — 完整重写
- 旧 `scene.zig` — 拆分：渲染逻辑留在 `scene.zig`，地图加载留在 `map.zig`
- `anime.zig` — 合并到 `palette.zig`（淡入淡出）和 `video.zig`

## 翻译策略

**核心原则：逐行对照 SDLPAL 的 C 代码翻译，保持相同的函数名、变量名、逻辑结构。**

对照示例 — `PAL_GameUpdate` (play.c):

```c
// SDLPAL C 版本
if (gpGlobals->fEnteringScene) {
    gpGlobals->fEnteringScene = FALSE;
    i = gpGlobals->wNumScene - 1;
    gpGlobals->g.rgScene[i].wScriptOnEnter = 
        PAL_RunTriggerScript(gpGlobals->g.rgScene[i].wScriptOnEnter, 0xFFFF);
    if (gpGlobals->fEnteringScene) return;
    PAL_ClearKeyState();
    PAL_MakeScene();
}
```

```zig
// Zig 翻译版本
if (globals.entering_scene) {
    globals.entering_scene = false;
    const i = globals.num_scene - 1;
    globals.g.scenes[i].script_on_enter = 
        runTriggerScript(globals.g.scenes[i].script_on_enter, 0xFFFF);
    if (globals.entering_scene) return;
    clearKeyState();
    makeScene();
}
```

**`VIDEO_UpdateScreen` → 用预计算的 `palette565[256]` 查表，把 index buffer 写入共享 RGB565 framebuffer。**

**`UTIL_Delay(ms)` → busy-wait 循环检查虚拟时间，让出 CPU 时间片。**

**`PAL_ProcessEvent` / 输入读取 → 从共享 input_keys 变量读取当前按键状态。**

## 不支持的内容

- **Win95 版**：所有 `gConfig.fIsWIN95`、YJ2 解压、Win95 特有消息格式等代码不翻译，只支持 DOS 版
- **音乐/音效/影片**：不实现音频播放、MIDI、OPL、AVI 等
- **触屏 overlay**：不实现
- **网络/多语言**：不实现

## retro_run 主线程流程

```zig
export fn retro_run() void {
    if (input_poll_cb) |poll| poll();
    
    // 把 joypad 状态写入共享变量（游戏线程读取）
    pumpJoypadInput();
    
    // 直接把当前 framebuffer 发给前端（游戏线程可能正在写，不管）
    if (video_cb) |cb| {
        cb(&framebuffer, 320, 200, 320 * 2);
    }
}
```

虚拟时间由 `frame_time_callback` 推进（libretro 前端每帧回调），不在 retro_run 里手动累加。

## 与当前代码的关系

- **保留**：所有渲染基础设施（palcommon, palette, yj1, font, bdf, text, map, scene, ui, anime）
- **保留**：game_context.zig 中的数据结构定义（GlobalVars, Object, EventObject 等）
- **重写**：所有游戏逻辑（从阻塞式 C 直接翻译，不再用状态机）
- **删除**：当前的 game.zig, field.zig, menu.zig, input.zig, script.zig 中的状态机逻辑

## 移植顺序

1. **基础框架**：frame_sync.zig + libretro_core.zig（线程创建/同步） + pal_util.zig（yieldFrame, delay, input）
2. **主循环**：pal_main.zig（PAL_GameMain → PAL_LoadResources → PAL_StartFrame）
3. **场景逻辑**：pal_play.zig（PAL_GameUpdate, PAL_Search, PAL_UpdateParty）
4. **脚本系统**：pal_script.zig（完整的 PAL_RunTriggerScript + PAL_RunAutoScript + PAL_InterpretInstruction，所有 ~165 个 opcode）
5. **菜单系统**：pal_menu.zig（PAL_InGameMenu 全部子菜单 + 物品使用/装备逻辑）
6. **战斗系统**：pal_battle.zig + pal_fight.zig
7. **存档系统**：PAL_SaveGame / PAL_LoadGame

每步完成后都可以编译测试。

## 风险与注意事项

1. **数据竞争**：framebuffer 可能被同时读写，但和 SDLPAL 一样可接受（最多偶尔画面撕裂一帧）
2. **input_keys 竞争**：主线程写、游戏线程读，同为 u32 原子宽度，实际无害
3. **退出清理**：retro_unload_game 设 `quit = true`，游戏线程检测后退出，主线程 join
4. **macOS pthread**：Zig 的 `std.Thread.spawn` 即可，不需要 pthread（之前 game_thread.zig 验证了 pthread 也可行）
5. **游戏线程死循环**：如果虚拟时间不推进（frame_time_callback 不被调），游戏线程会卡在 delayUntil。只要前端正常调 retro_run 就不会发生

## 优势

- 可以**逐行翻译** SDLPAL，减少引入 bug 的机会
- 不需要把阻塞逻辑展开成状态机，大幅减少工作量
- 菜单/对话/战斗等嵌套调用保持原有结构，代码更清晰
- SDLPAL libretro 版已验证这个架构可行
- 无帧同步开销，实现更简单
