# Agent 集成 SOP — 把新的 coding agent 接进 caged

本文档是往 caged 里集成一个新 agent（`pi`、`dsh`、`cmdc` 之外的第四、第五个……）
时必须遵守的规程。两条硬性要求，缺一不可：

1. **以高权限 / 无权限守卫模式运行** —— agent 本身已经跑在沙箱里（非 root、只读
   rootfs、`--cap-drop ALL`），它自己的权限弹窗/审批机制是多余的摩擦，必须关掉。
2. **sessions 放在 `/workspace` 下** —— 容器是即抛的，但 `/workspace` 是宿主机
   workspace 的 live bind mount；session 只有落在 `/workspace` 里，才能在容器销毁后
   存活、并且让不同 agent 之间互相查阅（pi 的会话、dsh 的会话、cmdc 的会话彼此可见）。

先看现状对照表，再看集成步骤。

## 现状对照表（三个已集成的 agent）

| Agent | 镜像/启动脚本 | 权限模式（要求 1） | session 落点（要求 2） | skills 落点 |
|---|---|---|---|---|
| **pi** | `scripts/start-container.sh pi` | pi 本身没有权限管理，天然全开；seed 里设了 `defaultProjectTrust: "always"` 消除信任弹窗 | `seed/.pi/agent/settings.json` → `"sessionDir": "/workspace/.pi/sessions"` | `seed/.pi/agent/skills/`（`~/.pi/agent/skills`） |
| **dsh** | `scripts/start-container.sh dsh` | `start-container.sh` 默认 `DSH_PERMISSION_MODE=danger-full-access`（dsh 官方"allow all"模式，`approval/policy: never`） | `seed/.dsh/cordis.patch.yml` → `session-persistence-jsonl` 段，root 指向 `/workspace/.dsh/sessions`（明文 JSONL，`compression: none`，方便其他 agent 直接读） | `seed/.dsh/skills/`（`$DSH_HOME/skills`，dsh 本地 provider 的 user 级 root） |
| **cmdc**（Command Code） | `scripts/start-container.sh cmdc` + `Containerfile.commandcode` | `seed/.commandcode/settings.json` → `"permissions": { "defaultMode": "bypass" }` | `scripts/commandcode-entrypoint.sh` 把 `~/.commandcode/projects` 和 `~/.commandcode/file-history` 懒迁移为指向 `/workspace/.commandcode/` 的 symlink | `seed/.commandcode/skills/`（`~/.commandcode/skills`） |

## 要求 1：高权限模式

**为什么。** caged 的隔离边界是容器本身：uid 1000、只读 rootfs、无 capabilities、
`--no-new-privileges`（见 `docs/SECURITY.md`）。agent 在容器里能做的任何事都被这层
边界限制住了，它自己的权限系统只会：
- 在无人值守/后台运行时**卡死**（一个没人回答的弹窗挂住整个任务）；
- 给 agent 无意义的摩擦，且它的"权限判断"本身不可信（被 prompt 注入就能绕过）。

所以 caged 的立场是：**沙箱外不设防，沙箱内也不设防**。

**怎么做。** 每个 agent 关闭权限守卫的方式不同，按它自己的机制来：

| agent 机制 | caged 的做法 |
|---|---|
| 有官方"允许一切"模式/flag | 用官方机制，如 dsh 的 `DSH_PERMISSION_MODE=danger-full-access`、cmdc 的 `--yolo` / `permissions.defaultMode: "bypass"` |
| 本身无权限管理 | 什么都不用做，但把信任类设置开掉（pi 的 `defaultProjectTrust: "always"`） |
| 有 deny/ask 规则 | **不要**给 agent 配 `deny`/`ask` 规则 —— 那会重新引入弹窗。权限全交给容器边界 |

**cmdc 的两个坑（踩过的）：**

1. **项目级 settings 覆盖 HOME 级。** cmd 的配置层级是
   `<cwd>/.commandcode/settings.json` > `$HOME/.commandcode/settings.json`。
   容器里 `$HOME=/agent-home`（seed 挂载），cwd 是 `/workspace`。如果 workspace 里
   存在一个带 `"defaultMode": "default"` 或 `deny`/`ask` 规则的项目级
   `settings.json`，它会**盖掉** seed 里的 bypass。集成时必须检查两层：
   - `seed/.commandcode/settings.json`（HOME 级，仓库里管）→ `defaultMode: "bypass"`
   - 各 workspace 的 `.commandcode/settings.json`（项目级，交互时"允许并记住"会往这写）
     → 也必须是 bypass，不能残留 `default` 模式或规则列表

