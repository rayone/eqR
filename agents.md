---
title: "AGENTS.md: Autonomous Developer Agent Rulebook & Bounded-Context Engineering SOP"
tags:
  - engineering/sop
  - agent-rulebook
  - static-analysis
  - golang
  - bash
  - csharp
  - javascript
  - typescript
  - rust
  - python
  - swift
status: mandatory-standard
updated: 2026-10-27
---

# AGENTS.md: Autonomous Developer Agent Rulebook

> [!IMPORTANT] **Core Engineering Mandate**
> Every autonomous coding agent and engineer operating on this repository must use the deterministic toolchains, pre-computed context indexes, bounded-context scripts, and automated Git pre-commit gates defined in this specification. Never allow the coding agent to browse repositories freely, read entire files, ingest raw compiler/test logs, or invent duplicate domain types.

---

## 1. Executive Architecture: Bounded-Context Agent Operations

When an AI coding agent ingests entire source files, unbounded `grep` output, or raw multi-hundred-line compiler backtraces, its active context window exceeds **12k–16k tokens**. Past this threshold, attention dilution causes the agent to:

1. Violate architectural invariants and invent duplicate types, structs, records, classes, or interfaces.
2. Hallucinate function signatures and break downstream callers across packages and modules.
3. Enter destructive edit-compile-fail loops that corrupt the working tree and exhaust compute budgets.

To eliminate context overflow and codebase corruption across **Go, Bash, C# (.NET), JavaScript/TypeScript, Rust, Python, and Swift** repositories, this rulebook shifts repository discovery, static analysis, and impact verification **out of the model's context window** and into deterministic CLI tools that execute in milliseconds at zero token cost.

| Engineering Goal | Deterministic Tooling Layer (Zero Token Cost) | Pre-Computed Artifact / Gate | Agent Workflow Command |
| :--- | :--- | :--- | :--- |
| **1. Zero-Destruction Safety** | `lefthook`, `graph-indexer`, `serena` MCP, `go vet`, `golangci-lint`, `shellcheck`, `shfmt`, `dotnet build -warnaserror`, `eslint`, `tsc`, `cargo check`, `ruff`, `swiftlint` | `lefthook.yml`, `.agent/scripts/verify.sh`, `.agent/scripts/check-duplicate-types.sh` | `/safe-verify` |
| **2. Loop & Context Protection** | Harness Extension / Hook, POSIX `sed`, `nl`, `timeout`, token circuit breaker | `.agent/extensions/context-circuit-breaker.ts`, `.agent/scripts/slice.sh` | Automatic (Enforced on every tool call) |
| **3. Dead-Code Pruning** | `deadcode` (Go), `golangci-lint` (`unused`), `shellcheck` (`SC2034`), Roslyn (`IDE0051`/`IDE0052`), `knip`, `clippy`, `ruff`, `periphery` | `.agent/context/dead_code.txt` | `/prune-dead` |
| **4. Runtime, Concurrency & UI Perf** | `ast-grep (sg)`, `ripgrep (rg)`, language-specific AST & concurrency analyzers | `.agent/context/bottlenecks.txt`, `.ast-grep/rules/bottlenecks.yml` | `/perf-fix` |
| **5. Surgical Feature Injection** | `repomix --compress`, `graph-indexer` (`callgraph`, `refs`, `read`), `serena` MCP / LSP (`gopls`, `csharp-ls`, `tsserver`, `rust-analyzer`, `bash-language-server`) | `.agent/context/api_surface.txt`, `.agent/context/anchor_neighborhood.txt` | `/inject-feature` |

### Standard Repository Directory Layout

Every repository maintains the following standardized `.agent/` and static-analysis structure:

~~~text
repo-root/
├── AGENTS.md                                  # Master system instructions loaded automatically by the coding agent
├── lefthook.yml                               # Automated pre-commit compiler, linter, LSP, and call-graph gates
├── .ast-grep/
│   ├── sgconfig.yml                           # AST-Grep project configuration
│   └── rules/
│       └── bottlenecks.yml                    # Deterministic AST rules for Go, Bash, C#, JS/TS, Rust, Python, Swift
└── .agent/
    ├── settings.json                          # Agent settings, MCP bindings, permissions, and token budgets
    ├── context/                               # Pre-computed zero-token static analysis & neighborhood files (gitignored)
    │   ├── api_surface.txt                    # Compressed type/struct/interface/class/function skeletons
    │   ├── dead_code.txt                      # Exact unused code hit-list across all supported languages
    │   ├── bottlenecks.txt                    # Exact concurrency, allocation, shell, and UI hot-path hit-list
    │   └── anchor_neighborhood.txt            # 1-hop neighborhood slice generated for /inject-feature
    ├── extensions/
    │   └── context-circuit-breaker.ts         # Hard 12k token cap, full-file read blocker, and 2-strike loop killer
    ├── scripts/
    │   ├── bootstrap-repo.sh                  # One-command repo initialization
    │   ├── refresh-all-context.sh             # Master background indexer (updates .agent/context/*.txt)
    │   ├── index-api-surface.sh               # Generates .agent/context/api_surface.txt
    │   ├── index-dead-code.sh                 # Generates .agent/context/dead_code.txt
    │   ├── index-bottlenecks.sh               # Generates .agent/context/bottlenecks.txt
    │   ├── build-anchor-pack.sh               # Builds .agent/context/anchor_neighborhood.txt for a single symbol
    │   ├── slice.sh                           # Bounded 40-80 line file reader (sed/nl wrapper)
    │   ├── verify.sh                          # Single-target compiler/linter + Graph Indexer verifier (capped at 20 lines)
    │   └── check-duplicate-types.sh           # Blocks duplicate struct/interface/class/record/enum/type definitions
    ├── skills/
    │   ├── dead-code-pruner/
    │   │   └── SKILL.md                       # Skill instructions for surgical dead-code removal
    │   ├── perf-surgeon/
    │   │   └── SKILL.md                       # Skill instructions for 40-80 line hot-path & concurrency fixes
    │   └── prune-then-inject/
    │       └── SKILL.md                       # Skill instructions for 1-hop anchor feature injection
    └── prompts/
        ├── prune-dead.md                      # Slash command: /prune-dead
        ├── perf-fix.md                        # Slash command: /perf-fix
        ├── inject-feature.md                  # Slash command: /inject-feature
        └── safe-verify.md                     # Slash command: /safe-verify
~~~

---

## 2. Mandatory Operating Contract for the Coding Agent

