# zigpal 与 SDLPAL 偏差清单

按 SDLPAL 主仓库 (`resources/sdlpal-master/`) 逐文件比对的结果。仅列出偏离 SDLPAL 1:1 实现的部分，不包含项目刻意不实现的功能（音频、影片、Win95 分支、YJ2 解压、PAL_CLASSIC 之外的流程、消息文件覆盖、配置菜单等）。

## HIGH — 确实会影响玩法

| # | zigpal 位置 | SDLPAL 对应 | 问题 |
|---|---|---|---|
| 1 | `script.zig` 0x0035 (ShakeScreen) | `script.c:1709-1715` | 接的是 `video.shakeScreen` 异步晃动，SDLPAL 是阻塞式 `PAL_Shake`，boss 入场看不到晃动 |
| 2 | `script.zig` 0x0096 (Ending) | `script.c:2693+` | 完全空 stub —— 通关无法播结尾动画 |
| 3 | `script.zig` 0x008D (PlayerLevelUp) | `script.c:2591` | 空 stub —— 剧情触发的强制升级（非战斗）失效 |
| 4 | `script.zig` 0x004F (FadeToRed) | `palette.c:595` | 空 —— 死亡场景的 12 步红色淡出丢失 |
| 5 | `script.zig` 0x004C (MonsterChasePlayer) | `script.c` | 空 stub —— 迷宫里怪物不追玩家 |
| 6 | `script.zig` 0x0062 / 0x0063 | `script.c:1967-1981` | 暂停/加速怪物追逐没接，`chase_speed_change_cycles` 字段从未被写 |
| 7 | `script.zig` 0x00A4 / 0x00A5 (ShowFBP / ScrollFBP) | `script.c:3038-3052` | 空 stub —— 结尾画面、过场图片缺失 |
| 8 | `fight.zig` `playerAttackAnim` (758-807) | `fight.c:2007-2263` | 严重简化：缺 `g_Battle.lpEffectSprite` blit、`rgwBattleEffectIndex`、`fSecondAttack` 偏移、滑回起点路径，DUAL_ATTACK 第二刀位置错 |
| 9 | `fight.zig` `.attack_mate` (944-963) | `fight.c:3760-3854` | 简化：随机改首选；缺 frame-8/0 setup、滑向目标、(-12,-6) 击退；Protect 减半顺序也错 |
| 10 | `fight.zig` 玩家 action 末尾 | `fight.c:4424` | 缺 `action.target = origTarget` 还原；连击 (repeat) 时取错目标 |
| 11 | `fight.zig` 敌方物攻 (1526) | `fight.c:5052-5104` | autoDefend 是减半而非完全闪避 |
| 12 | `fight.zig` 敌方物攻末 | `fight.c:5139-5146` | 缺 `wAttackEquivItem` 命中触发（毒蛇咬中毒、石化等剧情怪招） |
| 13 | `battle.zig` `initBattle` | `battle.c:1754` | 缺 `PAL_UpdateEquipments()` —— 战斗开始装备效果未应用 |
| 14 | `fight.zig` startFrame 每回合 | `fight.c:1680-1692` | 缺每回合开始的 `enemy.script_on_turn_start` 触发循环（只在 pre-battle 跑了一次） |
| 15 | `fight.zig` `allActionsSelected` | `fight.c:1446-1447` | `fPrevAutoAtk` / `fPrevPlayerAutoAtk` 未设置 → auto-attack 连续回合中断 |
| 16 | `save.zig:135` | `global.c:706+` | 加载存档时 `poison_status` 被清零 (claim "matches DOS" 但实际 SDLPAL 是保留) |
| 17 | `play.zig:90-94` | `play.c:178-191` | autoscript 循环没被 `fTrigger` 包住，场景切换时还在跑 |
| 18 | `text.zig` `~` 转义 | `text.c` | `parseInt` 读到行尾，实际游戏里多数变成 0 延迟 |

## MED — 视觉 / 边角 case

