# 角色开发与实战

- 每开发一个新角色，从最新 `master` 创建独立的 `feature/<角色英文ID>-strategy` 分支。
- 当前角色危险 5 未通关时，在本角色分支复盘、优化和复测，不因失败跳过或挪到队尾。
- 仅在原生第 20 波胜利且原生存档确认该角色危险 5 通关后，将角色分支合并到 `master` 并推送。编译、自检或提前预测不算通关。
- 合并完成后，才从更新后的 `master` 建下个角色分支并开始开发、实战。逐局控制器不得直接自动跳到下个角色。
- 保持 1 倍原速，不录视频。保留状态、事件日志、逐局分析和原生结算截图；不改原生存档或解锁条件。
- 不在对局中重打包、覆盖或热加载策略；等待当前局自然结束后再加载新版本。

目前角色顺序：游侠通关后再继续异变体及后续未完成角色。历史 `feature/brawler-strategy` 含早期混合开发记录，保留历史，不再往该分支追加其他角色开发。

Next character by explicit user direction: Crazy (character_crazy), feature/crazy-strategy. Mutant D5 verified and merged.

Current user-selected next character: Mage (character_mage), feature/mage-strategy. Crazy D5 verified and merged.

Current user-selected character: Chunky (character_chunky), feature/chunky-strategy. Mage D5 verified and merged.

Current campaign character: Old (character_old), feature/old-strategy. Chunky D5 verified and merged. Follow native base_game_set character order, skipping only saved clears; next Lucky, then Generalist because Mutant is already cleared.

Current campaign character: Lucky (character_lucky), feature/lucky-strategy. Old D5 verified and merged; progress 8/10. Next native-order uncleared role: Generalist.