You are operating inside a strict **12,000-token bounded context window** across a polyglot codebase (**Go, Bash, C#, JavaScript/TypeScript, Rust, Python, Swift**). Violating any rule below trips the automated circuit breaker and aborts your turn.

### 2.1 Ironclad Context & File-Reading Rules (Zero Full-File Reads)

- **NEVER read entire files.** Commands such as `cat`, `less`, `more`, unbounded `head`/`tail`, or reading more than 80 lines at once are strictly prohibited and blocked by the harness.
- **ALWAYS read bounded slices (40–80 lines maximum)** using `./.agent/scripts/slice.sh <file_path> <start_line> <end_line>` or `npx graph-indexer read <symbol> --max-lines 80`.
- **NEVER wander the codebase with broad grep or file searches.** Before touching any code, read the pre-computed files in `.agent/context/`:
  - `.agent/context/api_surface.txt` — All existing exported structs, interfaces, classes, records, enums, traits, protocols, and shared signatures.
  - `.agent/context/dead_code.txt` — Pre-computed unused symbols and structural bloat.
  - `.agent/context/bottlenecks.txt` — Pre-computed concurrency, memory allocation, shell, and UI hot-path bottlenecks with exact file and line numbers.
  - `.agent/context/anchor_neighborhood.txt` — Pre-built 1-hop neighborhood for the active anchor symbol.

### 2.2 Symbol-Level Navigation & Editing (Graph Indexer + Serena MCP / LSP)

- Use `graph-indexer` (`call_graph`, `find_references`, `change_impact`, `check_changes`, `outline`) to inspect 1-hop callers and callees before modifying any symbol.
- Use `serena` MCP symbol tools (`get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol`, `safe_delete_symbol`) for surgical AST-aware edits instead of rewriting entire files.
- **NEVER invent duplicate types.** Always check `.agent/context/api_surface.txt` before creating any `struct`, `interface`, `class`, `record`, `enum`, `trait`, `protocol`, or `type`. Reuse existing domain models.

### 2.3 Verification & 2-Strike Circuit Breaker

- **NEVER run raw workspace-wide build or test commands** (`go build ./...`, `go test ./...`, `dotnet build`, `dotnet test`, `npm test`, `tsc`, `cargo build`, `pytest`) directly in bash. Raw compiler output overflows context.
- **ALWAYS verify edits using `./.agent/scripts/verify.sh <file_path> [symbol_name]`**, which runs `graph-indexer check`, `graph-indexer impact --diff`, and single-target compiler/linter checks capped at 20 lines.
- **2-Strike Stop Rule:** If `./.agent/scripts/verify.sh` fails twice consecutively on the same edit:
  1. Immediately revert the broken file with `git checkout -- <file_path>`.
  2. Output a concise 5-line root-cause summary (exact compiler/linter error + conflicting caller/type signature) and **STOP**. Never attempt a 3rd blind retry.

---

## 3. Code Accuracy & Maintainability Standards by Language

Every line of code generated or modified by the agent must satisfy these universal architectural invariants and language-specific engineering rules.

### 3.1 Universal Maintainability Invariants

- **Guard Clauses & Flat Control Flow:** Use early returns/guard clauses to handle preconditions and errors at the top of functions. Maximum indentation depth is 3 levels.
- **Single-Responsibility Functions:** Functions must not exceed 50 lines. Extract pure helper functions when cyclomatic complexity exceeds 10.
- **Explicit Dependency Injection:** Pass dependencies explicitly via constructors, struct fields, or function parameters. Never introduce hidden global state or service locators.
- **Deterministic Resource Lifecycle:** Every acquired file descriptor, network socket, database transaction, subprocess, lock, or cancellation context must have a deterministic release path in the same lexical scope (`defer`, `using`, `try/finally`, `trap`, RAII).
- **Backward-Compatible Signatures:** Do not alter exported function signatures, public struct fields, or wire serialization tags (`json`, `yaml`, `protobuf`, `[JsonPropertyName]`) unless explicitly instructed and all 1-hop callers are updated in the same turn.

### 3.2 Go (Golang) Standards

- **Context Propagation:** `ctx context.Context` must be the first parameter of every function performing I/O, RPC, database queries, or blocking operations. Never store `context.Context` inside a `struct`. Always call the `cancel()` function returned by `context.WithTimeout` / `context.WithCancel` via `defer cancel()`.
- **Error Handling & Wrapping:** Never ignore returned errors (`_ = fn()`). Check errors immediately, wrap with actionable call-site context using `fmt.Errorf("doing x for %s: %w", id, err)`, and inspect error chains exclusively via `errors.Is` and `errors.As`. Never log and return the same error.
- **Concurrency & Goroutine Safety:** Never spawn an untracked `go func()` without a deterministic termination signal (`ctx.Done()`, `errgroup.Group`, or `sync.WaitGroup`) and bounded concurrency. Protect shared map/slice mutations with `sync.Mutex`/`sync.RWMutex` or channel ownership. Never copy `sync.Mutex`, `sync.WaitGroup`, or `sync.Cond` by value (`go vet -copylocks`).
- **Interface & Receiver Design:** Define small consumer-side interfaces ("accept interfaces, return concrete structs"). Do not mix value and pointer receivers on the same type. Make zero values useful where practical.
- **Memory & Allocation Discipline:** Pre-allocate slices and maps when capacity is known (`make([]T, 0, len(input))`, `make(map[K]V, len(input))`). Avoid `init()` functions and package-level mutable variables.
- **Testing:** Write table-driven tests using `t.Run`, mark independent unit tests with `t.Parallel()`, and verify race-freedom (`go test -race`).

### 3.3 Bash / Shell Scripting Standards

- **Strict Execution Header:** Every executable Bash script must start with:
  ~~~bash
  #!/usr/bin/env bash
  set -euo pipefail
  IFS=$'\n\t'
  ~~~
- **Quoting & Parameter Expansion:** Double-quote all variable and command expansions (`"${var}"`, `"$(cmd)"`) to prevent globbing and word splitting. Use `${var:-}` when reading potentially unset optional variables under `set -u`.
- **Arrays Over Word Splitting:** Build dynamic command arguments using indexed arrays (`cmd_args=("--flag" "${val}"); "${cmd_args[@]}"`). Never build commands in flat strings or invoke `eval`.
- **Scoping & Functions:** Declare all function-internal variables with `local`. Prefer `[[ ... ]]` over `[ ... ]` or `test`, and `(( ... ))` for integer arithmetic.
- **Safe Temporary Files & Cleanup Traps:** Create temporary artifacts exclusively via `mktemp` / `mktemp -d` and register a deterministic cleanup handler prior to populating them:
  ~~~bash
  cleanup() { rm -rf "${tmp_dir:-}"; }
  trap cleanup EXIT INT TERM
  ~~~
- **Process & Pipeline Safety:** Check command existence with `command -v <tool> >/dev/null 2>&1` (never `which`). Use `find ... -print0 | xargs -0` or `while IFS= read -r -d '' file; do ... done < <(find ... -print0)` to handle filenames with whitespace safely. Zero `shellcheck` warnings (`SC2086`, `SC2155`, `SC2034`) are permitted.

### 3.4 C# / .NET Standards

- **Nullable & Modern Language Invariants:** Assume `<Nullable>enable</Nullable>` and `<ImplicitUsings>enable</ImplicitUsings>`. Handle nullability explicitly via pattern matching (`is null`, `is not null`, `is { Property: var p }`). Never suppress null warnings with the null-forgiving operator (`!`) outside proven test assertions.
- **Async/Await & Cancellation Discipline:** Suffix async methods with `Async` and accept `CancellationToken cancellationToken = default` as the final parameter, forwarding it to all downstream async calls. Never block synchronously on tasks (`.Result`, `.Wait()`, `.GetAwaiter().GetResult()`)—always `await`. Never declare `async void` methods; use `async Task` or `async ValueTask<T>`. Use `.ConfigureAwait(false)` in non-UI library assemblies.
- **Resource & Lifetime Management:** Prefer C# `using var` / `await using var` declarations for all `IDisposable` and `IAsyncDisposable` instances. Never instantiate `new HttpClient()` directly in request paths; inject `HttpClient` via `IHttpClientFactory` or reuse a singleton `SocketsHttpHandler`.
- **Allocation & Hot-Path Performance:** Prefer `record` / `readonly record struct` for immutable DTOs and value objects. On high-throughput parsing or buffer paths, use `Span<T>`, `ReadOnlySpan<T>`, `Memory<T>`, and `ArrayPool<T>.Shared` to avoid Gen0 heap allocations and LOH fragmentation. Avoid LINQ closures in per-frame or tight loops.
- **EF Core & Data Access:** Append `.AsNoTracking()` on read-only queries, project early with `.Select(...)`, and avoid $N+1$ lazy-loading queries.

### 3.5 JavaScript / TypeScript Standards

- **Strict Type Safety:** Ban `any`, `@ts-ignore`, and non-null assertions (`!`) in TypeScript; use `unknown` with type predicates or schema validators (Zod/Valibot) at I/O boundaries. In JavaScript, include JSDoc `@param` and `@returns` annotations on exported functions and enforce `"use strict"` / ES module semantics.
- **Async & Promise Hygiene:** Never leave floating promises unhandled (`@typescript-eslint/no-floating-promises`). Propagate `AbortSignal` (`{ signal }`) into `fetch`, timers, and streams. Use `Promise.all` / `Promise.allSettled` for independent concurrent I/O instead of sequential `await` in loops.
- **Immutability & Equality:** Default to `const`; never use `var`. Enforce strict equality (`===`, `!==`) and optional chaining / nullish coalescing (`?.`, `??`) over truthy/falsy coercions that fail on `0` or `""`. Never mutate function input arguments or React props/state in place.
- **Event Loop & UI Hot Paths:** Never call synchronous `fs.*Sync` or `child_process.*Sync` inside request handlers or async workflows. In React/frontend code, hoist static objects outside components, ensure complete `useEffect` dependency arrays without state-setter loops, and clean up listeners/timers on unmount.

### 3.6 Rust, Python & Swift Standards

- **Rust:** Ban `.unwrap()` and `.expect()` in production library/service paths; propagate errors with `?` and typed `thiserror` enums. Prefer borrowed slices (`&[T]`, `&str`, `Cow<'_, str>`) over `.clone()` on hot paths. Never hold a synchronous `std::sync::MutexGuard` across an `.await` point.
- **Python:** Require full type annotations on all function signatures (`mypy`/`pyright` strict). Never use mutable default arguments (`def fn(x: list[str] | None = None)`). Never call blocking I/O (`time.sleep`, `requests.*`, `subprocess.run`) inside `async def` coroutines—use `asyncio.sleep`, `httpx.AsyncClient`, or `asyncio.to_thread`.
- **Swift:** Enforce Swift 6 strict concurrency (`Sendable`, `@MainActor`, `actor` isolation). Never perform synchronous disk/network I/O (`Data(contentsOf:)`) or `DispatchQueue.main.sync` on the main actor. Keep SwiftUI `var body: some View` blocks under 45 lines by extracting `Equatable` subviews.

---

## 4. Workstation & Repository Bootstrap

Run the workstation installer once to install the polyglot CLI stack, then run `.agent/scripts/bootstrap-repo.sh` inside any cloned repository.

### Step 4.1: Install Global CLI Tooling

~~~bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Core search, AST analysis, Bash static analysis, and Git hook manager
brew install \
  ripgrep \
  fd \
  ast-grep \
  lefthook \
  shellcheck \
  shfmt \
  golangci-lint \
  periphery \
  swiftlint \
  ruff \
  uv \
  jq \
  coreutils

# 2. Go static analysis & LSP tooling
go install golang.org/x/tools/gopls@latest
go install golang.org/x/tools/cmd/deadcode@latest
go install honnef.co/go/tools/cmd/staticcheck@latest

# 3. .NET SDK analyzers & formatter (requires dotnet SDK installed)
dotnet tool install -g csharp-ls || true

# 4. Node/JS/TypeScript static analysis, Repomix, and Graph Indexer
npm install -g \
  repomix \
  knip \
  typescript \
  eslint \
  @biomejs/biome \
  graph-indexer

# 5. Rust toolchain components
rustup component add clippy rust-analyzer || true

# 6. Serena MCP Server (LSP semantic retrieval & symbol-level editing)
uv tool install serena-agent
~~~

### Step 4.2: Project-Level Agent Configuration (`.agent/settings.json`)

Create `.agent/settings.json` in the repository root to bind `graph-indexer` and `serena` MCP and enforce compact context management:

~~~json
{
  "context": {
    "maxTokens": 12288,
    "autoCompactThreshold": 9500,
    "alwaysLoad": [
      "AGENTS.md"
    ]
  },
  "mcpServers": {
    "graph-indexer": {
      "command": "npx",
      "args": ["-y", "graph-indexer", "serve"]
    },
    "serena": {
      "command": "uvx",
      "args": [
        "--from",
        "serena-agent",
        "serena-mcp-server",
        "--project",
        "."
      ]
    }
  },
  "permissions": {
    "allow": [
      "bash(.agent/scripts/*)",
      "bash(npx graph-indexer *)",
      "mcp(graph-indexer:*)",
      "mcp(serena:*)"
    ],
    "deny": [
      "bash(git commit --no-verify*)",
      "bash(git push --force*)"
    ]
  }
}
~~~

### Step 4.3: One-Command Repository Bootstrap Script (`.agent/scripts/bootstrap-repo.sh`)

Save this script to `.agent/scripts/bootstrap-repo.sh` and run `chmod +x .agent/scripts/*.sh`:

~~~bash
#!/usr/bin/env bash
# .agent/scripts/bootstrap-repo.sh
# Initializes Graph Indexer, Lefthook pre-commit gates, and pre-computed .agent/context/ indexes.
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

mkdir -p .agent/context .agent/scripts .agent/skills .agent/prompts .agent/extensions .ast-grep/rules

# Ensure .agent/context/ is ignored by git so local index artifacts never pollute commits
if ! grep -q "^.agent/context/" .gitignore 2>/dev/null; then
  echo ".agent/context/" >> .gitignore
fi

echo "[1/4] Initializing local SQLite code graph via graph-indexer..."
npx graph-indexer init
npx graph-indexer index

echo "[2/4] Installing Lefthook pre-commit verification gates..."
lefthook install

echo "[3/4] Generating zero-token static analysis context (.agent/context/*.txt)..."
chmod +x .agent/scripts/*.sh
./.agent/scripts/refresh-all-context.sh

echo "[4/4] Bootstrap complete. Repository is ready for bounded-context agent operations."
~~~

---

## 5. Goal 1: Zero-Destruction Codebase Safety & Pre-Commit Gates

To guarantee an agent never corrupts shared branches, invents duplicate types, or breaks downstream callers, every edit must pass three layers of deterministic verification:

1. **In-Turn Agent Verification (`.agent/scripts/verify.sh`)**
2. **Duplicate Type Guard (`.agent/scripts/check-duplicate-types.sh`)**
3. **Git Pre-Commit Gate (`lefthook.yml`)**

### Step 5.1: Single-Target Bounded Verifier (`.agent/scripts/verify.sh`)

Validates uncommitted changes using `graph-indexer` (`check` and `impact --diff`), duplicate type checks, and the language compiler/linter for the modified target only, truncating output to **at most 20 lines**:

~~~bash
#!/usr/bin/env bash
# .agent/scripts/verify.sh
# Usage: ./.agent/scripts/verify.sh <target_file> [symbol_name]
set -uo pipefail
IFS=$'\n\t'

TARGET_FILE="${1:-}"
SYMBOL_NAME="${2:-}"

if [[ -z "${TARGET_FILE}" || ! -f "${TARGET_FILE}" ]]; then
  echo "ERROR: Provide a valid target file path. Usage: ./.agent/scripts/verify.sh <file> [symbol]"
  exit 2
fi

echo "=== [1/4] Graph Indexer Broken Call-Site & Signature Check ==="
GRAPH_CHECK_OUT="$(npx graph-indexer check --files "${TARGET_FILE}" 2>&1)"
echo "${GRAPH_CHECK_OUT}" | head -n 12
if echo "${GRAPH_CHECK_OUT}" | grep -qiE "Problems:|argument|removed|untouched caller"; then
  echo "FAIL: Graph Indexer detected broken call sites or signature mismatches."
  exit 1
fi

if [[ -n "${SYMBOL_NAME}" ]]; then
  echo "=== [2/4] 1-Hop Blast Radius Check (${SYMBOL_NAME}) ==="
  npx graph-indexer impact --symbols "${SYMBOL_NAME}" --depth 1 2>&1 | head -n 10
else
  echo "=== [2/4] Diff Blast Radius Check ==="
  npx graph-indexer impact --diff --depth 1 2>&1 | head -n 10
fi

echo "=== [3/4] Duplicate Type & Struct Guard ==="
if ! ./.agent/scripts/check-duplicate-types.sh "${TARGET_FILE}"; then
  exit 1
fi

echo "=== [4/4] Single-Target Compiler & Linter Gate ==="
EXT="${TARGET_FILE##*.}"
TARGET_DIR="$(dirname "${TARGET_FILE}")"
COMPILE_OUT=""
STATUS=0

case "${EXT}" in
  go)
    # Verify only the modified Go package
    PKG_PATH="./${TARGET_DIR}"
    COMPILE_OUT="$(timeout 30s bash -c "go vet '${PKG_PATH}' && golangci-lint run --fast '${PKG_PATH}'" 2>&1)" || STATUS=$?
    ;;
  sh|bash)
    COMPILE_OUT="$(timeout 15s bash -c "bash -n '${TARGET_FILE}' && shellcheck -x '${TARGET_FILE}' && shfmt -d '${TARGET_FILE}'" 2>&1)" || STATUS=$?
    ;;
  cs)
    # Locate nearest .csproj for single-project verification
    CSPROJ="$( (cd "${TARGET_DIR}" && while [[ "${PWD}" != "/" ]]; do ls ./*.csproj 2>/dev/null | head -n 1 && break; cd ..; done) )"
    if [[ -n "${CSPROJ}" ]]; then
      COMPILE_OUT="$(timeout 45s dotnet build "${CSPROJ}" --no-restore -warnaserror -v quiet -nologo 2>&1)" || STATUS=$?
    else
      COMPILE_OUT="$(timeout 45s dotnet build --no-restore -warnaserror -v quiet -nologo 2>&1)" || STATUS=$?
    fi
    ;;
  js|mjs|cjs)
    if command -v biome >/dev/null 2>&1 && [[ -f "biome.json" ]]; then
      COMPILE_OUT="$(timeout 20s npx biome check "${TARGET_FILE}" 2>&1)" || STATUS=$?
    else
      COMPILE_OUT="$(timeout 20s bash -c "node --check '${TARGET_FILE}' && npx eslint --max-warnings=0 '${TARGET_FILE}'" 2>&1)" || STATUS=$?
    fi
    ;;
  ts|tsx)
    COMPILE_OUT="$(timeout 25s bash -c "npx tsc --noEmit --pretty false && npx eslint --max-warnings=0 '${TARGET_FILE}'" 2>&1)" || STATUS=$?
    ;;
  rs)
    PKG_TOML="$(upsearch() { test / == "${PWD}" && return || test -e "Cargo.toml" && echo "${PWD}/Cargo.toml" && return || cd .. && upsearch; }; (cd "${TARGET_DIR}" && upsearch))"
    if [[ -n "${PKG_TOML}" ]]; then
      PKG_NAME="$(grep -m1 '^name[[:space:]]*=' "${PKG_TOML}" | sed -E 's/.*"([^"]+)".*/\1/')"
      COMPILE_OUT="$(timeout 30s cargo check -p "${PKG_NAME}" --message-format=short 2>&1)" || STATUS=$?
    else
      COMPILE_OUT="$(timeout 30s cargo check --message-format=short 2>&1)" || STATUS=$?
    fi
    ;;
  swift)
    COMPILE_OUT="$(timeout 30s swiftlint lint --path "${TARGET_FILE}" --quiet 2>&1 && timeout 45s swift build -Xswiftc -suppress-warnings 2>&1)" || STATUS=$?
    ;;
  py)
    COMPILE_OUT="$(timeout 15s ruff check "${TARGET_FILE}" --output-format=concise 2>&1)" || STATUS=$?
    ;;
  *)
    echo "No language compiler gate configured for .${EXT}"
    ;;