| # | zigpal 位置 | SDLPAL 对应 | 问题 |
|---|---|---|---|
| 19 | `script.zig` 0x0073 (FadeToScene) | `script.c:2229-2247` | 直接 fadeIn，缺渐入渐出的双段过渡 |
| 20 | `script.zig` 0x007F (ViewportMove) | `script.c` | 瞬间移动，应按 `operand[2]` 帧数平滑滚动 |
| 21 | `script.zig` 0x0076 (ShowFBP) | `script.c` | 空 —— 丢图片转场 |
| 22 | `fight.zig` `displayStatChange` (262-301) | `fight.c:670-712` | 玩家伤害飘字用固定 `PLAYER_POS_PUB` 坐标，应跟随 `player.pos`；缺 MP delta 显示 |
| 23 | `battleui.zig:670-683` | `uibattle.c` | 选敌人 wrap 用 `MAX_ENEMIES_IN_TEAM-1`，应用 `max_enemy_index`，光标会绕到空槽 |
| 24 | `scene.zig` `makeScene` | `scene.c PAL_MakeScene` | 没调 `applyWave` —— 海底/特殊场景的水波纹效果丢失 |
| 25 | `text.zig` 称呼检测 (489) | `text.c:1717-1719` | 检测的 `0xA1 0x47` 是 `、` 不是 `：`，对全角冒号判断错 |
| 26 | `uigame.zig:140` quitGame | `uigame.c` | 不管选 yes/no 一律忽略，缺 `PAL_AdditionalCredits + TerminateOnError` 路径 |
| 27 | `text.zig` `$` 延迟转义 (362-368) | `text.c TEXT_DisplayText` | SDLPAL 用 `wcstol` 自适应 1-3 位数字；zigpal 硬编码 2 位，单数字 (`$5 `) 时 off-by-one |
| 28 | `fight.zig` `enemySelectTarget` | `fight.c PAL_BattleEnemySelectTargetIndex` | 用统一随机；SDLPAL 是带权（偏向虚弱/濒死目标）— 待核实 |

## LOW — 细节

| # | zigpal 位置 | 问题 |
|---|---|---|
| 29 | `battle.zig:614-617` `isPlayerDying` | 用 `hp*5 < maxhp` 缺 100 的上限（仅影响 confused jitter 视觉） |
| 30 | `script.zig` PAL_RunAutoScript 分发 (194-256) | 只处理 0x0000-0x0009 / 0x003B-0x003E / 0x008E；缺 0x000A、0x0073、0x009B、0x00A0 |
| 31 | `save.zig:162` | `battle_speed` 硬编码 2；SDLPAL 写 `gpGlobals->bBattleSpeed` (1-5)，回写丢用户设置 |
| 32 | `script.zig` 0x0098 | 缺 `trail[3+i].direction` 重置 |
| 33 | `script.zig:1622` 0x00A0 | 设 quit_flag 而非 `PAL_AdditionalCredits + TerminateOnError`（libretro 生命周期约束） |
| 34 | `text.zig:495-497` `pos_icon` | 多行对话时 icon 位置漂移，缺 `bCurrentDialogLineCharCount` 字段 |
| 35 | `play.zig:43` `vanish_time` | 用 wrapping `+%`；SDLPAL 是 signed `+=`（行为通常一致） |
| 36 | `fight.zig:444-475` `postActionCheck` | 缺 `kBattleResultTerminated` 早退和 `g_Battle.fEnemyMoving = FALSE` 重置 |

## 待核实

- `fight.zig:1052` 玩家魔法元素抗性的 `resistance_multiplier` 用 1 还是 20（agent 自己也不确定，但与 SDLPAL 调用形式一致，应 OK）
- `fight.zig:1430` `enemySelectTarget` 是否真的是带权随机（需查 SDLPAL `PAL_BattleEnemySelectTargetIndex` 完整定义）
- `global.zig:addPoisonForPlayer` 的 resistance 检查公式
- `uigame.zig:189-192` 音乐/音效菜单切换是否影响存档字段

## 推进顺序建议

1. **结尾相关**：#2 (0x0096), #7 (0x00A4/A5), #4 (0x004F)
2. **战斗装备 / 自动战斗**：#13, #14, #15
3. **场景过渡**：#17 (autoscript 门控), #19, #20
4. **战斗细节**：#8, #10, #11, #12
5. **存档**：#16
6. **视觉小修**：#22, #23, #24
