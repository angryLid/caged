---
name: mdx-notes
description: MDX authoring pitfalls and common gotchas. Load when writing or editing any .mdx file (especially Astro presentation slides) to avoid parse errors and rendering issues.
---

# MDX 编写要点

在 Astro 项目里写 `.mdx`（尤其演示幻灯片）时，按下面规则组织内容。规则分两类代价，先分清再动手：

- **fatal** — 解析直接失败，构建崩掉，必须规避。
- **cosmetic** — 不报错但渲染/布局跑偏，需要规避。

## fatal：守住解析器（_acorn_）

MDX 解析器（acorn）把 `{ ... }` 当 JS 表达式来读。下面三类写法都会逼它崩掉——每一条都给出正向写法。

### 用 `{/* */}` 写注释
注释用 JSX 注释 `{/* 注释 */}`，不要用 HTML 的 `<!-- -->`。后者会触发 acorn 报 `Unexpected character !`，即使写在 SVG 或 JSX 元素内部也一样。

### 脚本放进组件，而不是内联 `<script>`
内联 `<script>` 里的 `{ }` 和运算符会被 acorn 当 JSX 解析而出错。把脚本定义在 `.astro` 组件里 import 引入，或加 `is:inline` 指令。

### 样式放进 `.astro` / `.css`，而不是 `<style>` 块
任何 CSS 选择器块里的 `{ }` 都会让 acorn 失败——`@keyframes`、`@media`、普通选择器、`:root` 全都一样。把样式移进该 slide 用的 `.astro` 组件（自动 scoped，不污染全局），或单独 `.css` import；简单样式直接 inline `style={{ color: 'red' }}`。

## cosmetic：别让布局跑偏

### 换行交给 CSS，不交给行距
一条空行会生成一个 `<p>` 段落；单个换行是软换行（渲染为空格）。在 JSX 布局里裸换行会冒出意外的 `<p>`，带进多余的 margin/padding。要视觉间距时用 CSS（margin / gap / `<br>` / `display:block`），不要用空行撑高；`<p>` 内保持单行；纯文本要断行用行尾两个空格或 `<br>`。

### 字面量花括号要转义
`{ }` 在 MDX 里是表达式，不是文本。要显示字面量用 `&#123;100&#125;` 或 `{'{100}'}`。

### 遵守 JSX 语法
- `import` 全部放在文件顶部（frontmatter 之后、正文之前）。
- 自定义组件名以大写字母开头。
- `style` 属性值是对象：`style={{ color: 'red' }}`，不是字符串。

## 保存前的检查清单

- [ ] 注释用 `{/* */}`，文件里没有 `<!-- -->`
- [ ] 没有内联 `<script>`，没有 `<style>` 块
- [ ] JSX 布局内没有裸空行
- [ ] `<p>` 内部没有换行
- [ ] 字面量花括号已转义
- [ ] `import` 都在顶部
- [ ] `style` 用的是对象语法