esac

if [[ "${STATUS}" -ne 0 ]]; then
  echo "COMPILER/LINTER GATE FAILED (Showing first 20 actionable lines):"
  echo "${COMPILE_OUT}" | grep -iE "(error|warning|fail|SC[0-9]{4}|CS[0-9]{4}|IDE[0-9]{4}|:[0-9]+:[0-9]+:)" | head -n 20 | cut -c 1-220
  exit 1
fi

echo "PASS: Zero broken callers, zero duplicate types, target verified cleanly."
exit 0
~~~

### Step 5.2: Duplicate Type & Struct Guard (`.agent/scripts/check-duplicate-types.sh`)

Prevents the agent from inventing a duplicate `UserConfig`, `AuthToken`, or `OrderService` across Go, C#, JS/TS, Rust, Swift, and Python when one already exists in `.agent/context/api_surface.txt`:

~~~bash
#!/usr/bin/env bash
# .agent/scripts/check-duplicate-types.sh
# Blocks newly introduced struct/interface/class/record/enum/trait/protocol/type definitions that collide with existing repository symbols.
set -euo pipefail
IFS=$'\n\t'

TARGET_FILE="${1:-}"
API_SURFACE=".agent/context/api_surface.txt"

if [[ ! -f "${API_SURFACE}" ]]; then
  ./.agent/scripts/index-api-surface.sh >/dev/null 2>&1 || true
