# Instances Empty State Compact Design

## Goal

优化展开态首页在“没有会话”时的视觉表现：

- 保留当前空态文案
- 去掉大面积无意义留白
- 让整个 `instances` 打开态在无会话时明显变矮
- 有音乐卡片时，整体观感更像“音乐卡片 + 一块紧凑空态”，而不是一个被撑满的大面板

## Scope

In scope:

- 调整 `ClaudeInstancesView` 的空态布局
- 调整 `instances` 页面在 `NotchViewModel` 中的打开高度策略
- 保留现有三行空态文案
- 为无会话状态定义更紧凑的面板高度和内容高度
- 与现有音乐卡片共存，不改音乐卡片内容

Out of scope:

- 会话列表滚动逻辑
- `ChatView` 聊天页布局
- `NotchMenuView` 菜单页布局
- 空态文案改写
- 打开态外层壳体的宽度策略

## Existing Context

当前 `instances` 页面在 `NotchViewModel` 中使用固定打开高度 `320`。

在 `ClaudeInstancesView` 中：

- 有会话时，会话列表已经改成了自适应高度 + 超出滚动
- 无会话时，`emptyState` 使用 `.frame(maxWidth: .infinity, maxHeight: .infinity)`

这意味着即使把 `ClaudeInstancesView` 内部空态做成紧凑块，外层面板本身仍然不会变矮，因此“无会话”时依旧会显得空。

## Approach

同时调整两层：

1. `NotchViewModel` 为 `instances` 页面提供动态打开高度
2. `ClaudeInstancesView` 将空态从“填满剩余空间”改成“一个紧凑且居中的内容块”

建议规则：

- 有会话时，继续维持当前约 `320` 的打开高度基线，并由列表内部处理自适应/滚动
- 无会话且无音乐时，使用明显更短的打开高度
- 无会话且有音乐时，打开高度应等于“音乐卡片高度 + 紧凑空态 + 合理间距”，而不是固定 `320`

这样做的结果是：

- 改动真正影响面板外轮廓，而不只是内容摆放
- `instances` 页在无会话时可以明显变矮
- 有会话页面继续沿用现在的列表逻辑
- 无会话时视觉上明显更短、更紧凑

## Layout Rules

- 空态内容保留三行：
  - `No sessions`
  - `Run claude in terminal`
  - `or start a codex session`
- 无会话时，面板总高度应低于当前固定 `320`
- 空态内容应垂直居中在一个较短的容器内
- 该容器应有明确的紧凑高度，而不是无限拉伸
- 有音乐卡片时，空态应自然贴在音乐卡片下方并保持适度呼吸感
- 无音乐卡片时，空态仍然保持紧凑，不重新退化为整页居中大留白

## Visual Direction

- 主标题保持当前语义，但可以略强化可读性
- 副文案保留层次差异
- 减少大面积空白，比当前版本更“像一个状态卡片”
- 不引入新的图标、插画或按钮，避免喧宾夺主

## Data Flow

此改动需要同时落在：

- `NotchViewModel`
- `ClaudeInstancesView`

可能只需要：

- 一个 `instances` 页的动态高度计算入口
- 一个空态目标高度常量
- 一个空态容器样式

不需要修改 `SessionStore` 或会话模型。

## Error Handling And Fallbacks

- 如果音乐卡片存在，面板高度应随音乐卡片和空态组合一起收紧
- 如果会话重新出现，应恢复到当前列表页面的打开高度策略，而不是卡在空态高度

## Testing

手动验证即可：

- 无音乐 + 无会话：面板整体明显更矮，空态明显更紧凑
- 有音乐 + 无会话：面板整体明显收紧，不再有大片空白
- 文案保持原样
- 有会话时不影响当前列表行为

## Risks

- 如果空态高度收得过头，可能显得过于挤压
- 如果 `NotchViewModel` 的高度切换条件定义不稳，可能在“会话出现/消失”时造成高度跳变
- 如果容器层次做得太重，可能抢走音乐卡片的视觉重点

## Success Criteria

- 无会话时整个 `instances` 打开态明显更矮
- 无会话时页面不再显得空荡
- 文案保持不变
- 有音乐卡片时整体视觉高度更协调
- 有会话时现有列表行为不受影响
