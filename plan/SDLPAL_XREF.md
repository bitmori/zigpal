# SDLPAL ↔ Zigpal Cross-Reference

This document maps every top-level function (and every opcode `case` in `script.zig`'s
dispatchers) in the zigpal Zig source to its counterpart in the SDLPAL C source under
`resources/sdlpal-master/`. It is intended as an audit aid: the **Notes** column flags
obvious stubs / incomplete ports / libretro-specific glue, but does **not** assert that
non-flagged entries are bit-for-bit faithful — verifying that is the auditor's job.

Conventions:

- **Zigpal column** — `[name](src/file.zig#LXX) — kind` where *kind* is `fn`, `pub fn`,
  `pub inline fn`, or `case 0xNN` for opcode dispatch arms.
- **SDLPAL column** — `[PAL_Name](resources/sdlpal-master/file.c#LYY)` for direct
  counterparts, `inside [PAL_Outer](file.c#L...)` for inlined helpers, `case 0xNN`
  for opcode arms inside `PAL_InterpretInstruction` / `PAL_RunTriggerScript` /
  `PAL_RunAutoScript`, or `—` if no counterpart exists.
- **Notes column** — short hint such as *stub*, *audio skipped*, *libretro-only*,
  *zigpal-specific*, *Stage N marker*, *unimplemented opcode*, etc. Empty cell means
  the body looked substantive and shaped like the SDLPAL counterpart.

The opcode dispatcher in `src/script.zig` (`interpretInstruction`, `runTriggerScript`,
`runAutoScript`) is enumerated case-by-case so each opcode can be diffed against the
matching arm of `PAL_InterpretInstruction` / `PAL_RunTriggerScript` / `PAL_RunAutoScript`
in `resources/sdlpal-master/script.c`.

---