fi

DIFF_CMD=(git diff HEAD --)
[[ -n "${TARGET_FILE}" ]] && DIFF_CMD+=("${TARGET_FILE}")

# Extract newly added type declarations across Go, C#, JS/TS, Rust, Swift, Python
NEW_TYPES="$("${DIFF_CMD[@]}" \
  | grep -E '^\+[^+]' \
  | sed -E 's/^\+//' \
  | sed -nE \
      -e 's/.*\btype[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+(struct|interface)\b.*/\1/p' \
      -e 's/.*\b(public|internal|private|protected|export|pub|sealed|abstract|partial|readonly)?[[:space:]]*(struct|enum|trait|protocol|interface|record|class)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\3/p' \
  | sort -u || true)"

if [[ -z "${NEW_TYPES}" ]]; then
  exit 0
fi

COLLISIONS=0
for TYPE_NAME in ${NEW_TYPES}; do
  DEF_COUNT="$(npx graph-indexer search "${TYPE_NAME}" --limit 10 2>/dev/null \
    | grep -E "\b${TYPE_NAME}\b.*(struct|enum|interface|class|record|type|trait|protocol)" \
    | wc -l | tr -d ' ')"
  if (( DEF_COUNT > 1 )); then
    echo "DUPLICATE TYPE BLOCKED: '${TYPE_NAME}' is defined in multiple files:"
    npx graph-indexer search "${TYPE_NAME}" --limit 5 | head -n 6
    echo "Action Required: Reuse the existing '${TYPE_NAME}' from .agent/context/api_surface.txt instead of creating a duplicate."
    COLLISIONS=1
  fi
done

exit "${COLLISIONS}"
~~~

### Step 5.3: Automated Git Pre-Commit Gate (`lefthook.yml`)

Place `lefthook.yml` in the repository root. Lefthook executes these checks in parallel before any commit is recorded and rejects broken or non-compliant edits automatically:

~~~yaml
# lefthook.yml — Zero-Destruction Polyglot Pre-Commit Gate
pre-commit:
  parallel: true
  commands:
    graph-impact-gate:
      run: |
        npx graph-indexer index >/dev/null 2>&1
        OUT="$(npx graph-indexer check)"
        echo "$OUT"
        if echo "$OUT" | grep -qiE "Problems:|argument|removed|untouched caller"; then
          echo "COMMIT REJECTED: Graph Indexer detected broken downstream callers or signature mismatches."
          exit 1
        fi

    duplicate-types-gate:
      run: ./.agent/scripts/check-duplicate-types.sh

    go-compiler-gate:
      glob: "*.go"
      run: |
        gofmt -l {staged_files} | grep . && { echo "Run gofmt on staged files"; exit 1; } || true
        go vet ./...
        golangci-lint run --new-from-rev=HEAD

    bash-linter-gate:
      glob: "*.{sh,bash}"
      run: |
        shellcheck -x {staged_files}
        shfmt -d {staged_files}

    csharp-compiler-gate:
      glob: "*.cs"
      run: |
        dotnet format --verify-no-changes --include {staged_files}
        dotnet build --no-restore -warnaserror -v quiet -nologo

    js-ts-compiler-gate:
      glob: "*.{js,mjs,cjs,ts,tsx}"
      run: |
        if [ -f tsconfig.json ]; then npx tsc --noEmit --pretty false; fi
        npx eslint --max-warnings=0 {staged_files}
        if [ -f package.json ]; then npx knip --no-progress --reporter compact; fi

    rust-compiler-gate:
      glob: "*.rs"
      run: |
        cargo check --workspace --message-format=short
        cargo clippy --workspace --message-format=short -- -D warnings

    swift-compiler-gate:
      glob: "*.swift"
      run: |
        swiftlint lint --quiet --strict {staged_files}
        swift build

    python-linter-gate:
      glob: "*.py"
      run: |
        ruff check {staged_files} --output-format=concise

post-commit:
  commands:
    refresh-agent-context:
      run: ./.agent/scripts/refresh-all-context.sh >/dev/null 2>&1 &
~~~

### Step 5.4: `/safe-verify` Slash Command (`.agent/prompts/safe-verify.md`)

~~~markdown
---
description: Run bounded single-target compiler, linter, LSP, duplicate-type, and 1-hop call-graph verification on uncommitted changes
---
Run `./.agent/scripts/verify.sh $ARGUMENTS` to verify the active target file and symbol.
- If verification passes, report the 1-hop impact summary in 3 bullet points.
- If verification fails, inspect ONLY the reported line numbers using `./.agent/scripts/slice.sh`, apply a surgical fix via Serena `replace_symbol_body` or `replace_content`, and re-run `./.agent/scripts/verify.sh` once.
- Respect the 2-Strike Circuit Breaker: if the second verification fails, run `git checkout -- <file>` and report the exact blocker.
~~~

---

## 6. Goal 2: Eliminating Agent Loops & Context Overflow

To prevent the coding agent from exceeding the 12k–16k token boundary or spinning in an infinite retry loop, combine **bounded shell wrappers** with an **Agent Harness Circuit Breaker Extension**.

### Step 6.1: Bounded 40–80 Line File Reader (`.agent/scripts/slice.sh`)

~~~bash
#!/usr/bin/env bash
# .agent/scripts/slice.sh
# Usage: ./.agent/scripts/slice.sh <file_path> <start_line> <end_line>
# Enforces a hard maximum window of 80 lines per read to prevent context bloat.
set -euo pipefail
IFS=$'\n\t'

FILE="${1:-}"
START="${2:-1}"
END="${3:-60}"

if [[ -z "${FILE}" || ! -f "${FILE}" ]]; then
  echo "ERROR: File '${FILE}' does not exist."
  exit 1
fi

MAX_WINDOW=80
SPAN=$(( END - START + 1 ))
if (( SPAN > MAX_WINDOW )); then
  END=$(( START + MAX_WINDOW - 1 ))
  echo "[BOUNDED CONTEXT GUARD] Requested ${SPAN} lines; clamped to ${MAX_WINDOW} lines (${START}..${END})."
fi

if (( START < 1 )); then START=1; fi

echo "=== ${FILE} (Lines ${START}..${END}) ==="
nl -ba -w4 -s': ' "${FILE}" | sed -n "${START},${END}p" | cut -c 1-220
~~~

### Step 6.2: Agent Harness Circuit Breaker (`.agent/extensions/context-circuit-breaker.ts`)

Intercepts harness tool calls and turn events to enforce:
- Hard blocking of full-file reads (`cat`, unbounded `head`/`tail`, or `read_file` exceeding 80 lines)
- Hard blocking of raw, uncapped compiler/test runs (`go test`, `go build`, `dotnet build`, `dotnet test`, `npm test`, `npx tsc`, `cargo build`, `cargo test`, `swift build`, `pytest` outside `verify.sh`)
- Automatic context compaction at 9,500 tokens and hard ceiling at 12,288 tokens
- A 2-strike consecutive verification failure breaker that automatically halts execution

~~~typescript
// .agent/extensions/context-circuit-breaker.ts
export interface ToolCallEvent {
  toolName: string;
  args?: Record<string, unknown>;
  result?: { output?: string; exitCode?: number };
}

export interface TurnEvent {
  usage?: { totalTokens?: number };
}

export interface ExtensionAPI {
  on(event: "beforeToolCall", handler: (e: ToolCallEvent) => Promise<{ block: boolean; message: string } | void>): void;
  on(event: "afterToolCall", handler: (e: ToolCallEvent) => Promise<void>): void;
  on(event: "afterTurn", handler: (e: TurnEvent) => Promise<void>): void;
  abortTurn(reason: string): Promise<void>;
  compactContext(options: { preserveFiles: string[]; summaryMaxTokens: number }): Promise<void>;
}

const MAX_CONTEXT_TOKENS = 12_288;
const COMPACT_THRESHOLD_TOKENS = 9_500;
const MAX_CONSECUTIVE_FAILURES = 2;

const BANNED_RAW_COMMANDS = [
  /\bcat\s+[^|]+$/,
  /\b(go\s+(build|test|vet)|golangci-lint\s+run|dotnet\s+(build|test)|npm\s+test|npx\s+tsc|cargo\s+(build|test|clippy)|swift\s+(build|test)|pytest)\b(?!.*verify\.sh)/,
  /\bgrep\s+-r\b/,
];

