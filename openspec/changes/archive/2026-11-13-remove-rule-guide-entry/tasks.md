## 1. 菜单与代码

- [x] 1.1 从 `addAssistiveSection` 移除「应用规则说明」菜单项，验证：中英文菜单中都不再出现该条目，且「应用规则…」仍在原位
- [x] 1.2 确认 `openRuleGuide()` 与 `RuleGuideView` 仍被首次引导路径使用，验证：新用户首次启动仍弹出引导，已处理用户重启不再弹出
- [x] 1.3 检查 `onboarding.title` 等文案仍被引导窗口引用，验证：窗口标题与正文显示正常，无空文案

## 2. 文档与规格

- [x] 2.1 检查 `README.md` 是否提到"菜单中可以重新打开规则说明"，如有则同步删除，验证：全文搜索无该表述
- [x] 2.2 确认主规格 `application-rule-onboarding` 的改动与实现一致，验证：`openspec validate remove-rule-guide-entry --strict` 通过

## 3. 回归

- [x] 3.1 手工回归：首次启动展示引导、处理后重启不展示、菜单无独立入口、规则窗口内容完整，验证：四项逐条打勾
- [x] 3.2 中英文各验证一次，验证：英文菜单无遗留的 "Application Rules Guide" 条目