2. **`COMMANDCODE_HOME` 环境变量对 cmd 无效。** cmd 硬编码 session/状态目录为
   `$HOME/.commandcode`（读 `$HOME`，不读任何 override 变量）。别想靠环境变量改它的
   状态目录，改目录只能靠 entrypoint 里的 symlink 方案（见要求 2）。

## 要求 2：sessions 放在 /workspace

**为什么。** 容器是即抛的（`--rm`，每次 `start-container.sh` 重建）。session 如果写在
容器内或 seed 里，要么随容器消失，要么堆在 repo 的 `seed/` 里被 git 追踪/污染。
`/workspace` 是宿主机 workspace 的 live mount，session 放这里：
- 容器销毁后 session 还在（`$CAGED_WORKSPACE/.pi/sessions` 等）；
- pi / dsh / cmdc 都在同一个 workspace 上跑，彼此能读到对方的会话记录；
- 每个 agent 的 session 目录按 agent 名隔离，互不冲突。

**约定目录：**

| agent | workspace 内目录 |
|---|---|
| pi | `/workspace/.pi/sessions/` |
| dsh | `/workspace/.dsh/sessions/` |
| cmdc | `/workspace/.commandcode/`（`projects/` 是会话，`file-history/` 是 rewind 备份） |

`.gitignore` 里已有对应条目（`.pi/sessions/`、`.dsh/sessions/`、`.commandcode/`），
新 agent 的 session 目录也要加进去。

**怎么做。** 三种机制，按 agent 支持哪种选哪种：

1. **原生配置项**（最干净）—— pi 用 `"sessionDir"`，dsh 用 patch 配置，直接指向
   `/workspace/...`。
2. **启动脚本传参/环境变量** —— 如果 agent 支持 CLI flag 或 env 指定 session 目录，
   在 `start-container.sh` 对应 mode 分支里设。
3. **entrypoint symlink 重定向**（兜底）—— 如果 agent 硬编码目录（cmdc 就是），
   在它自己的 entrypoint 脚本里把硬编码路径 relocation 到 `/workspace`：首次启动把
   seed 里已有的真实数据搬过去，之后用 symlink 指向 workspace，幂等。

cmdc 的 symlink 方案是 `scripts/commandcode-entrypoint.sh` 里的
`relocate_to_workspace` 函数：对 `projects` 和 `file-history` 两个子目录，先判断
seed 路径是 symlink（已迁移）、真实目录（搬数据）、还是不存在（直接建），统一落到
`/workspace/.commandcode/<subdir>` 并留 symlink。

## 集成新 agent 的步骤清单

1. **建镜像**：`Containerfile.<agent>`，`FROM caged-base` 或基于现有镜像，跑在
   非 root 用户上，入口用 `tini`。
2. **加启动模式**：`scripts/start-container.sh` 加一个 case 分支（镜像 tag、容器名、
   内存、`DEFAULT_CMD`、该 agent 需要的 env），并接入 `/workspace` + `/agent-home`
   两个 mount。
3. **关权限守卫**：按要求 1 找到该 agent 的"允许一切"开关，写进 seed 配置或启动
   脚本，作为默认值。明确不留 `deny`/`ask` 规则。
4. **session 落 workspace**：按要求 2 三选一，把 session 目录指到
   `/workspace/.<agent>/...`。
5. **skills**：确认该 agent 读 Agent Skills 标准（每技能一个目录、内含
   `SKILL.md` + YAML frontmatter）。找到它扫描的 skills 根目录，在
   `seed/skills.json` 的 `linkTargets[]` 加一行（`dir` 相对 seed 根），并在它的
   entrypoint 里加上与 `scripts/entrypoint.sh` 第 3 步相同的 `--link-only`
   skills 同步（镜像已从 base 继承 vendor 和 skills-sync.mjs）。
6. **gitignore**：在 `.gitignore` 加 workspace 侧 session 目录 + seed 侧生成的
   `skills/` 目录。
7. **文档**：更新 README 的现状对照表，把新 agent 的行补上。

## 验证

```sh
# 权限：进容器跑一个本来会触发弹窗的操作（写文件、跑任意 shell），应无提示直接执行
scripts/start-container.sh <agent>    # 交互里让 agent 建文件/跑命令，观察有无弹窗

# session：容器内跑一段会话后退出，host 侧检查 workspace 目录
ls "$CAGED_WORKSPACE"/.pi/sessions      # pi 会话落在这里
ls "$CAGED_WORKSPACE"/.dsh/sessions     # dsh 会话
ls "$CAGED_WORKSPACE"/.commandcode/projects/<cwd-slug>/   # cmdc 会话

# 重启容器，`<agent> -c` / resume 应能看到刚才的会话（数据跨容器存活）
```