export default function registerContextCircuitBreaker(agent: ExtensionAPI) {
  let consecutiveVerifyFailures = 0;
  let lastFailedTarget = "";

  // 1. Pre-Tool Call Guard: Block full-file reads and raw compiler dumps
  agent.on("beforeToolCall", async (event: ToolCallEvent) => {
    if (event.toolName === "bash") {
      const cmd = String(event.args?.command ?? "").trim();

      for (const pattern of BANNED_RAW_COMMANDS) {
        if (pattern.test(cmd) && !cmd.includes(".agent/scripts/")) {
          return {
            block: true,
            message:
              "BLOCKED BY BOUNDED-CONTEXT GUARD: Never run raw cat/grep or uncapped compiler/test commands. " +
              "Use `./.agent/scripts/slice.sh <file> <start> <end>` (max 80 lines) or `./.agent/scripts/verify.sh <file> [symbol]`.",
          };
        }
      }
    }

    if (event.toolName === "read_file" || event.toolName === "fs_read_file") {
      const start = Number(event.args?.startLine ?? 1);
      const end = Number(event.args?.endLine ?? 9999);
      if (end - start > 80) {
        return {
          block: true,
          message:
            `BLOCKED BY BOUNDED-CONTEXT GUARD: Requested ${end - start} lines. ` +
            "Maximum allowed slice is 80 lines. Use `./.agent/scripts/slice.sh <file> <start> <end>` or Serena `get_symbols_overview`.",
        };
      }
    }
  });

  // 2. Post-Tool Call Guard: Track verify.sh failures and trip 2-strike circuit breaker
  agent.on("afterToolCall", async (event: ToolCallEvent) => {
    if (event.toolName === "bash") {
      const cmd = String(event.args?.command ?? "");
      if (cmd.includes("verify.sh")) {
        const output = String(event.result?.output ?? "");
        const exitCode = Number(event.result?.exitCode ?? 0);

        if (exitCode !== 0 || output.includes("COMPILER/LINTER GATE FAILED") || output.includes("FAIL:")) {
          consecutiveVerifyFailures += 1;
          lastFailedTarget = cmd;

          if (consecutiveVerifyFailures >= MAX_CONSECUTIVE_FAILURES) {
            consecutiveVerifyFailures = 0;
            await agent.abortTurn(
              `CIRCUIT BREAKER TRIPPED (2 Consecutive Verification Failures on '${lastFailedTarget}'). ` +
              "Execution halted to prevent context corruption and retry loops. " +
              "Revert the uncommitted edit (`git checkout -- <file>`) and review the compiler diagnostic with the engineer."
            );
          }
        } else {
          consecutiveVerifyFailures = 0;
        }
      }
    }
  });

  // 3. Turn Token Ceiling Guard: Compact at 9.5k tokens, hard compact at 12.2k tokens
  agent.on("afterTurn", async (turn: TurnEvent) => {
    const usedTokens = turn.usage?.totalTokens ?? 0;
    if (usedTokens >= MAX_CONTEXT_TOKENS) {
      await agent.compactContext({
        preserveFiles: ["AGENTS.md"],
        summaryMaxTokens: 1200,
      });
    } else if (usedTokens >= COMPACT_THRESHOLD_TOKENS) {
      await agent.compactContext({
        preserveFiles: ["AGENTS.md"],
        summaryMaxTokens: 1500,
      });
    }
  });
}
~~~

---

## 7. Goal 3: Structural Verification & Dead-Code Pruning (`.agent/context/dead_code.txt`)

Instead of asking the LLM to scan the repository for unused code, `.agent/scripts/index-dead-code.sh` runs deterministic static analyzers across **Go, Bash, C#, JS/TS, Rust, Swift, and Python** at **zero token cost** and writes a compact, line-numbered hit-list to `.agent/context/dead_code.txt`.

### Step 7.1: Zero-Token Dead-Code Indexer (`.agent/scripts/index-dead-code.sh`)

~~~bash
#!/usr/bin/env bash
# .agent/scripts/index-dead-code.sh
# Pre-computes unused code, redundant exports, and dead symbols into .agent/context/dead_code.txt
set -uo pipefail
IFS=$'\n\t'

OUT_FILE=".agent/context/dead_code.txt"
mkdir -p .agent/context
: > "${OUT_FILE}"

echo "# PRE-COMPUTED DEAD CODE HIT-LIST (Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ"))" >> "${OUT_FILE}"
echo "# Format: [LANG] file:line | symbol/rule | diagnostic" >> "${OUT_FILE}"
echo "" >> "${OUT_FILE}"

# 1. Go: golangci-lint (unused, ineffassign) + golang.org/x/tools/cmd/deadcode
if [[ -f "go.mod" ]] || fd -q "^go\.mod$" --max-depth 3; then
  echo "## [GO] Unused Functions, Types & Unreachable Call-Graph Symbols" >> "${OUT_FILE}"
  if command -v deadcode >/dev/null 2>&1; then
    deadcode -test ./... 2>/dev/null \
      | sed -E 's/^/[GO:deadcode] /' >> "${OUT_FILE}" || true
  fi
  if command -v golangci-lint >/dev/null 2>&1; then
    golangci-lint run --disable-all -E unused -E ineffassign --out-format=line-number ./... 2>/dev/null \
      | sed -E 's/^/[GO:golangci] /' >> "${OUT_FILE}" || true
  fi
  echo "" >> "${OUT_FILE}"
fi

# 2. Bash: shellcheck SC2034 (unused variables) & unreachable code
if fd -q "\.(sh|bash)$" --max-depth 3; then
  echo "## [BASH] ShellCheck Unused Variables (SC2034) & Unreachable Commands (SC2317)" >> "${OUT_FILE}"
  if command -v shellcheck >/dev/null 2>&1; then
    fd -e sh -e bash --max-depth 4 -X shellcheck -f gcc --include=SC2034,SC2317 2>/dev/null \
      | sed -E 's/^/[BASH:shellcheck] /' >> "${OUT_FILE}" || true
  fi
  echo "" >> "${OUT_FILE}"
fi

# 3. C# / .NET: Roslyn Unused Private Members (IDE0051, IDE0052, CS0168, CS0219, CS0414, CS0649)
if fd -q "\.(sln|csproj)$" --max-depth 3; then
  echo "## [CSHARP] Roslyn Unused Members, Locals & Fields" >> "${OUT_FILE}"
  if command -v dotnet >/dev/null 2>&1; then
    dotnet build --no-restore -v quiet -nologo 2>/dev/null \
      | grep -E "(IDE0051|IDE0052|IDE0059|CS0168|CS0219|CS0414|CS0649)" \
      | sed -E 's/^[[:space:]]*//[CSHARP:roslyn] /' >> "${OUT_FILE}" || true
  fi
  echo "" >> "${OUT_FILE}"
fi

# 4. JavaScript / TypeScript: Knip unused files, exports, types + tsc unused locals
if [[ -f "package.json" ]] || [[ -f "tsconfig.json" ]]; then
  echo "## [JS/TS] Knip Unused Exports, Types & Files" >> "${OUT_FILE}"
  npx knip --no-progress --reporter compact 2>/dev/null \
    | sed -E 's/^/[JSTS:knip] /' >> "${OUT_FILE}" || true
  if [[ -f "tsconfig.json" ]]; then
    npx tsc --noEmit --pretty false --noUnusedLocals --noUnusedParameters 2>/dev/null \
      | grep -E "TS(6133|6192|6196):" \
      | sed -E 's/^/[JSTS:tsc] /' >> "${OUT_FILE}" || true
  fi
  echo "" >> "${OUT_FILE}"
fi

# 5. Rust: cargo clippy dead_code, unused_imports, unused_variables
if [[ -f "Cargo.toml" ]] || fd -q "^Cargo\.toml$" --max-depth 3; then
  echo "## [RUST] Clippy & rustc Dead Code Diagnostics" >> "${OUT_FILE}"
  cargo clippy --workspace --all-targets --message-format=short \
    -- -W dead_code -W unused_imports -W unused_variables -W unused_mut 2>&1 \
    | grep -E "warning:.*(never (used|constructed|read)|unused)" \
    | sed -E 's/^/[RUST] /' >> "${OUT_FILE}" || true
  echo "" >> "${OUT_FILE}"
fi

# 6. Swift: Periphery + SwiftLint unused declarations & imports
if [[ -f "Package.swift" ]] || fd -q "\.(xcodeproj|xcworkspace)$" --max-depth 2; then
  echo "## [SWIFT] Periphery & SwiftLint Unused Declarations" >> "${OUT_FILE}"
  if command -v periphery >/dev/null 2>&1; then
    periphery scan --quiet 2>/dev/null \
      | sed -E 's/^/[SWIFT:periphery] /' >> "${OUT_FILE}" || true
  fi
  if command -v swiftlint >/dev/null 2>&1; then
    swiftlint lint --quiet 2>/dev/null \
      | grep -E "(unused_declaration|unused_import|unused_optional_binding|unused_closure_parameter)" \
      | sed -E 's/^/[SWIFT:swiftlint] /' >> "${OUT_FILE}" || true
  fi
  echo "" >> "${OUT_FILE}"
fi

# 7. Python: Ruff unused imports (F401), unused variables (F841), commented-out code (ERA001)
if fd -q "\.py$" --max-depth 3; then
  echo "## [PYTHON] Ruff Unused Symbols & Redundant Code" >> "${OUT_FILE}"
  ruff check . --output-format=concise --select F401,F841,ERA001,RUF100,PIE790 2>/dev/null \
    | sed -E 's/^/[PYTHON:ruff] /' >> "${OUT_FILE}" || true
  echo "" >> "${OUT_FILE}"
fi

TOTAL_HITS="$(grep -cE '^\[(GO|BASH|CSHARP|JSTS|RUST|SWIFT|PYTHON)' "${OUT_FILE}" || true)"
echo "# TOTAL DEAD-CODE CANDIDATES: ${TOTAL_HITS}" >> "${OUT_FILE}"
echo "Dead-code index written to ${OUT_FILE} (${TOTAL_HITS} candidates)."
~~~

