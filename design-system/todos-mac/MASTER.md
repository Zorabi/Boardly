# Boardly Design System

> Source of truth for the native macOS human-task kanban prototype.

## Product character

- Calm, compact, dark-first and content-led.
- Native macOS behavior takes priority over reproducing a web layout.
- One primary action per screen; secondary actions live in toolbars, context menus, and the Inspector.
- The interface should disappear while the board remains easy to scan.

## Semantic color tokens

Use semantic SwiftUI colors in implementation. The values below are visual targets, not component-level hard-coded colors.

| Token | Dark target | Light target | Usage |
|---|---:|---:|---|
| `appBackground` | `#111114` | `#F4F4F6` | Window content |
| `sidebarSurface` | `#17171B` | `#ECECEF` | Sidebar |
| `columnSurface` | `#151519` | `#EBEBEE` | Board columns |
| `cardSurface` | `#202025` | `#FFFFFF` | Task cards |
| `cardHover` | `#27272D` | `#F8F8FA` | Pointer hover |
| `separator` | white 8% | black 10% | Dividers and card borders |
| `primaryText` | `#F3F3F5` | `#17171A` | Titles and task names |
| `secondaryText` | `#A2A2AA` | `#62626A` | Metadata |
| `accent` | `#7567F8` | `#6253E8` | Selection and primary action |
| `danger` | `#FF665F` | `#D93632` | Destructive actions only |

Status is never communicated by color alone:

| Status | Color | SF Symbol |
|---|---|---|
| Backlog | secondary gray | `tray` |
| To do | blue | `circle` |
| In progress | amber | `clock` |
| Done | green | `checkmark.circle.fill` |

## Typography

- Use San Francisco through SwiftUI semantic styles; do not bundle a web font.
- Window title: `.title3.weight(.semibold)`.
- Column title and toolbar labels: `.subheadline.weight(.semibold)`.
- Card title: `.body.weight(.medium)`, two lines maximum on the board.
- Metadata: `.caption`, never below 11 pt at the default scale.
- Use monospaced digits only for counts and checklist progress.

## Spacing and shape

- Base grid: 4 pt.
- Common spacing: 4 / 8 / 12 / 16 / 24 / 32 pt.
- Sidebar row height: 30–32 pt; toolbar controls retain native hit regions.
- Board column width: 280 pt default, 248 pt minimum, 360 pt maximum.
- Card padding: 12 pt; card gap: 8 pt; column gap: 12 pt.
- Card corner radius: 9 pt; column corner radius: 12 pt; sheets use native presentation.
- Prefer a 1 px semantic border to prominent shadows. Use only a faint shadow while dragging.

## Window composition

Use a native `NavigationSplitView`:

1. Sidebar: Inbox, Today, Board, then Projects.
2. Content: toolbar plus the horizontally scrolling board.
3. Inspector: selected task details, collapsible with `⌥⌘I`.

Minimum useful window size is 960×620. Preserve column scroll positions and task selection when navigating.

## Interaction rules

- `⌘N`: create a task in the current context.
- `⌘K`: focus search.
- `⌘1` / `⌘2` / `⌘3`: Inbox / Today / Board.
- Return opens the selected task; Escape closes sheets or clears selection.
- Drag cards within or across columns, with insertion feedback and undo.
- Every drag action also has a context-menu and keyboard equivalent.
- Task details autosave. Do not require a web-style Save button.
- Destructive actions are separated and support undo where practical.
- Use native focus rings, context menus, tooltips, VoiceOver labels and keyboard traversal.

## Motion

- Use SwiftUI's native short ease or spring for card insertion and column changes, 150–220 ms.
- No decorative entrance animation or continuously moving UI.
- Respect Reduce Motion; replace movement with crossfades when enabled.
- Pointer hover changes surface/border only and must not shift layout.

## Light and dark mode

- Dark mode is the signature and default presentation. The prototype does not follow a light system appearance.
- Keep semantic tokens so a first-class light theme can be added later without changing component structure.
- Primary text must reach WCAG AA contrast; secondary content must remain legible.
- Selection, keyboard focus, overdue, and status must remain distinguishable in both appearances.

## Avoid

- No Agents, skills, MCP, machines, model services, or scheduler navigation.
- No glass blur on every surface, neon gradients, oversized radii, or floating mobile-style action buttons.
- No tiny icon-only controls without tooltips and accessibility labels.
- No status conveyed only by colored dots.
- No modal task editor for routine edits; use the Inspector.
- No configurable workflow builder in the first release.

## Delivery checklist

- [ ] All core actions are available without drag and without a pointer.
- [ ] VoiceOver announces task title, project, status, due state, and checklist progress.
- [ ] Reduced Motion and increased text size preserve usability.
- [ ] Empty, loading, search-no-result, and error states offer a clear next action.
- [ ] Light and dark mode have independently verified contrast.
- [ ] The board remains usable at the minimum window size.
