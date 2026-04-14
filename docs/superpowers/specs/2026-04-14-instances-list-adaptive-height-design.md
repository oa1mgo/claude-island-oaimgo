# Instances List Adaptive Height Design

## Goal

把打开态首页里的会话列表从固定占满式高度改成自适应高度：

- 内容较少时，列表区域随内容收缩
- 内容较多时，列表区域在达到上限后停止增长，并在内部滚动

这个上限的视觉基准应当约等于：

- `1` 个 `MusicCardView`
- `4.5` 个 `InstanceRow`

## Scope

In scope:

- 调整 `ClaudeInstancesView` 的会话列表高度行为
- 保留当前音乐卡片位于列表上方的结构
- 让会话列表在超出最大高度时滚动
- 让会话数量较少时不再撑满整个展开面板

Out of scope:

- `ChatView` 聊天消息页高度策略
- `NotchMenuView` 菜单页滚动策略
- `MusicCardView` 和 `InstanceRow` 的视觉样式重做
- 展开面板宽度、顶部 header、聊天输入栏行为调整

## Existing Context

当前打开态首页由 `ClaudeInstancesView` 负责：

- `MusicCardView` 位于上方
- 会话列表由 `ScrollView` + `LazyVStack` 渲染

列表已经具备滚动能力，但缺少一个和设计目标一致的最大高度约束，因此在内容较少时仍然表现得像固定高度区域。

## Approach

采用“实测内容高度 + 上限裁剪”的方案，而不是硬编码一个静态高度常量。

实现思路：

1. 测量音乐卡片的实际渲染高度
2. 测量单个会话行的实际渲染高度
3. 计算列表区域的目标最大高度：`musicCardHeight + instanceRowHeight * 4.5`
4. 让会话列表容器使用 `min(contentHeight, targetMaxHeight)` 作为最终高度
5. 当内容高度超过该值时，保留现有 `ScrollView`，由内部滚动承载溢出内容

这样做可以让阈值跟随真实 UI，而不是依赖脆弱的经验常量。

## Layout Rules

- 当没有音乐卡片时，最大高度基准退化为 `4.5` 个 `InstanceRow`
- 当音乐卡片存在时，最大高度基准为 `MusicCardView + 4.5` 个 `InstanceRow`
- 当会话总高度低于最大高度时，列表区域按内容自然收缩
- 当会话总高度高于最大高度时，列表区域固定在最大高度，内部滚动
- 空态继续保持当前居中展示，不引入滚动区域占位

## Data Flow

需要在 `ClaudeInstancesView` 内引入轻量级高度测量状态：

- `musicCardHeight`
- `instanceRowHeight`
- `listContentHeight`

这些状态只服务于布局，不进入 `SessionState` 或全局模型。

## Error Handling And Fallbacks

- 如果首帧还未拿到测量值，先使用当前内容自然布局，再在测量完成后平滑收敛到目标高度
- 如果没有音乐卡片，则不等待音乐高度测量
- 如果列表为空，则直接展示空态，不套用列表高度逻辑

## Testing

手动验证即可：

- 无音乐，`1-4` 个会话：列表高度应随内容收缩
- 无音乐，`5+` 个会话：列表应在约 `4.5` 行处开始滚动
- 有音乐，少量会话：整体高度应为音乐卡片加少量会话，不占满
- 有音乐，多会话：应在“音乐卡片 + 约 `4.5` 行会话”处开始滚动
- 切换音乐显示状态时，高度阈值应正确变化
- 空态仍保持当前展示方式

## Risks

- 如果高度测量绑定位置不对，可能造成首帧轻微跳动
- `LazyVStack` 的内容高度测量需要绑定在稳定容器上，否则可能出现计算不一致
- `4.5` 行是视觉目标，不会精确到像素级“半行切割”，应优先保证整体观感自然

## Success Criteria

- 会话列表不再表现为固定高度区域
- 少量会话时，打开态首页高度更紧凑
- 多量会话时，列表在目标阈值处开始滚动
- 音乐卡片存在与否都能得到合理的最大高度
- 空态、聊天页、菜单页行为保持不变