### Step 7.2: Dead-Code Pruner Skill (`.agent/skills/dead-code-pruner/SKILL.md`)

~~~markdown
---
name: dead-code-pruner
description: Surgically verify and delete unused code from .agent/context/dead_code.txt using Graph Indexer call graphs and Serena safe_delete_symbol.
---
# Surgical Dead-Code Pruning Protocol

Never scan the repository manually for dead code. Follow this exact 4-step deterministic loop:

1. **Read the Hit-List Slice:**
   Run `./.agent/scripts/slice.sh .agent/context/dead_code.txt 1 60` (or filter by path with `grep "<path>" .agent/context/dead_code.txt | head -n 25`).
2. **Verify Zero External Callers (2-Source Proof):**
   For each candidate symbol `<symbol>` at `<file>:<line>`:
   - Run `npx graph-indexer refs <symbol> --include-tests`
   - Run `npx graph-indexer callgraph <symbol> --direction callers --depth 1`
   - If ANY external production caller, interface satisfaction contract, reflection binding, DI registration, or test reference exists (or if the symbol is marked with `//go:linkname`, `[UsedImplicitly]`, `#[no_mangle]`, `@objc`, or public SDK exports), **SKIP IT** immediately.
3. **Surgical Deletion:**
   - Inspect only the 30 lines around `<file>:<line>` via `./.agent/scripts/slice.sh <file> $((line-10)) $((line+20))`.
   - Prefer Serena MCP `safe_delete_symbol` (or `replace_content` for single unused imports/locals).
4. **Immediate Single-Target Verification:**
   - Run `./.agent/scripts/verify.sh <file> <symbol>` after each file batch.
   - If verification fails, immediately run `git checkout -- <file>`.
~~~

### Step 7.3: `/prune-dead` Slash Command (`.agent/prompts/prune-dead.md`)

~~~markdown
---
description: Prune verified dead code from .agent/context/dead_code.txt in a target directory or file
---
Load the `dead-code-pruner` skill and prune unused code for target scope: `$ARGUMENTS` (if empty, process the top 10 candidates in `.agent/context/dead_code.txt`).

Strict Execution Sequence:
1. Filter `.agent/context/dead_code.txt` for `$ARGUMENTS` (maximum 10 symbols per run).
2. For each candidate, run `npx graph-indexer refs <symbol>` and `npx graph-indexer callgraph <symbol> --direction callers --depth 1` to confirm 0 external callers.
3. Inspect at most 40 lines around the symbol using `./.agent/scripts/slice.sh`.
4. Delete the dead symbol using Serena `safe_delete_symbol` or `replace_content`.
5. Run `./.agent/scripts/verify.sh <file>` after each file modification.
6. Output a compact Markdown summary table of removed symbols, skipped symbols (with reason), and verification status.
~~~

---

## 8. Goal 4: Fix Concurrency, Runtime & UI Bottlenecks (`/perf-fix`)

Goroutine leaks, thread-pool starvation, shell subshell overhead, and UI frame drops across Go, Bash, C#, JS/TS, Rust, Swift, and Python follow deterministic structural anti-patterns. We pre-index all source files using `ast-grep (sg)` and structural checks into `.agent/context/bottlenecks.txt`, enabling a single `/perf-fix` workflow that inspects only the **40–80 lines** of the flagged function.

### Step 8.1: AST-Grep Multi-Language Bottleneck Rules (`.ast-grep/rules/bottlenecks.yml`)

Create `.ast-grep/sgconfig.yml`:

~~~yaml
# .ast-grep/sgconfig.yml
ruleDirs:
  - .ast-grep/rules
~~~

Create `.ast-grep/rules/bottlenecks.yml`:

~~~yaml
# .ast-grep/rules/bottlenecks.yml
id: go-defer-inside-loop
language: Go
severity: warning
message: "defer inside for/range loop delays resource release until function exit and risks FD/memory exhaustion"
rule:
  pattern: defer $$$
  inside:
    any:
      - kind: for_statement
      - kind: range_clause
    stopBy: function_declaration
---
id: go-http-default-client-no-timeout
language: Go
severity: error
message: "Unbounded http.Get/Post/DefaultClient call without context or timeout risks permanent goroutine leak"
rule:
  any:
    - pattern: http.Get($$$)
    - pattern: http.Post($$$)
    - pattern: http.DefaultClient.Do($$$)
---
id: csharp-sync-over-async-blocking
language: CSharp
severity: error
message: "Synchronous blocking (.Result / .Wait() / .GetAwaiter().GetResult()) causes .NET ThreadPool starvation and deadlocks"
rule:
  any:
    - pattern: $TASK.Result
    - pattern: $TASK.Wait($$$)
    - pattern: $TASK.GetAwaiter().GetResult()
---
id: csharp-transient-httpclient-socket-exhaustion
language: CSharp
severity: error
message: "Direct instantiation of new HttpClient() causes ephemeral port/socket exhaustion; inject IHttpClientFactory"
rule:
  pattern: new HttpClient($$$)
---
id: js-ts-sync-io-or-deep-clone-hotpath
language: TypeScript
severity: warning
message: "Event-loop blocking *Sync call or expensive JSON.parse(JSON.stringify(...)) deep clone"
rule:
  any:
    - pattern: JSON.parse(JSON.stringify($$$))
    - pattern: fs.readFileSync($$$)
    - pattern: fs.writeFileSync($$$)
    - pattern: child_process.execSync($$$)
---
id: react-unmemoized-effect-loop
language: Tsx
severity: warning
message: "Potential React re-render loop or unmemoized inline object/closure in JSX hot path"
rule:
  any:
    - pattern: useEffect(() => { $$$ set$STATE($$$); $$$ })
    - pattern: <$COMP $$$ style={{ $$$ }} $$$ />
---
id: rust-hotpath-clone-or-lock
language: Rust
severity: warning
message: "Hot-path per-frame .clone() or synchronous Mutex/RwLock acquisition inside render/update/tick function"
rule:
  any:
    - pattern: $EXPR.clone()
    - pattern: $LOCK.lock()
    - pattern: $LOCK.write()
  inside:
    kind: function_item
    stopBy: end
    regex: "fn\\s+(render|update|draw|tick|paint|layout|view)"
---
id: swiftui-mainthread-blocking-io
language: Swift
severity: error
message: "Main-thread blocking I/O or synchronous sleep inside SwiftUI View or @MainActor context"
rule:
  any:
    - pattern: Data(contentsOf: $$$)
    - pattern: String(contentsOf: $$$)
    - pattern: Thread.sleep($$$)
    - pattern: DispatchQueue.main.sync($$$)
---
id: python-async-blocking-io
language: Python
severity: error
message: "Synchronous blocking I/O inside async def coroutine (blocks event loop)"
rule:
  any:
    - pattern: time.sleep($$$)
    - pattern: requests.$METHOD($$$)
    - pattern: subprocess.run($$$)
  inside:
    kind: function_definition
    stopBy: end
    regex: "^async\\s+def\\s+"
~~~

### Step 8.2: Runtime & Concurrency Bottleneck Pre-Indexer (`.agent/scripts/index-bottlenecks.sh`)

~~~bash
#!/usr/bin/env bash
# .agent/scripts/index-bottlenecks.sh
# Pre-indexes concurrency, allocation, shell, and UI hot-path bottlenecks into .agent/context/bottlenecks.txt
set -uo pipefail
IFS=$'\n\t'

OUT_FILE=".agent/context/bottlenecks.txt"
mkdir -p .agent/context
: > "${OUT_FILE}"

echo "# PRE-COMPUTED RUNTIME, CONCURRENCY & UI BOTTLENECKS (Generated $(date -u +"%Y-%m-%dT%H:%M:%SZ"))" >> "${OUT_FILE}"
echo "# Format: [CATEGORY] file:line | symbol_or_rule | bottleneck_summary" >> "${OUT_FILE}"
echo "" >> "${OUT_FILE}"

# 1. Run AST-Grep structural rules across Go, C#, JS/TS/TSX, Rust, Swift, and Python
if command -v sg >/dev/null 2>&1 && [[ -f ".ast-grep/sgconfig.yml" ]]; then
  echo "## [AST-GREP] Structural Concurrency & Hot-Path Bottlenecks" >> "${OUT_FILE}"
  sg scan --config .ast-grep/sgconfig.yml --json 2>/dev/null \
    | jq -r '.[] | "[\(.ruleId)] \(.file):\(.range.start.line + 1)-\(.range.end.line + 1) | \(.message)"' \
    >> "${OUT_FILE}" || true
  echo "" >> "${OUT_FILE}"
fi

# 2. Bash Subshell & Pipeline Anti-Patterns (cat-pipe-while, unquoted expansions, eval)
if fd -q "\.(sh|bash)$" --max-depth 3; then
  echo "## [BASH] Subshell Loops, Unquoted Expansions & Unsafe Constructs" >> "${OUT_FILE}"
  if command -v shellcheck >/dev/null 2>&1; then
    fd -e sh -e bash --max-depth 4 -X shellcheck -f gcc --include=SC2002,SC2030,SC2031,SC2046,SC2086,SC2155,SC2206,SC2207 2>/dev/null \
      | sed -E 's/^/[BASH:perf-safety] /' >> "${OUT_FILE}" || true
  fi
  echo "" >> "${OUT_FILE}"