## battle.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [getPlayerBattleSprite](src/battle.zig#L249) — pub fn | [PAL_GetPlayerBattleSprite](resources/sdlpal-master/global.c#L1978) | |
| [freeBattleSprites](src/battle.zig#L259) — fn | [PAL_FreeBattleSprites](resources/sdlpal-master/battle.c#L807) | |
| [decompressMkfChunk](src/battle.zig#L274) — fn | inside [PAL_LoadBattleSprites](resources/sdlpal-master/battle.c#L856) | helper around `PAL_MKFDecompressChunk` |
| [loadBattleSprites](src/battle.zig#L286) — pub fn | [PAL_LoadBattleSprites](resources/sdlpal-master/battle.c#L856) | |
| [loadBattleBackground](src/battle.zig#L325) — fn | [PAL_LoadBattleBackground](resources/sdlpal-master/battle.c#L949) | |
| [initBattle](src/battle.zig#L336) — fn | inside [PAL_StartBattle](resources/sdlpal-master/battle.c#L1531) | initialisation prefix |
| [freeBattle](src/battle.zig#L438) — fn | inside [PAL_StartBattle](resources/sdlpal-master/battle.c#L1531) | cleanup epilog |
| [battleStartFrame](src/battle.zig#L449) — fn | [PAL_BattleStartFrame](resources/sdlpal-master/fight.c#L1073) | wraps `fight.startFrame` + UI update |
| [flagPlayerFleeing](src/battle.zig#L459) — pub fn | inside [PAL_BattleCommitAction](resources/sdlpal-master/fight.c#L1811) | sets `g_battle.flee` flag |
| [battleMain](src/battle.zig#L463) — fn | [PAL_BattleMain](resources/sdlpal-master/battle.c#L685) | |
| [battleDrawBackground](src/battle.zig#L508) — fn | [PAL_BattleDrawBackground](resources/sdlpal-master/battle.c#L34) | |
| [drawEnemySprites](src/battle.zig#L531) — fn | [PAL_BattleDrawEnemySprites](resources/sdlpal-master/battle.c#L86) | |
| [drawPlayerSprites](src/battle.zig#L561) — fn | [PAL_BattleDrawPlayerSprites](resources/sdlpal-master/battle.c#L143) | |
| [drawMagicSprite](src/battle.zig#L606) — fn | [PAL_BattleDrawMagicSprites](resources/sdlpal-master/battle.c#L216) | |
| [isPlayerDying](src/battle.zig#L618) — pub fn | [PAL_IsPlayerDying](resources/sdlpal-master/fight.c#L29) | duplicated in fight.zig |
| [clearSpriteObject](src/battle.zig#L626) — pub fn | [PAL_BattleClearSpriteObject](resources/sdlpal-master/battle.c#L248) | |
| [spriteAddUnlock](src/battle.zig#L632) — pub fn | [PAL_BattleSpriteAddUnlock](resources/sdlpal-master/battle.c#L272) | |
| [addSpriteObject](src/battle.zig#L638) — pub fn | [PAL_BattleAddSpriteObject](resources/sdlpal-master/battle.c#L282) | |
| [addFighterSpriteObject](src/battle.zig#L653) — fn | [PAL_BattleAddFighterSpriteObject](resources/sdlpal-master/battle.c#L361) | |
| [sortSpriteObjectByPos](src/battle.zig#L672) — fn | [PAL_BattleSortSpriteObjecByPos](resources/sdlpal-master/battle.c#L409) | |
| [drawAllSpritesWithColorShift](src/battle.zig#L700) — fn | [PAL_BattleDrawAllSpritesWithColorShift](resources/sdlpal-master/battle.c#L505) | |
| [battleFadeScene](src/battle.zig#L720) — pub fn | [PAL_BattleFadeScene](resources/sdlpal-master/battle.c#L609) | |
| [battleMakeScene](src/battle.zig#L765) — pub fn | [PAL_BattleMakeScene](resources/sdlpal-master/battle.c#L565) | |
| [startBattle](src/battle.zig#L782) — pub fn | [PAL_StartBattle](resources/sdlpal-master/battle.c#L1531) | audio skipped |

## battleui.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [isActionValid](src/battleui.zig#L57) — fn | [PAL_BattleUIIsActionValid](resources/sdlpal-master/uibattle.c#L272) | PAL_CLASSIC subset |
| [drawMiscMenu](src/battleui.zig#L78) — fn | [PAL_BattleUIDrawMiscMenu](resources/sdlpal-master/uibattle.c#L344) | |
| [miscMenuUpdate](src/battleui.zig#L98) — fn | [PAL_BattleUIMiscMenuUpdate](resources/sdlpal-master/uibattle.c#L417) | |
| [miscItemSubMenuUpdate](src/battleui.zig#L117) — fn | [PAL_BattleUIMiscItemSubMenuUpdate](resources/sdlpal-master/uibattle.c#L472) | |
| [playerReady](src/battleui.zig#L145) — pub fn | [PAL_BattleUIPlayerReady](resources/sdlpal-master/uibattle.c#L582) | |
| [showNum](src/battleui.zig#L153) — pub fn | [PAL_BattleUIShowNum](resources/sdlpal-master/uibattle.c#L1770) | |
| [drawPlayerInfoBoxes](src/battleui.zig#L170) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | helper |
| [drawEnemyHighlight](src/battleui.zig#L179) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | helper |
| [drawCurrentPlayerArrow](src/battleui.zig#L194) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | helper |
| [drawSelectedPlayerArrow](src/battleui.zig#L206) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | helper |
| [drawActionIcons](src/battleui.zig#L218) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | bottom-row icons |
| [pickAutoMagic](src/battleui.zig#L257) — fn | [PAL_BattleUIPickAutoMagic](resources/sdlpal-master/uibattle.c#L722) | |
| [update](src/battleui.zig#L279) — pub fn | [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | PAL_CLASSIC state machine |
| [handleMainMenuKeys](src/battleui.zig#L419) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | input handler |
| [handleMagicSelected](src/battleui.zig#L519) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | magic submenu |
| [uiUseItem](src/battleui.zig#L543) — fn | [PAL_BattleUIUseItem](resources/sdlpal-master/uibattle.c#L624) | |
| [uiThrowItem](src/battleui.zig#L562) — fn | [PAL_BattleUIThrowItem](resources/sdlpal-master/uibattle.c#L675) | |
| [handleMiscSelection](src/battleui.zig#L584) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | misc menu dispatch |
| [handleMiscItemSubSelection](src/battleui.zig#L603) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | use/throw dispatch |
| [targetEnemyState](src/battleui.zig#L618) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | target-enemy state arm |
| [targetPlayerState](src/battleui.zig#L692) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | target-player state arm |
| [drawShowNumbers](src/battleui.zig#L733) — fn | inside [PAL_BattleUIUpdate](resources/sdlpal-master/uibattle.c#L785) | float-up damage numbers |

## bdf.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [parseIntFromLine](src/bdf.zig#L88) — fn | — | zigpal-specific (BDF font parser) |
| [load](src/bdf.zig#L96) — pub fn | — | zigpal-specific (BDF font parser) |

## debug.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [ensureFont](src/debug.zig#L36) — pub fn | — | zigpal-specific debug overlay |
| [toggle](src/debug.zig#L54) — pub fn | — | zigpal-specific debug overlay |
| [requestMenu](src/debug.zig#L64) — pub fn | — | zigpal-specific debug overlay |
| [pollMenuRequest](src/debug.zig#L68) — pub fn | — | zigpal-specific debug overlay |
| [actionStartBattle](src/debug.zig#L88) — fn | — | debug action |
| [pickEnemyTeam](src/debug.zig#L95) — fn | — | debug action |
| [actionToggleOverlay](src/debug.zig#L265) — fn | — | debug action |
| [actionOpenPawnShop](src/debug.zig#L270) — fn | — | debug action |
| [actionRandomShop](src/debug.zig#L274) — fn | — | debug action |
| [actionLearnMagic](src/debug.zig#L289) — fn | — | debug action |
| [actionGetItem](src/debug.zig#L307) — fn | — | debug action |
| [actionPartyEdit](src/debug.zig#L329) — fn | — | debug action |
| [isMagicObject](src/debug.zig#L342) — fn | — | debug helper |
| [isItemObject](src/debug.zig#L346) — fn | — | debug helper |
| [pickPartyMember](src/debug.zig#L353) — fn | — | debug helper |
| [partyEditMenu](src/debug.zig#L390) — fn | — | debug action |
| [playerSlot](src/debug.zig#L464) — fn | — | debug helper |
| [togglePartyMember](src/debug.zig#L472) — fn | — | debug helper |
| [showMenu](src/debug.zig#L494) — fn | — | debug menu (zigpal-specific) |
| [drawPixel](src/debug.zig#L575) — fn | — | overlay primitive |
| [drawHLine](src/debug.zig#L580) — fn | — | overlay primitive |
| [drawVLine](src/debug.zig#L585) — fn | — | overlay primitive |
| [drawRect](src/debug.zig#L590) — fn | — | overlay primitive |
| [drawTileDiamond](src/debug.zig#L601) — fn | — | overlay primitive |
| [drawText](src/debug.zig#L615) — fn | — | overlay primitive |
| [drawOverlay](src/debug.zig#L622) — pub fn | — | zigpal-specific debug overlay |
| [drawTileGrid](src/debug.zig#L637) — fn | loosely [PAL_ShowSearchTriggerRange](resources/sdlpal-master/paldebug.c#L26) | zigpal-specific overlay |
| [drawEventObjects](src/debug.zig#L672) — fn | — | overlay rendering |
| [drawPartyMarker](src/debug.zig#L700) — fn | — | overlay rendering |
| [drawStatusLine](src/debug.zig#L707) — fn | — | overlay rendering |

## fight.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [isPlayerDying](src/fight.zig#L32) — pub fn | [PAL_IsPlayerDying](resources/sdlpal-master/fight.c#L29) | |
| [isPlayerHealthy](src/fight.zig#L39) — pub fn | [PAL_IsPlayerHealthy](resources/sdlpal-master/fight.c#L52) | |
| [battleSelectAutoTargetFrom](src/fight.zig#L49) — pub fn | [PAL_BattleSelectAutoTargetFrom](resources/sdlpal-master/fight.c#L87) | |
| [battleSelectAutoTarget](src/fight.zig#L72) — pub fn | [PAL_BattleSelectAutoTarget](resources/sdlpal-master/fight.c#L79) | |
| [calcBaseDamage](src/fight.zig#L78) — fn | [PAL_CalcBaseDamage](resources/sdlpal-master/fight.c#L131) | |
| [calcMagicDamage](src/fight.zig#L96) — fn | [PAL_CalcMagicDamage](resources/sdlpal-master/fight.c#L174) | |
| [detectMagicTargetChange](src/fight.zig#L138) — fn | [FIGHT_DetectMagicTargetChange](resources/sdlpal-master/fight.c#L3552) | |
| [checkHidingEffect](src/fight.zig#L159) — fn | [PAL_BattleCheckHidingEffect](resources/sdlpal-master/fight.c#L3511) | PAL_CLASSIC branch |
| [calcPhysicalAttackDamage](src/fight.zig#L168) — pub fn | [PAL_CalcPhysicalAttackDamage](resources/sdlpal-master/fight.c#L253) | |
| [getEnemyDexterity](src/fight.zig#L176) — fn | [PAL_GetEnemyDexterity](resources/sdlpal-master/fight.c#L289) | |
| [getPlayerActualDexterity](src/fight.zig#L184) — fn | [PAL_GetPlayerActualDexterity](resources/sdlpal-master/fight.c#L336) | |
| [renderFrame](src/fight.zig#L195) — fn | inside [PAL_BattleDelay](resources/sdlpal-master/fight.c#L469) | per-frame redraw helper |
| [battleDelay](src/fight.zig#L230) — pub fn | [PAL_BattleDelay](resources/sdlpal-master/fight.c#L469) | |
| [backupStat](src/fight.zig#L246) — pub fn | [PAL_BattleBackupStat](resources/sdlpal-master/fight.c#L561) | |
| [displayStatChange](src/fight.zig#L262) — pub fn | [PAL_BattleDisplayStatChange](resources/sdlpal-master/fight.c#L603) | |
| [updateFighters](src/fight.zig#L323) — pub fn | [PAL_BattleUpdateFighters](resources/sdlpal-master/fight.c#L916) | |
| [postActionCheck](src/fight.zig#L363) — pub fn | [PAL_BattlePostActionCheck](resources/sdlpal-master/fight.c#L719) | |
| [commitAction](src/fight.zig#L522) — pub fn | [PAL_BattleCommitAction](resources/sdlpal-master/fight.c#L1811) | |
| [refundUiActionConsumables](src/fight.zig#L609) — pub fn | inside [PAL_BattleCommitAction](resources/sdlpal-master/fight.c#L1811) | refund helper |
| [playerCheckReady](src/fight.zig#L637) — pub fn | [PAL_BattlePlayerCheckReady](resources/sdlpal-master/fight.c#L1023) | |
| [allActionsSelected](src/fight.zig#L669) — fn | inside [PAL_BattleStartFrame](resources/sdlpal-master/fight.c#L1073) | "all decided" branch |
| [validateAction](src/fight.zig#L768) — fn | [PAL_BattlePlayerValidateAction](resources/sdlpal-master/fight.c#L3249) | |
| [playerAttackAnim](src/fight.zig#L786) — fn | [PAL_BattleShowPlayerAttackAnim](resources/sdlpal-master/fight.c#L2008) | |
| [playerPerformAction](src/fight.zig#L981) — pub fn | [PAL_BattlePlayerPerformAction](resources/sdlpal-master/fight.c#L3577) | |
| [getFleeRateAvg](src/fight.zig#L1539) — fn | inside [PAL_BattlePlayerPerformAction](resources/sdlpal-master/fight.c#L3577) | flee rate helper |
| [enemySelectTarget](src/fight.zig#L1554) — fn | [PAL_BattleEnemySelectTargetIndex](resources/sdlpal-master/fight.c#L4520) | |
| [enemyPerformAction](src/fight.zig#L1571) — pub fn | [PAL_BattleEnemyPerformAction](resources/sdlpal-master/fight.c#L4551) | |
| [enemySelectEnemyTarget](src/fight.zig#L1850) — fn | [PAL_BattleEnemySelectEnemyTargetIndex](resources/sdlpal-master/fight.c#L4489) | |
| [enemyPerformMagicAction](src/fight.zig#L1865) — fn | inside [PAL_BattleEnemyPerformAction](resources/sdlpal-master/fight.c#L4551) | enemy magic branch (fight.c L4656) |
| [playerEscape](src/fight.zig#L2048) — pub fn | [PAL_BattlePlayerEscape](resources/sdlpal-master/battle.c#L1438) | audio skipped |
| [battleFrameMagic](src/fight.zig#L2113) — fn | inside [PAL_BattleShowPlayerOffMagicAnim](resources/sdlpal-master/fight.c#L2609) | per-frame magic redraw |
| [battleShowPlayerOffMagicAnim](src/fight.zig#L2123) — pub fn | [PAL_BattleShowPlayerOffMagicAnim](resources/sdlpal-master/fight.c#L2609) | |
| [blitMagicResidueToBackground](src/fight.zig#L2266) — fn | inside [PAL_BattleShowPlayerOffMagicAnim](resources/sdlpal-master/fight.c#L2609) | residue blit (fight.c L2757) |
| [battleShowEnemyMagicAnim](src/fight.zig#L2282) — pub fn | [PAL_BattleShowEnemyMagicAnim](resources/sdlpal-master/fight.c#L2847) | |
| [battleShowPlayerDefMagicAnim](src/fight.zig#L2417) — pub fn | [PAL_BattleShowPlayerDefMagicAnim](resources/sdlpal-master/fight.c#L2448) | |
| [battleShowPlayerPreMagicAnim](src/fight.zig#L2512) — pub fn | [PAL_BattleShowPlayerPreMagicAnim](resources/sdlpal-master/fight.c#L2338) | |
| [battleShowPlayerSummonMagicAnim](src/fight.zig#L2580) — pub fn | [PAL_BattleShowPlayerSummonMagicAnim](resources/sdlpal-master/fight.c#L3072) | |
| [battleShowPlayerUseItemAnim](src/fight.zig#L2661) — pub fn | [PAL_BattleShowPlayerUseItemAnim](resources/sdlpal-master/fight.c#L2266) | |
| [battleShowPostMagicAnim](src/fight.zig#L2697) — pub fn | [PAL_BattleShowPostMagicAnim](resources/sdlpal-master/fight.c#L3190) | |
| [enemyEscape](src/fight.zig#L2728) — pub fn | [PAL_BattleEnemyEscape](resources/sdlpal-master/battle.c#L1376) | audio skipped |
| [battleSimulateMagic](src/fight.zig#L2756) — pub fn | [PAL_BattleSimulateMagic](resources/sdlpal-master/fight.c#L5301) | |
| [showGetDialog](src/fight.zig#L2799) — pub fn | inside [PAL_BattleStealFromEnemy](resources/sdlpal-master/fight.c#L5193) | shared "得到 ..." helper |
| [battleStealFromEnemy](src/fight.zig#L2822) — pub fn | [PAL_BattleStealFromEnemy](resources/sdlpal-master/fight.c#L5193) | |
| [battleWon](src/fight.zig#L2886) — pub fn | [PAL_BattleWon](resources/sdlpal-master/battle.c#L991) | level-up dialog stubbed (comments only) |
| [checkHiddenExp](src/fight.zig#L3178) — fn | inside [PAL_BattleWon](resources/sdlpal-master/battle.c#L991) | hidden EXP rollover |
| [startFrame](src/fight.zig#L3247) — pub fn | [PAL_BattleStartFrame](resources/sdlpal-master/fight.c#L1073) | |

## font.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [comptime_reverseBits](src/font.zig#L40) — fn | — | zigpal comptime helper |
| [init](src/font.zig#L54) — pub fn | inside [PAL_InitFont](resources/sdlpal-master/font.c#L434) | DOS BIG5 font path only |
| [lookupBig5](src/font.zig#L66) — pub fn | inside [PAL_DrawCharOnSurface](resources/sdlpal-master/font.c#L522) | glyph lookup |
| [getAsciiGlyph](src/font.zig#L78) — pub fn | inside [PAL_DrawCharOnSurface](resources/sdlpal-master/font.c#L522) | ASCII glyph lookup |
| [drawAscii](src/font.zig#L83) — pub fn | inside [PAL_DrawCharOnSurface](resources/sdlpal-master/font.c#L522) | ASCII path |
| [drawBig5](src/font.zig#L103) — pub fn | inside [PAL_DrawCharOnSurface](resources/sdlpal-master/font.c#L522) | BIG5 path |
| [charWidth](src/font.zig#L132) — pub fn | [PAL_CharWidth](resources/sdlpal-master/font.c#L611) | |
| [height](src/font.zig#L137) — pub fn | [PAL_FontHeight](resources/sdlpal-master/font.c#L632) | |

## global.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [palXY](src/global.zig#L94) — pub inline fn | macro `PAL_XY` in [global.h](resources/sdlpal-master/global.h) | encoded as u32 (zig variant) |
| [palX](src/global.zig#L98) — pub inline fn | macro `PAL_X` in [global.h](resources/sdlpal-master/global.h) | |
| [palY](src/global.zig#L102) — pub inline fn | macro `PAL_Y` in [global.h](resources/sdlpal-master/global.h) | |
| [palXyOffset](src/global.zig#L106) — pub inline fn | — | zigpal helper |
| [setLoadFlags](src/global.zig#L533) — pub fn | [PAL_SetLoadFlags](resources/sdlpal-master/res.c#L164) | |
| [reloadInNextTick](src/global.zig#L538) — pub fn | [PAL_ReloadInNextTick](resources/sdlpal-master/global.c#L889) | |
| [getItemAmount](src/global.zig#L547) — pub fn | [PAL_GetItemAmount](resources/sdlpal-master/global.c#L1175) | |
| [getItemIndexToInventory](src/global.zig#L557) — pub fn | [PAL_GetItemIndexToInventory](resources/sdlpal-master/global.c#L1020) | |
| [addItemToInventory](src/global.zig#L571) — pub fn | [PAL_AddItemToInventory](resources/sdlpal-master/global.c#L1063) | |
| [compressInventory](src/global.zig#L606) — pub fn | [PAL_CompressInventory](resources/sdlpal-master/global.c#L1212) | |
| [countItem](src/global.zig#L621) — pub fn | [PAL_CountItem](resources/sdlpal-master/global.c#L957) | |
| [increaseHPMP](src/global.zig#L643) — pub fn | [PAL_IncreaseHPMP](resources/sdlpal-master/global.c#L1254) | |
| [getPlayerAttackStrength](src/global.zig#L667) — pub fn | [PAL_GetPlayerAttackStrength](resources/sdlpal-master/global.c#L1736) | |
| [getPlayerMagicStrength](src/global.zig#L676) — pub fn | [PAL_GetPlayerMagicStrength](resources/sdlpal-master/global.c#L1768) | |
| [getPlayerDefense](src/global.zig#L685) — pub fn | [PAL_GetPlayerDefense](resources/sdlpal-master/global.c#L1800) | |
| [getPlayerDexterity](src/global.zig#L694) — pub fn | [PAL_GetPlayerDexterity](resources/sdlpal-master/global.c#L1832) | |
| [getPlayerFleeRate](src/global.zig#L703) — pub fn | [PAL_GetPlayerFleeRate](resources/sdlpal-master/global.c#L1868) | |
| [getPlayerPoisonResistance](src/global.zig#L712) — pub fn | [PAL_GetPlayerPoisonResistance](resources/sdlpal-master/global.c#L1900) | |
| [getPlayerCooperativeMagic](src/global.zig#L723) — pub fn | [PAL_GetPlayerCooperativeMagic](resources/sdlpal-master/global.c#L2013) | |
| [addMagic](src/global.zig#L734) — pub fn | [PAL_AddMagic](resources/sdlpal-master/global.c#L2084) | |
| [playerLevelUp](src/global.zig#L749) — pub fn | [PAL_PlayerLevelUp](resources/sdlpal-master/global.c#L2347) | |
| [getPlayerElementalResistance](src/global.zig#L777) — pub fn | [PAL_GetPlayerElementalResistance](resources/sdlpal-master/global.c#L1937) | |
| [playerCanAttackAll](src/global.zig#L787) — pub fn | [PAL_PlayerCanAttackAll](resources/sdlpal-master/global.c#L2048) | |
| [partySlotOf](src/global.zig#L796) — fn | inside [PAL_AddPoisonForPlayer](resources/sdlpal-master/global.c#L1459) | helper |
| [addPoisonForPlayer](src/global.zig#L805) — pub fn | [PAL_AddPoisonForPlayer](resources/sdlpal-master/global.c#L1459) | |
| [curePoisonByKind](src/global.zig#L822) — pub fn | [PAL_CurePoisonByKind](resources/sdlpal-master/global.c#L1520) | |
| [curePoisonByLevel](src/global.zig#L834) — pub fn | [PAL_CurePoisonByLevel](resources/sdlpal-master/global.c#L1567) | |
| [isPlayerPoisonedByLevel](src/global.zig#L847) — pub fn | [PAL_IsPlayerPoisonedByLevel](resources/sdlpal-master/global.c#L1617) | |
| [isPlayerPoisonedByKind](src/global.zig#L861) — pub fn | [PAL_IsPlayerPoisonedByKind](resources/sdlpal-master/global.c#L1687) | |
| [setPlayerStatus](src/global.zig#L871) — pub fn | [PAL_SetPlayerStatus](resources/sdlpal-master/global.c#L2173) | |
| [updateEquipments](src/global.zig#L906) — pub fn | [PAL_UpdateEquipments](resources/sdlpal-master/global.c#L1333) | |
| [removePlayerStatus](src/global.zig#L924) — pub fn | [PAL_RemovePlayerStatus](resources/sdlpal-master/global.c#L2280) | |
| [clearAllPlayerStatus](src/global.zig#L932) — pub fn | [PAL_ClearAllPlayerStatus](resources/sdlpal-master/global.c#L2311) | |
| [removeEquipmentEffect](src/global.zig#L947) — pub fn | [PAL_RemoveEquipmentEffect](resources/sdlpal-master/global.c#L1372) | |

## input.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [clearKeyState](src/input.zig#L56) — pub fn | [PAL_ClearKeyState](resources/sdlpal-master/input.c#L1188) | |
| [forgetDirection](src/input.zig#L65) — pub fn | inside [PAL_ProcessEvent](resources/sdlpal-master/input.c#L1308) | direction-buffering helper |
| [initInput](src/input.zig#L76) — pub fn | [PAL_InitInput](resources/sdlpal-master/input.c#L1210) | libretro joypad path |
| [shutdownInput](src/input.zig#L83) — pub fn | [PAL_ShutdownInput](resources/sdlpal-master/input.c#L1244) | empty body — no-op |
| [getCurrDirection](src/input.zig#L85) — fn | [PAL_GetCurrDirection](resources/sdlpal-master/input.c#L163) | |
| [keyDown](src/input.zig#L95) — fn | [PAL_KeyDown](resources/sdlpal-master/input.c#L192) | |
| [keyUp](src/input.zig#L114) — fn | [PAL_KeyUp](resources/sdlpal-master/input.c#L244) | |
| [processEvent](src/input.zig#L138) — pub fn | [PAL_ProcessEvent](resources/sdlpal-master/input.c#L1308) | libretro retropad source |

## itemmenu.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [itemSelectMenuInit](src/itemmenu.zig#L65) — pub fn | [PAL_ItemSelectMenuInit](resources/sdlpal-master/itemmenu.c#L314) | |
| [itemSelectMenuUpdate](src/itemmenu.zig#L101) — pub fn | [PAL_ItemSelectMenuUpdate](resources/sdlpal-master/itemmenu.c#L29) | |
| [itemSelectMenuFromList](src/itemmenu.zig#L285) — pub fn | — | zigpal-specific debug entry |
| [itemSelectMenu](src/itemmenu.zig#L334) — pub fn | [PAL_ItemSelectMenu](resources/sdlpal-master/itemmenu.c#L380) | |
| [itemUseMenu](src/itemmenu.zig#L396) — pub fn | [PAL_ItemUseMenu](resources/sdlpal-master/uigame.c#L1289) | |
| [gameUseItem](src/itemmenu.zig#L491) — pub fn | [PAL_GameUseItem](resources/sdlpal-master/play.c#L244) | |
| [gameEquipItem](src/itemmenu.zig#L521) — pub fn | [PAL_GameEquipItem](resources/sdlpal-master/play.c#L328) | |
| [equipItemMenu](src/itemmenu.zig#L530) — pub fn | [PAL_EquipItemMenu](resources/sdlpal-master/uigame.c#L1794) | |
| [inventoryMenu](src/itemmenu.zig#L632) — pub fn | [PAL_InventoryMenu](resources/sdlpal-master/uigame.c#L878) | |
| [decompressFbpChunk](src/itemmenu.zig#L653) — fn | inside [PAL_EquipItemMenu](resources/sdlpal-master/uigame.c#L1794) | helper around `PAL_MKFDecompressChunk` |

## libretro_core.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [frameTimeCallback](src/libretro_core.zig#L104) — fn | — | libretro-only |
| [pumpJoypadInput](src/libretro_core.zig#L128) — fn | — | libretro-only |
| [pumpDebugKeys](src/libretro_core.zig#L156) — fn | — | libretro-only |
| [gameThreadEntry](src/libretro_core.zig#L218) — fn | — | libretro-only (thread bootstrap) |

## magicmenu.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [magicSelectionMenuInit](src/magicmenu.zig#L41) — pub fn | [PAL_MagicSelectionMenuInit](resources/sdlpal-master/magicmenu.c#L302) | |
| [magicSelectionMenuUpdate](src/magicmenu.zig#L99) — pub fn | [PAL_MagicSelectionMenuUpdate](resources/sdlpal-master/magicmenu.c#L36) | |
| [magicSelectionMenuFromList](src/magicmenu.zig#L251) — pub fn | — | zigpal-specific debug entry |
| [magicSelectionMenu](src/magicmenu.zig#L309) — pub fn | [PAL_MagicSelectionMenu](resources/sdlpal-master/magicmenu.c#L413) | |
| [inGameMagicMenu](src/magicmenu.zig#L345) — pub fn | [PAL_InGameMagicMenu](resources/sdlpal-master/uigame.c#L654) | |

## main.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [gameMain](src/main.zig#L35) — pub fn | [PAL_GameMain](resources/sdlpal-master/game.c#L25) | trademark/splash skipped |
| [palInit](src/main.zig#L74) — fn | [PAL_Init](resources/sdlpal-master/main.c#L50) | libretro-trimmed |
| [loadAllResourceFiles](src/main.zig#L95) — fn | inside [PAL_Init](resources/sdlpal-master/main.c#L50) | libretro-specific bulk loader |
| [readFile](src/main.zig#L134) — fn | — | libretro/zigpal-specific I/O glue |

## map.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [loadMap](src/map.zig#L22) — pub fn | [PAL_LoadMap](resources/sdlpal-master/map.c#L26) | |
| [getTileBitmap](src/map.zig#L54) — pub fn | [PAL_MapGetTileBitmap](resources/sdlpal-master/map.c#L198) | |
| [tileIsBlocked](src/map.zig#L70) — pub fn | [PAL_MapTileIsBlocked](resources/sdlpal-master/map.c#L262) | |
| [getTileHeight](src/map.zig#L75) — pub fn | [PAL_MapGetTileHeight](resources/sdlpal-master/map.c#L302) | |
| [blitToSurface](src/map.zig#L93) — pub fn | [PAL_MapBlitToSurface](resources/sdlpal-master/map.c#L356) | |

## objectdesc.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [load](src/objectdesc.zig#L41) — pub fn | loosely [PAL_LoadObjectDesc](resources/sdlpal-master/ui.c#L864) | zigpal extension (loads `desc.json`) |
| [getType](src/objectdesc.zig#L86) — pub fn | — | zigpal extension |
| [get](src/objectdesc.zig#L91) — pub fn | [PAL_GetObjectDesc](resources/sdlpal-master/ui.c#L961) | zigpal JSON-based variant |
| [hasDescTable](src/objectdesc.zig#L99) — pub fn | — | zigpal extension |
| [ensureFont](src/objectdesc.zig#L104) — fn | — | zigpal-specific (BDF font) |
| [decodeUtf8](src/objectdesc.zig#L120) — fn | — | zigpal-specific |
| [drawAt](src/objectdesc.zig#L129) — pub fn | — | zigpal-specific UTF-8 BDF renderer |

## palcommon.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [palXY](src/palcommon.zig#L17) — pub fn | macro `PAL_XY` in [global.h](resources/sdlpal-master/global.h) | re-export shim |
| [palX](src/palcommon.zig#L21) — pub fn | macro `PAL_X` in [global.h](resources/sdlpal-master/global.h) | re-export shim |
| [palY](src/palcommon.zig#L25) — pub fn | macro `PAL_Y` in [global.h](resources/sdlpal-master/global.h) | re-export shim |
| [calcShadowColor](src/palcommon.zig#L95) — inline fn | [PAL_CalcShadowColor](resources/sdlpal-master/palcommon.c#L28) | |
| [skipRleHeader](src/palcommon.zig#L99) — fn | inside [PAL_RLEBlitToSurface](resources/sdlpal-master/palcommon.c#L36) | RLE prologue helper |
| [rleGetDimensions](src/palcommon.zig#L106) — fn | inside [PAL_RLEBlitToSurface](resources/sdlpal-master/palcommon.c#L36) | RLE size decoder |
| [rleBlitGeneric](src/palcommon.zig#L122) — fn | merges palcommon.c blits | combined dispatcher for all 4 variants |
| [rleBlitToSurface](src/palcommon.zig#L253) — pub fn | [PAL_RLEBlitToSurface](resources/sdlpal-master/palcommon.c#L36) | |
| [rleBlitToSurfaceWithShadow](src/palcommon.zig#L257) — pub fn | [PAL_RLEBlitToSurfaceWithShadow](resources/sdlpal-master/palcommon.c#L46) | |
| [rleBlitWithColorShift](src/palcommon.zig#L261) — pub fn | [PAL_RLEBlitWithColorShift](resources/sdlpal-master/palcommon.c#L245) | |
| [rleBlitMonoColor](src/palcommon.zig#L265) — pub fn | [PAL_RLEBlitMonoColor](resources/sdlpal-master/palcommon.c#L446) | |
| [fbpBlitToSurface](src/palcommon.zig#L269) — pub fn | [PAL_FBPBlitToSurface](resources/sdlpal-master/palcommon.c#L651) | |
| [rleGetWidth](src/palcommon.zig#L286) — pub fn | [PAL_RLEGetWidth](resources/sdlpal-master/palcommon.c#L698) | |
| [rleGetHeight](src/palcommon.zig#L291) — pub fn | [PAL_RLEGetHeight](resources/sdlpal-master/palcommon.c#L737) | |
| [spriteGetNumFrames](src/palcommon.zig#L298) — pub fn | [PAL_SpriteGetNumFrames](resources/sdlpal-master/palcommon.c#L776) | |
| [spriteGetFrame](src/palcommon.zig#L302) — pub fn | [PAL_SpriteGetFrame](resources/sdlpal-master/palcommon.c#L803) | |

## palette.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [init](src/palette.zig#L22) — pub fn | inside [PAL_Init](resources/sdlpal-master/main.c#L50) | PAT data loading |
| [get](src/palette.zig#L27) — pub fn | [PAL_GetPalette](resources/sdlpal-master/palette.c#L25) | |
| [setPalette](src/palette.zig#L50) — pub fn | [PAL_SetPalette](resources/sdlpal-master/palette.c#L93) | |
| [fadeOut](src/palette.zig#L58) — pub fn | [PAL_FadeOut](resources/sdlpal-master/palette.c#L123) | |
| [fadeIn](src/palette.zig#L96) — pub fn | [PAL_FadeIn](resources/sdlpal-master/palette.c#L193) | |
| [fadeToRed](src/palette.zig#L135) — pub fn | [PAL_FadeToRed](resources/sdlpal-master/palette.c#L595) | |
| [paletteFade](src/palette.zig#L179) — pub fn | [PAL_PaletteFade](resources/sdlpal-master/palette.c#L381) | |
| [sceneFade](src/palette.zig#L215) — pub fn | [PAL_SceneFade](resources/sdlpal-master/palette.c#L262) | |
| [colorFade](src/palette.zig#L279) — pub fn | [PAL_ColorFade](resources/sdlpal-master/palette.c#L462) | |

## play.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [gameUpdate](src/play.zig#L20) — pub fn | [PAL_GameUpdate](resources/sdlpal-master/play.c#L25) | |
| [getSearchTriggerRange](src/play.zig#L137) — fn | [PAL_GetSearchTriggerRange](resources/sdlpal-master/play.c#L362) | |
| [search](src/play.zig#L159) — pub fn | [PAL_Search](resources/sdlpal-master/play.c#L423) | |
| [startFrame](src/play.zig#L208) — pub fn | [PAL_StartFrame](resources/sdlpal-master/play.c#L513) | |
| [updateParty](src/play.zig#L238) — pub fn | re-export of [PAL_UpdateParty](resources/sdlpal-master/scene.c#L779) | thin shim to scene.zig |
| [waitForKeyInternal](src/play.zig#L243) — pub fn | [PAL_WaitForKeyInternal](resources/sdlpal-master/play.c#L603) | |
| [waitForKey](src/play.zig#L258) — pub fn | [PAL_WaitForKey](resources/sdlpal-master/play.c#L641) | |
| [waitForAnyKey](src/play.zig#L262) — pub fn | [PAL_WaitForAnyKey](resources/sdlpal-master/play.c#L663) | |

## playerstatus.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [playerStatus](src/playerstatus.zig#L80) — pub fn | [PAL_PlayerStatus](resources/sdlpal-master/uigame.c#L1051) | |
| [readRleChunk](src/playerstatus.zig#L231) — fn | inside [PAL_PlayerStatus](resources/sdlpal-master/uigame.c#L1051) | helper |
| [decompressFbpChunk](src/playerstatus.zig#L239) — fn | inside [PAL_PlayerStatus](resources/sdlpal-master/uigame.c#L1051) | helper around `PAL_MKFDecompressChunk` |

## res.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [initResources](src/res.zig#L31) — pub fn | [PAL_InitResources](resources/sdlpal-master/res.c#L101) | |
| [freeResources](src/res.zig#L36) — pub fn | [PAL_FreeResources](resources/sdlpal-master/res.c#L123) | |
| [freeEventObjectSprites](src/res.zig#L45) — fn | [PAL_FreeEventObjectSprites](resources/sdlpal-master/res.c#L38) | |
| [freePlayerSprites](src/res.zig#L56) — fn | [PAL_FreePlayerSprites](resources/sdlpal-master/res.c#L73) | |
| [loadResources](src/res.zig#L66) — pub fn | [PAL_LoadResources](resources/sdlpal-master/res.c#L191) | |
| [getCurrentMap](src/res.zig#L146) — pub fn | [PAL_GetCurrentMap](resources/sdlpal-master/res.c#L358) | |
| [getPlayerSprite](src/res.zig#L152) — pub fn | [PAL_GetPlayerSprite](resources/sdlpal-master/res.c#L385) | |
| [getEventObjectSprite](src/res.zig#L158) — pub fn | [PAL_GetEventObjectSprite](resources/sdlpal-master/res.c#L412) | |
| [decompressMkfChunk](src/res.zig#L168) — fn | wraps [PAL_MKFDecompressChunk](resources/sdlpal-master/palcommon.c#L1085) | helper |
| [initGameData](src/res.zig#L178) — fn | [PAL_InitGameData](resources/sdlpal-master/global.c#L915) | |
| [initGlobalGameData](src/res.zig#L193) — fn | [PAL_InitGlobalGameData](resources/sdlpal-master/global.c#L312) | |
| [loadDefaultGame](src/res.zig#L273) — fn | [PAL_LoadDefaultGame](resources/sdlpal-master/global.c#L378) | |
| [loadSavedGame](src/res.zig#L339) — fn | [PAL_LoadGame](resources/sdlpal-master/global.c#L727) | |

## save.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [savePath](src/save.zig#L70) — fn | inside [PAL_SaveGame](resources/sdlpal-master/global.c#L877) | path-builder helper |
| [readAll](src/save.zig#L77) — fn | — | libretro fd I/O helper |
| [writeAllOrErr](src/save.zig#L87) — fn | — | libretro fd I/O helper |
| [getSavedTimes](src/save.zig#L98) — pub fn | inside [PAL_SaveSlotMenu](resources/sdlpal-master/uigame.c#L169) | reads first WORD of `<slot>.rpg` |
| [loadGame](src/save.zig#L112) — pub fn | [PAL_LoadGame_DOS](resources/sdlpal-master/global.c#L642) | DOS save format only |
| [saveGame](src/save.zig#L170) — pub fn | [PAL_SaveGame_DOS](resources/sdlpal-master/global.c#L804) | DOS save format only |

## scene.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [addSpriteToDraw](src/scene.zig#L31) — fn | [PAL_AddSpriteToDraw](resources/sdlpal-master/scene.c#L40) | |
| [calcCoverTiles](src/scene.zig#L42) — fn | [PAL_CalcCoverTiles](resources/sdlpal-master/scene.c#L77) | |
| [sceneDrawSprites](src/scene.zig#L122) — fn | [PAL_SceneDrawSprites](resources/sdlpal-master/scene.c#L181) | |
| [applyWave](src/scene.zig#L202) — pub fn | [PAL_ApplyWave](resources/sdlpal-master/scene.c#L365) | |
| [makeScene](src/scene.zig#L240) — pub fn | [PAL_MakeScene](resources/sdlpal-master/scene.c#L453) | |
| [checkObstacle](src/scene.zig#L264) — pub fn | [PAL_CheckObstacle](resources/sdlpal-master/scene.c#L512) | |
| [checkObstacleWithRange](src/scene.zig#L268) — pub fn | [PAL_CheckObstacleWithRange](resources/sdlpal-master/scene.c#L522) | |
| [updatePartyGestures](src/scene.zig#L324) — pub fn | [PAL_UpdatePartyGestures](resources/sdlpal-master/scene.c#L636) | |
| [updateParty](src/scene.zig#L405) — pub fn | [PAL_UpdateParty](resources/sdlpal-master/scene.c#L779) | |
| [npcWalkOneStep](src/scene.zig#L439) — pub fn | [PAL_NPCWalkOneStep](resources/sdlpal-master/scene.c#L851) | |

## script.zig

### Helper functions

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [applyPoisonToEnemyAt](src/script.zig#L32) — fn | inside [PAL_InterpretInstruction](resources/sdlpal-master/script.c#L587) | poison helper (script.c L1196) |
| [rolesPtr](src/script.zig#L51) — inline fn | — | zigpal helper for opcode 0x0019 etc |
| [equipEffectPtr](src/script.zig#L55) — inline fn | — | zigpal helper for opcode 0x0017 etc |
| [npcWalkTo](src/script.zig#L60) — fn | [PAL_NPCWalkTo](resources/sdlpal-master/script.c#L31) | |
| [partyWalkTo](src/script.zig#L96) — fn | [PAL_PartyWalkTo](resources/sdlpal-master/script.c#L101) | |
| [partyRideEventObject](src/script.zig#L154) — fn | [PAL_PartyRideEventObject](resources/sdlpal-master/script.c#L203) | |
| [monsterChasePlayer](src/script.zig#L214) — fn | [PAL_MonsterChasePlayer](resources/sdlpal-master/script.c#L310) | |
| [loadFbpChunk](src/script.zig#L311) — fn | inside [PAL_ShowFBP](resources/sdlpal-master/ending.c#L49) | helper |
| [showFbp](src/script.zig#L326) — fn | [PAL_ShowFBP](resources/sdlpal-master/ending.c#L49) | |
| [scrollFbp](src/script.zig#L376) — fn | [PAL_ScrollFBP](resources/sdlpal-master/ending.c#L153) | |
| [endingAnimation](src/script.zig#L438) — fn | [PAL_EndingAnimation](resources/sdlpal-master/ending.c#L282) | |
| [runAutoScript](src/script.zig#L514) — pub fn | [PAL_RunAutoScript](resources/sdlpal-master/script.c#L3482) | |
| [runTriggerScript](src/script.zig#L593) — pub fn | [PAL_RunTriggerScript](resources/sdlpal-master/script.c#L3140) | |
| [interpretInstruction](src/script.zig#L769) — fn | [PAL_InterpretInstruction](resources/sdlpal-master/script.c#L587) | |
| [openLogFile](src/script.zig#L2031) — fn | — | zigpal-specific debug logging |
| [writeLog](src/script.zig#L2043) — fn | — | zigpal-specific debug logging |
| [logUnhandled](src/script.zig#L2050) — fn | — | zigpal-specific debug logging |
| [traceAuto](src/script.zig#L2070) — fn | — | zigpal-specific debug tracing |
| [traceWalk](src/script.zig#L2085) — fn | — | zigpal-specific debug tracing |
| [traceAutoBody](src/script.zig#L2100) — fn | — | zigpal-specific debug tracing |

### `runAutoScript` opcode dispatch (`script.zig` ↔ SDLPAL `PAL_RunAutoScript`)

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [case 0x0000](src/script.zig#L525) | [case 0x0000](resources/sdlpal-master/script.c#L3520) | |
| [case 0x0001](src/script.zig#L526) | [case 0x0001](resources/sdlpal-master/script.c#L3526) | |
| [case 0x0002](src/script.zig#L527) | [case 0x0002](resources/sdlpal-master/script.c#L3533) | |
| [case 0x0003](src/script.zig#L542) | [case 0x0003](resources/sdlpal-master/script.c#L3549) | |
| [case 0x0004](src/script.zig#L559) | [case 0x0004](resources/sdlpal-master/script.c#L3566) | |
| [case 0x0006](src/script.zig#L563) | [case 0x0006](resources/sdlpal-master/script.c#L3575) | |
| [case 0x0009](src/script.zig#L574) | [case 0x0009](resources/sdlpal-master/script.c#L3593) | |
| case 0xFFFF / 0x00A7 (src/script.zig#L586) | [case 0xFFFF](resources/sdlpal-master/script.c#L3607) / [case 0x00A7](resources/sdlpal-master/script.c#L3639) | |
| else → interpretInstruction (src/script.zig#L587) | else → `PAL_InterpretInstruction` | dispatcher fallback |

### `runTriggerScript` opcode dispatch (`script.zig` ↔ SDLPAL `PAL_RunTriggerScript`)

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [case 0x0000](src/script.zig#L613) | [case 0x0000](resources/sdlpal-master/script.c#L3204) | |
| [case 0x0001](src/script.zig#L616) | [case 0x0001](resources/sdlpal-master/script.c#L3211) | |
| [case 0x0002](src/script.zig#L620) | [case 0x0002](resources/sdlpal-master/script.c#L3219) | |
| [case 0x0003](src/script.zig#L637) | [case 0x0003](resources/sdlpal-master/script.c#L3239) | |
| [case 0x0004](src/script.zig#L652) | [case 0x0004](resources/sdlpal-master/script.c#L3258) | |
| [case 0x0005](src/script.zig#L656) | [case 0x0005](resources/sdlpal-master/script.c#L3267) | redraw screen |
| [case 0x0006](src/script.zig#L668) | [case 0x0006](resources/sdlpal-master/script.c#L3299) | |
| [case 0x0007](src/script.zig#L675) | [case 0x0007](resources/sdlpal-master/script.c#L3314) | start battle |
| [case 0x0008](src/script.zig#L688) | [case 0x0008](resources/sdlpal-master/script.c#L3335) | |
| [case 0x0009](src/script.zig#L692) | [case 0x0009](resources/sdlpal-master/script.c#L3343) | wait N frames |
| [case 0x000A](src/script.zig#L712) | [case 0x000A](resources/sdlpal-master/script.c#L3373) | yes/no goto |
| [case 0x003B](src/script.zig#L721) | [case 0x003B](resources/sdlpal-master/script.c#L3389) | dialog center |
| [case 0x003C](src/script.zig#L727) | [case 0x003C](resources/sdlpal-master/script.c#L3399) | dialog upper |
| [case 0x003D](src/script.zig#L733) | [case 0x003D](resources/sdlpal-master/script.c#L3409) | dialog lower |
| [case 0x003E](src/script.zig#L739) | [case 0x003E](resources/sdlpal-master/script.c#L3419) | dialog center window |
| [case 0x008E](src/script.zig#L745) | [case 0x008E](resources/sdlpal-master/script.c#L3428) | restore screen |
| [case 0xFFFF](src/script.zig#L751) | [case 0xFFFF](resources/sdlpal-master/script.c#L3438) | print dialog text |
| else → interpretInstruction (src/script.zig#L756) | else → `PAL_InterpretInstruction` | dispatcher fallback |

### `interpretInstruction` opcode dispatch (`script.zig` ↔ SDLPAL `PAL_InterpretInstruction`)

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| case 0x000B/0x000C/0x000D/0x000E (src/script.zig#L800) | [cases 0x000B-0x000E](resources/sdlpal-master/script.c#L652) | walk one step |
| [case 0x000F](src/script.zig#L806) | [case 0x000F](resources/sdlpal-master/script.c#L663) | set direction/frame |
| [case 0x0010](src/script.zig#L812) | [case 0x0010](resources/sdlpal-master/script.c#L677) | NPC walk to |
| [case 0x0011](src/script.zig#L817) | [case 0x0011](resources/sdlpal-master/script.c#L688) | NPC walk to (interleaved) |
| [case 0x0012](src/script.zig#L828) | [case 0x0012](resources/sdlpal-master/script.c#L706) | viewport-relative position |
| [case 0x0013](src/script.zig#L834) | [case 0x0013](resources/sdlpal-master/script.c#L716) | absolute position |
| [case 0x0014](src/script.zig#L840) | [case 0x0014](resources/sdlpal-master/script.c#L724) | set frame |
| [case 0x0015](src/script.zig#L846) | [case 0x0015](resources/sdlpal-master/script.c#L732) | party direction |
| [case 0x0016](src/script.zig#L851) | [case 0x0016](resources/sdlpal-master/script.c#L741) | conditional dir/frame |
| [case 0x0017](src/script.zig#L859) | [case 0x0017](resources/sdlpal-master/script.c#L752) | set equipment effect |
| [case 0x0018](src/script.zig#L867) | [case 0x0018](resources/sdlpal-master/script.c#L768) | equip item (script_on_equip not run) |
| [case 0x0019](src/script.zig#L883) | [case 0x0019](resources/sdlpal-master/script.c#L813) | adjust attribute |
| [case 0x001A](src/script.zig#L890) | [case 0x001A](resources/sdlpal-master/script.c#L834) | set stat |
| [case 0x001B](src/script.zig#L897) | [case 0x001B](resources/sdlpal-master/script.c#L867) | inc/dec HP |
| [case 0x001C](src/script.zig#L910) | [case 0x001C](resources/sdlpal-master/script.c#L896) | inc/dec MP |
| [case 0x001D](src/script.zig#L922) | [case 0x001D](resources/sdlpal-master/script.c#L923) | inc/dec HP+MP |
| [case 0x001E](src/script.zig#L934) | [case 0x001E](resources/sdlpal-master/script.c#L952) | adjust cash |
| [case 0x001F](src/script.zig#L942) | [case 0x001F](resources/sdlpal-master/script.c#L970) | add item |
| [case 0x0020](src/script.zig#L945) | [case 0x0020](resources/sdlpal-master/script.c#L977) | remove item |
| [case 0x0022](src/script.zig#L971) | [case 0x0022](resources/sdlpal-master/script.c#L1052) | revive player |
| [case 0x0023](src/script.zig#L991) | [case 0x0023](resources/sdlpal-master/script.c#L1104) | remove equipment |
| [case 0x0024](src/script.zig#L1012) | [case 0x0024](resources/sdlpal-master/script.c#L1137) | set auto script |
| [case 0x0025](src/script.zig#L1015) | [case 0x0025](resources/sdlpal-master/script.c#L1147) | set trigger script |
| [case 0x0026](src/script.zig#L1018) | [case 0x0026](resources/sdlpal-master/script.c#L1157) | open buy menu |
| [case 0x0027](src/script.zig#L1024) | [case 0x0027](resources/sdlpal-master/script.c#L1166) | open sell/pawn menu |
| [case 0x0021](src/script.zig#L1030) | [case 0x0021](resources/sdlpal-master/script.c#L1026) | inflict enemy damage |
| [case 0x0028](src/script.zig#L1045) | [case 0x0028](resources/sdlpal-master/script.c#L1175) | poison enemy |
| [case 0x0029](src/script.zig#L1065) | [case 0x0029](resources/sdlpal-master/script.c#L1257) | poison player |
| [case 0x002A](src/script.zig#L1082) | [case 0x002A](resources/sdlpal-master/script.c#L1287) | cure enemy poison by id |
| [case 0x002B](src/script.zig#L1110) | [case 0x002B](resources/sdlpal-master/script.c#L1331) | cure player poison by id |
| [case 0x002C](src/script.zig#L1122) | [case 0x002C](resources/sdlpal-master/script.c#L1349) | cure poisons by level |
| [case 0x002D](src/script.zig#L1134) | [case 0x002D](resources/sdlpal-master/script.c#L1367) | set player status |
| [case 0x002E](src/script.zig#L1140) | [case 0x002E](resources/sdlpal-master/script.c#L1377) | set enemy status |
| [case 0x002F](src/script.zig#L1151) | [case 0x002F](resources/sdlpal-master/script.c#L1399) | remove player status |
| [case 0x0033](src/script.zig#L1155) | [case 0x0033](resources/sdlpal-master/script.c#L1437) | collect enemy |
| [case 0x0034](src/script.zig#L1165) | [case 0x0034](resources/sdlpal-master/script.c#L1452) | transform collected |
| [case 0x0039](src/script.zig#L1180) | [case 0x0039](resources/sdlpal-master/script.c#L1573) | drain HP from enemy |
| [case 0x003A](src/script.zig#L1190) | [case 0x003A](resources/sdlpal-master/script.c#L1588) | player flee |
| [case 0x0042](src/script.zig#L1199) | [case 0x0042](resources/sdlpal-master/script.c#L1630) | simulate magic |
| [case 0x005B](src/script.zig#L1206) | [case 0x005B](resources/sdlpal-master/script.c#L1895) | halve enemy HP |
| [case 0x005C](src/script.zig#L1213) | [case 0x005C](resources/sdlpal-master/script.c#L1907) | hide for time |
| [case 0x005D](src/script.zig#L1219) | [case 0x005D](resources/sdlpal-master/script.c#L1914) | jump if not poisoned (kind) |
| [case 0x005E](src/script.zig#L1225) | [case 0x005E](resources/sdlpal-master/script.c#L1924) | jump if enemy not poisoned |
| [case 0x005F](src/script.zig#L1238) | [case 0x005F](resources/sdlpal-master/script.c#L1942) | kill player |
| [case 0x0060](src/script.zig#L1242) | [case 0x0060](resources/sdlpal-master/script.c#L1950) | KO enemy |
| [case 0x0061](src/script.zig#L1246) | [case 0x0061](resources/sdlpal-master/script.c#L1957) | jump if not poisoned (level) |
| [case 0x0062](src/script.zig#L1252) | [case 0x0062](resources/sdlpal-master/script.c#L1967) | pause chase |
| [case 0x0063](src/script.zig#L1257) | [case 0x0063](resources/sdlpal-master/script.c#L1975) | speed up chase |
| [case 0x0064](src/script.zig#L1262) | [case 0x0064](resources/sdlpal-master/script.c#L1983) | jump if HP > pct |
| [case 0x0066](src/script.zig#L1272) | [case 0x0066](resources/sdlpal-master/script.c#L2007) | throw weapon |
| [case 0x0067](src/script.zig#L1280) | [case 0x0067](resources/sdlpal-master/script.c#L2016) | enemy use magic |
| [case 0x0068](src/script.zig#L1287) | [case 0x0068](resources/sdlpal-master/script.c#L2025) | jump if enemy turn |
| [case 0x0069](src/script.zig#L1293) | [case 0x0069](resources/sdlpal-master/script.c#L2035) | enemy escape |
| [case 0x006A](src/script.zig#L1297) | [case 0x006A](resources/sdlpal-master/script.c#L2042) | steal from enemy |
| [case 0x006B](src/script.zig#L1301) | [case 0x006B](resources/sdlpal-master/script.c#L2049) | blow away enemies |
| [case 0x0030](src/script.zig#L1305) | [case 0x0030](resources/sdlpal-master/script.c#L1406) | temp stat boost % |
| [case 0x0031](src/script.zig#L1314) | [case 0x0031](resources/sdlpal-master/script.c#L1429) | extra battle sprite |
| [case 0x0035](src/script.zig#L1317) | [case 0x0035](resources/sdlpal-master/script.c#L1521) | shake screen |
| [case 0x0036](src/script.zig#L1323) | [case 0x0036](resources/sdlpal-master/script.c#L1537) | set RNG num |
| [case 0x0037](src/script.zig#L1326) | [case 0x0037](resources/sdlpal-master/script.c#L1544) | stub — `// PAL_RNGPlay — Stage 6 (animations).` |
| [case 0x0038](src/script.zig#L1329) | [case 0x0038](resources/sdlpal-master/script.c#L1554) | teleport |
| [case 0x003F](src/script.zig#L1338) | [case 0x003F](resources/sdlpal-master/script.c#L1605) | ride event obj (speed 2) |
| [case 0x0040](src/script.zig#L1341) | [case 0x0040](resources/sdlpal-master/script.c#L1613) | set trigger mode |
| [case 0x0041](src/script.zig#L1344) | [case 0x0041](resources/sdlpal-master/script.c#L1623) | mark script failed |
| [case 0x0043](src/script.zig#L1347) | [case 0x0043](resources/sdlpal-master/script.c#L1642) | audio skipped — sets `num_music` only |
| [case 0x0044](src/script.zig#L1351) | [case 0x0044](resources/sdlpal-master/script.c#L1650) | ride event obj (speed 4) |
| [case 0x0045](src/script.zig#L1354) | [case 0x0045](resources/sdlpal-master/script.c#L1658) | set battle music — bookkeeping only |
| [case 0x0046](src/script.zig#L1357) | [case 0x0046](resources/sdlpal-master/script.c#L1665) | set party position |
| [case 0x0047](src/script.zig#L1382) | [case 0x0047](resources/sdlpal-master/script.c#L1704) | stub — `// PAL_PlaySound — no audio.` |
| [case 0x0049](src/script.zig#L1385) | [case 0x0049](resources/sdlpal-master/script.c#L1711) | set event-object state |
| [case 0x004A](src/script.zig#L1388) | [case 0x004A](resources/sdlpal-master/script.c#L1719) | set battle field |
| [case 0x004B](src/script.zig#L1391) | [case 0x004B](resources/sdlpal-master/script.c#L1726) | vanish event object |
| [case 0x004C](src/script.zig#L1394) | [case 0x004C](resources/sdlpal-master/script.c#L1733) | monster chase player |
| [case 0x004D](src/script.zig#L1402) | [case 0x004D](resources/sdlpal-master/script.c#L1753) | wait for key |
| [case 0x004E](src/script.zig#L1405) | [case 0x004E](resources/sdlpal-master/script.c#L1760) | reload save (fade out) |
| [case 0x004F](src/script.zig#L1410) | [case 0x004F](resources/sdlpal-master/script.c#L1768) | fade to red |
| [case 0x0050](src/script.zig#L1413) | [case 0x0050](resources/sdlpal-master/script.c#L1775) | fade out |
| [case 0x0051](src/script.zig#L1418) | [case 0x0051](resources/sdlpal-master/script.c#L1784) | fade in |
| [case 0x0052](src/script.zig#L1424) | [case 0x0052](resources/sdlpal-master/script.c#L1794) | toggle event object state |
| [case 0x0053](src/script.zig#L1430) | [case 0x0053](resources/sdlpal-master/script.c#L1802) | day palette |
| [case 0x0054](src/script.zig#L1433) | [case 0x0054](resources/sdlpal-master/script.c#L1809) | night palette |
| [case 0x0055](src/script.zig#L1436) | [case 0x0055](resources/sdlpal-master/script.c#L1816) | add magic |
| [case 0x0056](src/script.zig#L1450) | [case 0x0056](resources/sdlpal-master/script.c#L1832) | remove magic |
| [case 0x0057](src/script.zig#L1462) | [case 0x0057](resources/sdlpal-master/script.c#L1848) | magic damage = MP*k |
| [case 0x0058](src/script.zig#L1471) | [case 0x0058](resources/sdlpal-master/script.c#L1859) | jump if amount < N |
| [case 0x0059](src/script.zig#L1477) | [case 0x0059](resources/sdlpal-master/script.c#L1870) | change scene |
| [case 0x005A](src/script.zig#L1487) | [case 0x005A](resources/sdlpal-master/script.c#L1887) | halve player HP |
| [case 0x0065](src/script.zig#L1491) | [case 0x0065](resources/sdlpal-master/script.c#L1995) | swap player sprite |
| [case 0x006C](src/script.zig#L1498) | [case 0x006C](resources/sdlpal-master/script.c#L2056) | nudge + walk |
| [case 0x006D](src/script.zig#L1505) | [case 0x006D](resources/sdlpal-master/script.c#L2065) | swap scene scripts |
| [case 0x006E](src/script.zig#L1519) | [case 0x006E](resources/sdlpal-master/script.c#L2091) | move party in one step |
| [case 0x006F](src/script.zig#L1537) | [case 0x006F](resources/sdlpal-master/script.c#L2115) | mirror state |
| [case 0x0070](src/script.zig#L1544) | [case 0x0070](resources/sdlpal-master/script.c#L2125) | party walk to (speed 2) |
| [case 0x0071](src/script.zig#L1547) | [case 0x0071](resources/sdlpal-master/script.c#L2132) | screen wave settings |
| [case 0x0073](src/script.zig#L1551) | [case 0x0073](resources/sdlpal-master/script.c#L2140) | fade to scene |
| [case 0x0074](src/script.zig#L1558) | [case 0x0074](resources/sdlpal-master/script.c#L2149) | jump if any party not full HP |
| [case 0x0075](src/script.zig#L1568) | [case 0x0075](resources/sdlpal-master/script.c#L2164) | set party members |
| [case 0x0076](src/script.zig#L1585) | [case 0x0076](resources/sdlpal-master/script.c#L2199) | show FBP |
| [case 0x0077](src/script.zig#L1588) | [case 0x0077](resources/sdlpal-master/script.c#L2215) | clear music |
| [case 0x0078](src/script.zig#L1591) | [case 0x0078](resources/sdlpal-master/script.c#L2224) | unknown — empty body |
| [case 0x0079](src/script.zig#L1594) | [case 0x0079](resources/sdlpal-master/script.c#L2230) | jump if name match |
| [case 0x007A](src/script.zig#L1603) | [case 0x007A](resources/sdlpal-master/script.c#L2245) | party walk to (speed 4) |
| [case 0x007B](src/script.zig#L1606) | [case 0x007B](resources/sdlpal-master/script.c#L2252) | party walk to (speed 8) |
| [case 0x007C](src/script.zig#L1609) | [case 0x007C](resources/sdlpal-master/script.c#L2259) | NPC walk to (interleaved sp4) |
| [case 0x007D](src/script.zig#L1618) | [case 0x007D](resources/sdlpal-master/script.c#L2277) | nudge event obj |
| [case 0x007E](src/script.zig#L1624) | [case 0x007E](resources/sdlpal-master/script.c#L2285) | set layer |
| [case 0x007F](src/script.zig#L1627) | [case 0x007F](resources/sdlpal-master/script.c#L2292) | move viewport (simplified vs SDLPAL animation) |
| [case 0x0080](src/script.zig#L1679) | [case 0x0080](resources/sdlpal-master/script.c#L2381) | toggle day/night palette |
| [case 0x0081](src/script.zig#L1683) | [case 0x0081](resources/sdlpal-master/script.c#L2390) | jump if obj out of range |
| [case 0x0082](src/script.zig#L1707) | [case 0x0082](resources/sdlpal-master/script.c#L2437) | NPC walk to (speed 8) |
| [case 0x0083](src/script.zig#L1712) | [case 0x0083](resources/sdlpal-master/script.c#L2448) | distance check |
| [case 0x0084](src/script.zig#L1728) | [case 0x0084](resources/sdlpal-master/script.c#L2473) | step toward obj |
| [case 0x0085](src/script.zig#L1750) | [case 0x0085](resources/sdlpal-master/script.c#L2511) | wait N*80 ms |
| [case 0x0086](src/script.zig#L1753) | [case 0x0086](resources/sdlpal-master/script.c#L2518) | jump if not enough equipped |
| [case 0x0087](src/script.zig#L1766) | [case 0x0087](resources/sdlpal-master/script.c#L2540) | walk one step |
| [case 0x0088](src/script.zig#L1769) | [case 0x0088](resources/sdlpal-master/script.c#L2547) | spend cash for magic |
| [case 0x0089](src/script.zig#L1777) | [case 0x0089](resources/sdlpal-master/script.c#L2557) | set battle result |
| [case 0x008A](src/script.zig#L1780) | [case 0x008A](resources/sdlpal-master/script.c#L2564) | set auto-battle |
| [case 0x008B](src/script.zig#L1783) | [case 0x008B](resources/sdlpal-master/script.c#L2571) | set palette |
| [case 0x008C](src/script.zig#L1789) | [case 0x008C](resources/sdlpal-master/script.c#L2582) | color fade |
| [case 0x008D](src/script.zig#L1793) | [case 0x008D](resources/sdlpal-master/script.c#L2591) | level up |
| [case 0x008F](src/script.zig#L1796) | [case 0x008F](resources/sdlpal-master/script.c#L2598) | halve cash |
| [case 0x0090](src/script.zig#L1799) | [case 0x0090](resources/sdlpal-master/script.c#L2605) | set object data |
| [case 0x0091](src/script.zig#L1806) | [case 0x0091](resources/sdlpal-master/script.c#L2613) | jump if not first of kind |
| [case 0x0092](src/script.zig#L1828) | [case 0x0092](resources/sdlpal-master/script.c#L2637) | player pre-magic anim |
| [case 0x0093](src/script.zig#L1808) | [case 0x0093](resources/sdlpal-master/script.c#L2664) | scene fade |
| [case 0x0094](src/script.zig#L1812) | [case 0x0094](resources/sdlpal-master/script.c#L2673) | jump on object state |
| [case 0x0095](src/script.zig#L1819) | [case 0x0095](resources/sdlpal-master/script.c#L2683) | jump on scene id |
| [case 0x0096](src/script.zig#L1824) | [case 0x0096](resources/sdlpal-master/script.c#L2693) | run ending animation |
| [case 0x0097](src/script.zig#L1827) | [case 0x0097](resources/sdlpal-master/script.c#L2701) | ride event obj (speed 8) |
| [case 0x0098](src/script.zig#L1830) | [case 0x0098](resources/sdlpal-master/script.c#L2709) | set followers |
| [case 0x0099](src/script.zig#L1852) | [case 0x0099](resources/sdlpal-master/script.c#L2740) | swap scene map |
| [case 0x009A](src/script.zig#L1861) | [case 0x009A](resources/sdlpal-master/script.c#L2756) | mass-set event-object state |
| [case 0x009B](src/script.zig#L1869) | [case 0x009B](resources/sdlpal-master/script.c#L2766) | fade to current scene |
| [case 0x009C](src/script.zig#L1925) | [case 0x009C](resources/sdlpal-master/script.c#L2776) | enemy division |
| [case 0x009E](src/script.zig#L1881) | [case 0x009E](resources/sdlpal-master/script.c#L2870) | enemy summons monster |
| [case 0x009F](src/script.zig#L1942) | [case 0x009F](resources/sdlpal-master/script.c#L2954) | enemy transforms |
| [case 0x00A0](src/script.zig#L1972) | [case 0x00A0](resources/sdlpal-master/script.c#L2988) | quit game (libretro flag) |
| [case 0x00A1](src/script.zig#L1976) | [case 0x00A1](resources/sdlpal-master/script.c#L2998) | reset trail |
| [case 0x00A2](src/script.zig#L1990) | [case 0x00A2](resources/sdlpal-master/script.c#L3016) | random goto |
| [case 0x00A3](src/script.zig#L1994) | [case 0x00A3](resources/sdlpal-master/script.c#L3023) | set music — bookkeeping only |
| [case 0x00A4](src/script.zig#L1997) | [case 0x00A4](resources/sdlpal-master/script.c#L3038) | scroll FBP |
| [case 0x00A5](src/script.zig#L2002) | [case 0x00A5](resources/sdlpal-master/script.c#L3055) | show FBP w/ effect (effect skipped) |
| [case 0x00A6](src/script.zig#L2007) | [case 0x00A6](resources/sdlpal-master/script.c#L3069) | backup screen |
| [else](src/script.zig#L2010) | else (default) | logs unhandled opcode (zigpal-only diagnostic) |

## shop.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [buyMenuOnItemChange](src/shop.zig#L36) — fn | [PAL_BuyMenu_OnItemChange](resources/sdlpal-master/uigame.c#L1503) | |
| [buyMenu](src/shop.zig#L106) — pub fn | [PAL_BuyMenu](resources/sdlpal-master/uigame.c#L1615) | |
| [sellMenuOnItemChange](src/shop.zig#L170) — fn | [PAL_SellMenu_OnItemChange](resources/sdlpal-master/uigame.c#L1710) | |
| [sellMenu](src/shop.zig#L191) — pub fn | [PAL_SellMenu](resources/sdlpal-master/uigame.c#L1755) | also serves as pawn shop |

## text.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [initText](src/text.zig#L68) — pub fn | [PAL_InitText](resources/sdlpal-master/text.c#L649) | DOS BIG5 path; .msg/.dat preloaded by main |
| [getWord](src/text.zig#L111) — pub fn | [PAL_GetWord](resources/sdlpal-master/text.c#L966) | returns raw BIG5 (no decode) |
| [getMsg](src/text.zig#L122) — pub fn | [PAL_GetMsg](resources/sdlpal-master/text.c#L988) | |
| [charWidth](src/text.zig#L133) — fn | inside [PAL_CharWidth](resources/sdlpal-master/font.c#L611) | text-byte variant |
| [nextChar](src/text.zig#L140) — fn | inside [PAL_DrawText](resources/sdlpal-master/text.c#L1075) | byte→char advance |
| [drawCharOnSurface](src/text.zig#L149) — fn | [PAL_DrawCharOnSurface](resources/sdlpal-master/font.c#L522) | |
| [drawText](src/text.zig#L158) — pub fn | [PAL_DrawText](resources/sdlpal-master/text.c#L1075) | |
| [dialogSetDelayTime](src/text.zig#L188) — pub fn | [PAL_DialogSetDelayTime](resources/sdlpal-master/text.c#L1186) | |
| [startDialog](src/text.zig#L193) — pub fn | [PAL_StartDialog](resources/sdlpal-master/text.c#L1208) | |
| [startDialogWithOffset](src/text.zig#L197) — pub fn | [PAL_StartDialogWithOffset](resources/sdlpal-master/text.c#L1219) | |
| [drawCharFace](src/text.zig#L242) — fn | inside [PAL_StartDialogWithOffset](resources/sdlpal-master/text.c#L1219) | face sprite blit |
| [dialogWaitForKeyWithMaximumSeconds](src/text.zig#L266) — fn | [PAL_DialogWaitForKeyWithMaximumSeconds](resources/sdlpal-master/text.c#L1356) | |
| [dialogWaitForKey](src/text.zig#L310) — fn | [PAL_DialogWaitForKey](resources/sdlpal-master/text.c#L1451) | |
| [displayText](src/text.zig#L320) — fn | inside [PAL_ShowDialogText](resources/sdlpal-master/text.c#L1616) | byte-stream renderer (BIG5) |
| [drawOneChar](src/text.zig#L416) — fn | inside [PAL_ShowDialogText](resources/sdlpal-master/text.c#L1616) | one glyph w/ shadow |
| [perCharDelay](src/text.zig#L434) — fn | inside [PAL_ShowDialogText](resources/sdlpal-master/text.c#L1616) | per-char timing |
| [showDialogText](src/text.zig#L446) — pub fn | [PAL_ShowDialogText](resources/sdlpal-master/text.c#L1616) | |
| [clearDialog](src/text.zig#L511) — pub fn | [PAL_ClearDialog](resources/sdlpal-master/text.c#L1752) | |
| [endDialog](src/text.zig#L534) — pub fn | [PAL_EndDialog](resources/sdlpal-master/text.c#L1787) | |
| [isInDialog](src/text.zig#L545) — pub fn | [PAL_IsInDialog](resources/sdlpal-master/text.c#L1820) | |

## ui.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [menuItemColorSelected](src/ui.zig#L32) — pub fn | macro `MENUITEM_COLOR_SELECTED_*` | uses `PAL_GetTickCount` cycle |
| [initUI](src/ui.zig#L69) — pub fn | [PAL_InitUI](resources/sdlpal-master/ui.c#L52) | |
| [freeUI](src/ui.zig#L77) — pub fn | [PAL_FreeUI](resources/sdlpal-master/ui.c#L93) | |
| [saveScreenArea](src/ui.zig#L85) — fn | inside [PAL_CreateBoxWithShadow](resources/sdlpal-master/ui.c#L131) | screen-area copy helper |
| [restoreScreenArea](src/ui.zig#L110) — fn | inside [PAL_DeleteBox](resources/sdlpal-master/ui.c#L355) | screen-area restore helper |
| [createBoxInternal](src/ui.zig#L133) — fn | [PAL_CreateBoxInternal](resources/sdlpal-master/ui.c#L27) | |
| [createBox](src/ui.zig#L143) — pub fn | [PAL_CreateBox](resources/sdlpal-master/ui.c#L119) | |
| [createBoxWithShadow](src/ui.zig#L147) — pub fn | [PAL_CreateBoxWithShadow](resources/sdlpal-master/ui.c#L131) | |
| [createSingleLineBox](src/ui.zig#L207) — pub fn | [PAL_CreateSingleLineBox](resources/sdlpal-master/ui.c#L242) | |
| [createSingleLineBoxWithShadow](src/ui.zig#L211) — pub fn | [PAL_CreateSingleLineBoxWithShadow](resources/sdlpal-master/ui.c#L252) | |
| [deleteBox](src/ui.zig#L259) — pub fn | [PAL_DeleteBox](resources/sdlpal-master/ui.c#L355) | |
| [drawNumber](src/ui.zig#L266) — pub fn | [PAL_DrawNumber](resources/sdlpal-master/ui.c#L640) | |
| [textWidth](src/ui.zig#L308) — pub fn | [PAL_TextWidth](resources/sdlpal-master/ui.c#L749) | |
| [wordWidth](src/ui.zig#L325) — pub fn | [PAL_WordWidth](resources/sdlpal-master/ui.c#L836) | |
| [wordMaxWidth](src/ui.zig#L331) — pub fn | [PAL_WordMaxWidth](resources/sdlpal-master/ui.c#L797) | |
| [menuTextMaxWidth](src/ui.zig#L342) — pub fn | [PAL_MenuTextMaxWidth](resources/sdlpal-master/ui.c#L763) | |
| [drawMenuLabel](src/ui.zig#L351) — fn | inside [PAL_ReadMenu](resources/sdlpal-master/ui.c#L401) | label drawing helper |
| [readMenu](src/ui.zig#L359) — pub fn | [PAL_ReadMenu](resources/sdlpal-master/ui.c#L401) | |

## uibattle.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [playerInfoBox](src/uibattle.zig#L23) — pub fn | [PAL_PlayerInfoBox](resources/sdlpal-master/uibattle.c#L31) | PAL_CLASSIC layout |

## uigame.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [selectionMenu](src/uigame.zig#L37) — pub fn | [PAL_SelectionMenu](resources/sdlpal-master/uigame.c#L242) | |
| [tripleMenu](src/uigame.zig#L98) — pub fn | [PAL_TripleMenu](resources/sdlpal-master/uigame.c#L320) | |
| [confirmMenu](src/uigame.zig#L104) — pub fn | [PAL_ConfirmMenu](resources/sdlpal-master/uigame.c#L343) | |
| [amountSelect](src/uigame.zig#L113) — pub fn | — | zigpal-specific quantity picker (used by debug + shop) |
| [switchMenu](src/uigame.zig#L193) — pub fn | [PAL_SwitchMenu](resources/sdlpal-master/uigame.c#L368) | |
| [showCash](src/uigame.zig#L202) — pub fn | [PAL_ShowCash](resources/sdlpal-master/uigame.c#L451) | |
| [inGameMenuOnItemChange](src/uigame.zig#L212) — fn | [PAL_InGameMenu_OnItemChange](resources/sdlpal-master/uigame.c#L922) | |
| [systemMenuOnItemChange](src/uigame.zig#L216) — fn | [PAL_SystemMenu_OnItemChange](resources/sdlpal-master/uigame.c#L494) | |
| [quitGame](src/uigame.zig#L223) — pub fn | [PAL_QuitGame](resources/sdlpal-master/uigame.c#L2059) | shutdown via libretro quit_flag |
| [systemMenu](src/uigame.zig#L232) — pub fn | [PAL_SystemMenu](resources/sdlpal-master/uigame.c#L516) | music/sound submenus are no-ops (no audio) |
| [drawOpeningMenuBackground](src/uigame.zig#L290) — pub fn | [PAL_DrawOpeningMenuBackground](resources/sdlpal-master/uigame.c#L42) | |
| [getSavedTimes](src/uigame.zig#L303) — fn | inside [PAL_SaveSlotMenu](resources/sdlpal-master/uigame.c#L169) | wrapper around save.zig |
| [saveSlotMenu](src/uigame.zig#L309) — pub fn | [PAL_SaveSlotMenu](resources/sdlpal-master/uigame.c#L169) | |
| [openingMenu](src/uigame.zig#L348) — pub fn | [PAL_OpeningMenu](resources/sdlpal-master/uigame.c#L83) | |
| [inGameMenu](src/uigame.zig#L384) — pub fn | [PAL_InGameMenu](resources/sdlpal-master/uigame.c#L944) | |

## util.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [getTicks](src/util.zig#L22) — pub fn | replaces `SDL_GetTicks` | libretro virtual-time variant |
| [advanceTicks](src/util.zig#L26) — pub fn | — | libretro-only (driven by `frame_time_callback`) |
| [shouldQuit](src/util.zig#L30) — pub fn | — | libretro-only |
| [delay](src/util.zig#L37) — pub fn | [UTIL_Delay](resources/sdlpal-master/util.c#L280) | virtual-time variant |
| [delayUntil](src/util.zig#L46) — pub fn | `PAL_DelayUntil` macro / helper | virtual-time variant |
| [nextRand](src/util.zig#L57) — fn | inside [RandomLong](resources/sdlpal-master/util.c#L222) | LCG core |
| [randomLong](src/util.zig#L62) — pub fn | [RandomLong](resources/sdlpal-master/util.c#L222) | |
| [randomFloat](src/util.zig#L67) — pub fn | [RandomFloat](resources/sdlpal-master/util.c#L251) | |
| [randomFloatRange](src/util.zig#L72) — pub fn | [RandomFloat](resources/sdlpal-master/util.c#L251) | overload: takes (min,max) |
| [logInfo](src/util.zig#L77) — pub fn | [UTIL_LogOutput](resources/sdlpal-master/util.c#L890) | thin wrapper over std.log |
| [logError](src/util.zig#L81) — pub fn | [UTIL_LogOutput](resources/sdlpal-master/util.c#L890) | thin wrapper over std.log |
| [readFileFully](src/util.zig#L89) — pub fn | loosely [UTIL_OpenFile](resources/sdlpal-master/util.c#L451) | libretro libc-based slurp |

## video.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [rgb565](src/video.zig#L49) — inline fn | inside [VIDEO_UpdateScreen](resources/sdlpal-master/video.c#L517) | libretro RGB565 packer (zigpal-specific) |
| [setPalette](src/video.zig#L54) — pub fn | [VIDEO_SetPalette](resources/sdlpal-master/video.c#L646) | |
| [updateScreen](src/video.zig#L64) — pub fn | [VIDEO_UpdateScreen](resources/sdlpal-master/video.c#L517) | always full-frame (no dirty rect) |
| [backupScreen](src/video.zig#L105) — pub fn | inside [VIDEO_FadeScreen](resources/sdlpal-master/video.c#L1130) | swap to gpScreenBak |
| [restoreScreen](src/video.zig#L109) — pub fn | inside [VIDEO_FadeScreen](resources/sdlpal-master/video.c#L1130) | restore from gpScreenBak |
| [shakeScreen](src/video.zig#L114) — pub fn | [VIDEO_ShakeScreen](resources/sdlpal-master/video.c#L1030) | |
| [fadeScreen](src/video.zig#L123) — pub fn | [VIDEO_FadeScreen](resources/sdlpal-master/video.c#L1130) | |

## yj1.zig

| Zigpal | SDLPAL | Notes |
| --- | --- | --- |
| [getBits](src/yj1.zig#L47) — fn | inside [YJ1_Decompress](resources/sdlpal-master/yj1.c#L129) | bit reader |
| [getLoop](src/yj1.zig#L66) — fn | inside [YJ1_Decompress](resources/sdlpal-master/yj1.c#L129) | loop-count decoder |
| [getCount](src/yj1.zig#L79) — fn | inside [YJ1_Decompress](resources/sdlpal-master/yj1.c#L129) | LZSS count decoder |
| [decompress](src/yj1.zig#L92) — pub fn | [YJ1_Decompress](resources/sdlpal-master/yj1.c#L129) | |