fi

# 3. Go Concurrency & Allocation Checks (copylocks, prealloc, bodyclose, contextcheck)
if [[ -f "go.mod" ]] && command -v golangci-lint >/dev/null 2>&1; then
  echo "## [GO] Slice Pre-Allocation, HTTP Body Leaks & Context Propagation" >> "${OUT_FILE}"
  golangci-lint run --disable-all -E prealloc -E bodyclose -E noctx -E govet --out-format=line-number ./... 2>/dev/null \
    | sed -E 's/^/[GO:perf] /' >> "${OUT_FILE}" || true
  echo "" >> "${OUT_FILE}"
fi

# 4. High-Signal Polyglot Regex Supplement (unbounded goroutines, C# async void, JS sync-in-async)
echo "## [HOT-PATH] Blocking Calls, Unbounded Concurrency & Allocation Hot-Spots" >> "${OUT_FILE}"
rg -n --no-heading \
  -g "*.{go,sh,bash,cs,js,ts,tsx,rs,swift,py}" \
  -g "!vendor/**" -g "!bin/**" -g "!obj/**" -g "!target/**" -g "!node_modules/**" -g "!.build/**" \
  "(async[[:space:]]+void\b|\.GetAwaiter\(\)\.GetResult\(\)|http\.DefaultClient|JSON\.parse\(JSON\.stringify|DispatchQueue\.main\.sync|\beval[[:space:]]+)" \
  2>/dev/null | head -n 80 >> "${OUT_FILE}" || true

echo "Bottleneck index written to ${OUT_FILE}."
~~~

### Step 8.3: Performance Surgeon Skill (`.agent/skills/perf-surgeon/SKILL.md`)

~~~markdown
---
name: perf-surgeon
description: Fix concurrency bugs, allocation hot-spots, shell anti-patterns, and UI bottlenecks by reading only 40-80 lines around the flagged function in .agent/context/bottlenecks.txt.
---
# Surgical Concurrency & Performance Protocol

1. **Locate Exact Bottleneck Coordinates:**
   Read `.agent/context/bottlenecks.txt` (via `./.agent/scripts/slice.sh .agent/context/bottlenecks.txt 1 50`) to get the exact `file:start-end` coordinates of the flagged function.
2. **Inspect Only the 40–80 Line Window:**
   Run `./.agent/scripts/slice.sh <file> <start_line> <end_line>` where `end_line - start_line <= 80`. Also run `npx graph-indexer callgraph <symbol> --depth 1` to check callers.
3. **Apply Language-Specific Surgical Fix:**
   - **Go (`go-defer-inside-loop` / `go-http-default-client-no-timeout` / `GO:perf`):** Extract the loop body into a helper function so `defer` runs per iteration (or close explicitly before continuing); replace `http.Get`/`http.DefaultClient` with `http.NewRequestWithContext(ctx, ...)` on a timeout-configured `*http.Client`; pre-allocate slices with `make([]T, 0, len(src))`.
   - **Bash (`BASH:perf-safety`):** Replace `cat file | while read` subshell pipelines with `while IFS= read -r line; do ... done < "${file}"`; replace external `sed`/`awk` forks inside loops with native Bash parameter expansion (`${var#prefix}`, `${var//a/b}`); quote all expansions (`"${var}"`).
   - **C# (`csharp-sync-over-async-blocking` / `csharp-transient-httpclient-socket-exhaustion`):** Replace `.Result`/`.Wait()` with `await ... .ConfigureAwait(false)` and propagate `CancellationToken`; replace `new HttpClient()` with injected `HttpClient` or `IHttpClientFactory`; convert `async void` to `async Task`.
   - **JS / TypeScript (`js-ts-sync-io-or-deep-clone-hotpath` / `react-unmemoized-effect-loop`):** Replace `JSON.parse(JSON.stringify(x))` with `structuredClone(x)`; replace `fs.*Sync` with `await fs.promises.*`; hoist static React objects and stabilize `useEffect` dependencies.
   - **Rust / Swift / Python:** Replace hot-path `.clone()` with borrowed slices or `Arc<T>`; move Swift blocking I/O off `@MainActor`; replace blocking Python calls inside `async def` with `asyncio.sleep`, `httpx.AsyncClient`, or `asyncio.to_thread`.
4. **Verify Single Target:**
   Run `./.agent/scripts/verify.sh <file> <function_name>`.
~~~

### Step 8.4: `/perf-fix` Slash Command (`.agent/prompts/perf-fix.md`)

~~~markdown
---
description: Fix a flagged concurrency, shell, memory allocation, or UI bottleneck by inspecting only the 40-80 line function window
---
Load the `perf-surgeon` skill. Target bottleneck or file/function: `$ARGUMENTS` (if empty, select the highest-severity item in `.agent/context/bottlenecks.txt`).

Strict Execution Sequence:
1. Locate the exact `file:line` entry in `.agent/context/bottlenecks.txt` matching `$ARGUMENTS`.
2. Inspect ONLY the 40–80 lines surrounding that function using `./.agent/scripts/slice.sh <file> <start> <end>`. Do NOT read the entire file.
3. Check 1-hop callers/callees via `npx graph-indexer callgraph <function_name> --depth 1`.
4. Replace only the target function body via Serena `replace_symbol_body` (or `replace_content` on the exact line range) to eliminate the bottleneck.
5. Verify immediately with `./.agent/scripts/verify.sh <file> <function_name>`.
~~~

---

## 9. Goal 5: Surgical Feature Injection at Specific Anchors ("Prune-Then-Inject")

When adding a feature, the agent must **never wander across the codebase** searching for files. The engineer provides the exact **anchor** (`<file_path> <symbol_name> [feature_spec]`), and `.agent/scripts/build-anchor-pack.sh` deterministically constructs a self-contained **1-hop neighborhood context pack** (`.agent/context/anchor_neighborhood.txt`).

### Step 9.1: API Surface Skeleton Indexer (`.agent/scripts/index-api-surface.sh`)

Uses `repomix --compress` (Tree-sitter skeleton extraction) and `graph-indexer outline` to extract all exported types, structs, interfaces, classes, records, and function signatures across Go, Bash, C#, JS/TS, Rust, Python, and Swift without implementation bodies:

~~~bash
#!/usr/bin/env bash
# .agent/scripts/index-api-surface.sh
# Extracts compressed Tree-sitter type/function signatures into .agent/context/api_surface.txt
set -uo pipefail
IFS=$'\n\t'

OUT_FILE=".agent/context/api_surface.txt"
mkdir -p .agent/context
: > "${OUT_FILE}"

echo "=== [1/2] HIGH-CENTRALITY REPOSITORY SYMBOL MAP (Graph Indexer Outline) ===" >> "${OUT_FILE}"
npx graph-indexer outline --max-tokens 2500 >> "${OUT_FILE}" 2>/dev/null || true
echo "" >> "${OUT_FILE}"

echo "=== [2/2] COMPRESSED TYPE & API SKELETONS (Repomix Tree-Sitter Compress) ===" >> "${OUT_FILE}"
npx repomix \
  --compress \
  --remove-comments \
  --remove-empty-lines \
  --no-file-summary \
  --style plain \
  --output ".agent/context/.repomix_raw.txt" >/dev/null 2>&1 || true

if [[ -f ".agent/context/.repomix_raw.txt" ]]; then
  # Filter to type, struct, interface, class, record, enum, trait, protocol, and function declarations across Go, C#, JS/TS, Bash, Rust, Swift, Python
  grep -E "^(File:|package |namespace |pub |public |internal |export |type |func |struct |enum |trait |protocol |interface |record |class |fn |def |async |function |[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{)" \
    ".agent/context/.repomix_raw.txt" | head -n 750 >> "${OUT_FILE}" || true
  rm -f ".agent/context/.repomix_raw.txt"
fi

echo "API surface index written to ${OUT_FILE}."
~~~

### Step 9.2: 1-Hop Anchor Neighborhood Builder (`.agent/scripts/build-anchor-pack.sh`)

~~~bash
#!/usr/bin/env bash
# .agent/scripts/build-anchor-pack.sh
# Usage: ./.agent/scripts/build-anchor-pack.sh <file_path> <anchor_symbol> [domain_keyword]
# Builds a deterministic, <1,800-token 1-hop context pack in .agent/context/anchor_neighborhood.txt
set -euo pipefail
IFS=$'\n\t'

FILE_PATH="${1:-}"
ANCHOR_SYMBOL="${2:-}"
KEYWORD="${3:-${ANCHOR_SYMBOL}}"
OUT_FILE=".agent/context/anchor_neighborhood.txt"

if [[ -z "${FILE_PATH}" || -z "${ANCHOR_SYMBOL}" ]]; then
  echo "Usage: ./.agent/scripts/build-anchor-pack.sh <file_path> <anchor_symbol> [domain_keyword]"
  exit 1
fi

mkdir -p .agent/context
: > "${OUT_FILE}"

echo "=================================================================" >> "${OUT_FILE}"
echo "ANCHOR TARGET: ${FILE_PATH} :: ${ANCHOR_SYMBOL}" >> "${OUT_FILE}"
echo "=================================================================" >> "${OUT_FILE}"

# 1. Find exact line number of anchor symbol in FILE_PATH
ANCHOR_LINE="$(rg -n "\b${ANCHOR_SYMBOL}\b" "${FILE_PATH}" | head -n 1 | cut -d: -f1 || echo 1)"
START_LINE=$(( ANCHOR_LINE > 15 ? ANCHOR_LINE - 15 : 1 ))
END_LINE=$(( START_LINE + 70 ))

echo "" >> "${OUT_FILE}"
echo "### [SECTION 1] 40-80 LINE ANCHOR WINDOW (${FILE_PATH}:${START_LINE}..${END_LINE})" >> "${OUT_FILE}"
./.agent/scripts/slice.sh "${FILE_PATH}" "${START_LINE}" "${END_LINE}" >> "${OUT_FILE}"

echo "" >> "${OUT_FILE}"
echo "### [SECTION 2] SYMBOL DEFINITION & BOUND EXTERNAL TYPES (graph-indexer read)" >> "${OUT_FILE}"
npx graph-indexer read "${FILE_PATH}:${ANCHOR_SYMBOL}" --max-lines 75 >> "${OUT_FILE}" 2>/dev/null || true

echo "" >> "${OUT_FILE}"
echo "### [SECTION 3] 1-HOP CALLERS & CALLEES (graph-indexer callgraph --depth 1)" >> "${OUT_FILE}"
npx graph-indexer callgraph "${ANCHOR_SYMBOL}" --direction both --depth 1 --limit 20 >> "${OUT_FILE}" 2>/dev/null || true

echo "" >> "${OUT_FILE}"
echo "### [SECTION 4] DIRECT REFERENCES (graph-indexer refs)" >> "${OUT_FILE}"
npx graph-indexer refs "${ANCHOR_SYMBOL}" --limit 20 >> "${OUT_FILE}" 2>/dev/null || true

echo "" >> "${OUT_FILE}"
echo "### [SECTION 5] LOCAL DEAD CODE / WARNINGS IN TARGET FILE" >> "${OUT_FILE}"
if [[ -f ".agent/context/dead_code.txt" ]]; then
  grep -F "${FILE_PATH}" .agent/context/dead_code.txt | head -n 15 >> "${OUT_FILE}" || echo "None" >> "${OUT_FILE}"
fi

echo "" >> "${OUT_FILE}"
echo "### [SECTION 6] EXISTING SHARED TYPES MATCHING '${KEYWORD}' (.agent/context/api_surface.txt)" >> "${OUT_FILE}"
if [[ -f ".agent/context/api_surface.txt" ]]; then
  rg -i -C 2 "${KEYWORD}" .agent/context/api_surface.txt | head -n 45 >> "${OUT_FILE}" || echo "No keyword matches; check api_surface.txt before creating any type." >> "${OUT_FILE}"
fi

echo "1-hop anchor pack generated at ${OUT_FILE} ($(wc -l < "${OUT_FILE}") lines)."
~~~

### Step 9.3: Master Context Refresh Script (`.agent/scripts/refresh-all-context.sh`)

~~~bash
#!/usr/bin/env bash
# .agent/scripts/refresh-all-context.sh
# Refreshes Graph Indexer SQLite DB and all three zero-token static analysis files in parallel.
set -euo pipefail
IFS=$'\n\t'

npx graph-indexer index >/dev/null 2>&1
./.agent/scripts/index-api-surface.sh &
PID_API=$!
./.agent/scripts/index-dead-code.sh &
PID_DEAD=$!
./.agent/scripts/index-bottlenecks.sh &
PID_BOTTLENECKS=$!

wait "${PID_API}" "${PID_DEAD}" "${PID_BOTTLENECKS}"
echo "All .agent/context/ indexes refreshed."
~~~

### Step 9.4: "Prune-Then-Inject" Skill (`.agent/skills/prune-then-inject/SKILL.md`)

~~~markdown
---
name: prune-then-inject
description: Inject a feature at an exact file+symbol anchor by inspecting only the 1-hop neighborhood, pruning local clutter first, reusing shared types, and verifying single-target compilation.
---
# Surgical Feature Injection Protocol ("Prune-Then-Inject")

Never search the repository when injecting a feature. Operate strictly within the 1-hop anchor neighborhood:

1. **Build & Read the 1-Hop Anchor Pack:**
   - Run `./.agent/scripts/build-anchor-pack.sh <file_path> <anchor_symbol> <domain_keyword>`.
   - Read `.agent/context/anchor_neighborhood.txt` via `./.agent/scripts/slice.sh .agent/context/anchor_neighborhood.txt 1 80` (and lines `81..160` if needed).
2. **Phase A — Local Prune First:**
   - Inspect Section 1 (the 40–80 line anchor window) and Section 5 (local dead code/warnings in that file).
   - Remove any unused local variables, dead branches, or redundant allocations inside the 40–80 line anchor window first so the injection site is clean.
3. **Phase B — Surgical Feature Injection:**
   - Reuse existing shared types, structs, records, classes, enums, or interfaces shown in Section 2 and Section 6 (`api_surface.txt`). **Never invent a duplicate type.**
   - Preserve exact method signatures expected by the 1-hop callers in Section 3 (`callgraph`), or update only verified 1-hop callers if explicitly requested.
   - Apply the change using Serena `replace_symbol_body` or `insert_after_symbol`.
4. **Phase C — Single-Target Verification:**
   - Run `./.agent/scripts/verify.sh <file_path> <anchor_symbol>`.
   - Confirm 0 broken callers, 0 duplicate types, and clean single-target compilation/linting.
~~~

### Step 9.5: `/inject-feature` Slash Command (`.agent/prompts/inject-feature.md`)

~~~markdown
---
description: Surgically inject a feature at an exact anchor (<file_path> <symbol_name> :: <feature_request>) using the Prune-Then-Inject protocol
---
Load the `prune-then-inject` skill.
Developer input: `$ARGUMENTS`
Expected format: `<file_path> <anchor_symbol> :: <feature_specification>`

If `<file_path>` or `<anchor_symbol>` is missing from `$ARGUMENTS`, STOP immediately and ask the engineer to provide the exact file path and function/struct/class/component anchor.

Strict Execution Sequence:
1. Run `./.agent/scripts/build-anchor-pack.sh <file_path> <anchor_symbol>` to generate `.agent/context/anchor_neighborhood.txt`.
2. Read `.agent/context/anchor_neighborhood.txt` in 80-line slices via `./.agent/scripts/slice.sh`. Do NOT search or read any file outside the 1-hop neighborhood.
3. **Prune First:** Clean up any local dead code, unused locals, or redundant allocations within the 40–80 line anchor window.
4. **Inject Second:** Wire in `<feature_specification>` using existing shared types from `api_surface.txt` and Serena symbol editing tools (`replace_symbol_body` / `insert_after_symbol`).
5. **Verify:** Execute `./.agent/scripts/verify.sh <file_path> <anchor_symbol>` and report the verification result.
~~~

---

## 10. Daily Workflow Reference & Verification Checklist

### Quick Command Reference

| Task Scenario | Terminal Pre-Step (Optional) | Agent Slash Command & Arguments | Deterministic Execution Flow |
| :--- | :--- | :--- | :--- |
| **Refresh Static Indexes** | `./.agent/scripts/refresh-all-context.sh` | *(Automatic on git commit)* | Updates `api_surface.txt`, `dead_code.txt`, `bottlenecks.txt`, and Graph Indexer SQLite DB at 0 token cost. |
| **Prune Dead Code** | None | `/prune-dead internal/billing/` | Reads `.agent/context/dead_code.txt`, proves 0 callers via `graph-indexer refs`, deletes via Serena `safe_delete_symbol`, and runs `verify.sh`. |
| **Fix Concurrency / Perf Issue** | None | `/perf-fix SyncOrdersAsync` | Reads `.agent/context/bottlenecks.txt`, slices only the 40–80 line hot function via `slice.sh`, fixes the bottleneck, and verifies single-target build. |
| **Inject New Feature** | None | `/inject-feature internal/auth/token.go ValidateToken :: Add 60s leeway check using existing ClockSkewConfig` | Builds 1-hop `anchor_neighborhood.txt`, prunes local mess around `ValidateToken`, wires feature with existing types, and verifies callers & compiler. |
| **Verify Current Worktree** | None | `/safe-verify scripts/deploy.sh run_migrations` | Runs `graph-indexer check`, `graph-indexer impact`, `check-duplicate-types.sh`, and single-target compiler/linter gate (capped at 20 lines). |

### Pre-Merge Verification Checklist

- [ ] **Bootstrap Executed:** Ran `./.agent/scripts/bootstrap-repo.sh` at repository root and confirmed `.agent/context/api_surface.txt`, `.agent/context/dead_code.txt`, and `.agent/context/bottlenecks.txt` are populated.
- [ ] **Pre-Commit Hook Active:** Ran `lefthook run pre-commit` and confirmed Graph Indexer, duplicate-type guard, and language compiler/linter gates (`go vet`/`golangci-lint`, `shellcheck`/`shfmt`, `dotnet build -warnaserror`, `tsc`/`eslint`, `cargo clippy`, `ruff`, `swiftlint`) execute cleanly.
- [ ] **Full-File Read Block Verified:** Verified that `.agent/extensions/context-circuit-breaker.ts` blocks raw `cat` or >80-line file reads and redirects the agent to `./.agent/scripts/slice.sh`.
- [ ] **Single-Target Verifier Tested:** Ran `./.agent/scripts/verify.sh <any_source_file>` and confirmed execution completes with output capped at 20 lines.