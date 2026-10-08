# ADR 0011: Agentic Linus for LocumView engineering, local and git-gated

Status: Accepted (build on hold until the prerequisites in section 7 are done). Updated 2026-10-07: the persona is Argus, staged (see the update at the end)
Date: 2026-10-07

## Context

Linus is the owner's assistant in Open WebUI (k3s namespace `ai` on MikePC). Since 2026-10-06 it runs on
`qwen3.8-27b-q4km` through the in-cluster `ollama` Service (an HAProxy in front of the host Ollama on MikePC's
RTX 5060 Ti), with a 16k context. Measured on 2026-10-06: about 10 tokens/s generation, about 600 tokens/s prompt
processing (a full 16k prompt takes about 26 s), about 2.4 GiB of the model spills to system RAM, and Open WebUI's
native tool calling works end to end (a tool question answered in 24 s once tool output was kept compact).

Much LocumView engineering work is narrow and repeatable: writing changelog entries in the house format, checking
manifests against what is live, summarizing pod logs after an incident, and small fixes. On 2026-10-06 alone, three
live-versus-git drifts were found by hand (the Open WebUI and agency manifests, and the guacamole-db `cp -f` fix
that existed live before it existed in git). A local model can do this kind of work if it is given narrow tools,
compact inputs and no way to change anything except by proposing a reviewed git change.

Linus today is the opposite of that. Its `k3s_status` tool runs as the Open WebUI pod's own ServiceAccount
`ai/linus-viewer`, which is bound to `cluster-admin` (ClusterRoleBinding `linus-viewer-clusterbinding`): it can
apply and delete any object, exec into pods and read every Secret. The family personas' `k3s_readonly` tool uses a
separate `linus-readonly` token that is read-only except that it may create Jobs in `games`, and `games` has no Pod
Security admission, so that token could run an arbitrary pod. Open WebUI is also reachable from the internet at
`linus.ringcatch.io` with only its own password in front (fix pending, see Prerequisites).

The README and PLAN.md (section 6) set the direction this ADR serves: agentic tooling on local models, so that
regulated data never leaves the boundary. Engineering assistance for LocumView is the first, low-stakes place to
prove that pattern on our own systems before it is offered to anyone else. This is internal tooling for building
LocumView, not a product feature, so it does not touch the version-one scope locked by ADR 0009.

## Decision

### 1. One persona, narrow tasks, proposals only

A new Open WebUI model `linus-locumview` (base `qwen3.8-27b-q4km`, `think: false`, `num_ctx` 16384), visible to the
owner only. It gets only the LocumView tools in section 4: no web search, no Google tools, no claude-memory write,
nothing outside the LocumView boundary. Its read-only claude-memory knowledge (queued at the end of Phase 3) may be
attached for context.

Linus never changes a running system. Its only write path is a pull request from its own fork to the `locumview`
repo, which the owner reviews and merges, and the owner (or the owner's own tooling) applies any change to the
cluster.

### 2. Candidate tasks, ranked

Fit for a 27B model at about 10 tokens/s and 16k context: one task per chat, at most about three tool calls,
inputs pre-trimmed by the tools, outputs under about 600 tokens.

| Rank | Task | Value | Risk | Output | Why it fits |
|---|---|---|---|---|---|
| 1 | Draft a changelog entry (`notes/phase1-changelog.md`) from a commit range plus the owner's notes | High: every change needs one, the format is strict | Low: documentation only, reviewed | PR | Template-driven, short output, inputs are a diff and a few lines |
| 2 | Drift report: compare `k8s/locumview/*.yaml` with live objects in `locumview` | High: caught three drifts by hand on 2026-10-06 | Low: read-only | Report in chat; optional PR that brings git in line with live | Compact field-by-field diff fits easily in 16k |
| 3 | Summarize pod logs and events after an incident (for example a CrashLoopBackOff) | Medium | Low: read-only. Logs may carry sensitive data, which stays local | Report; optional changelog draft (task 1) | Tool returns the last N lines and filtered events, not raw dumps |
| 4 | Documentation consistency: README ADR table against `docs/adr/`, ROADMAP links, changelog numbering | Medium | Low | PR | Mechanical and checkable |
| 5 | Draft a small fix as a patch (a manifest field, a script line, a typo) | High | Medium: code or config that will be applied later | PR, diff capped at about 40 changed lines and 3 files, allowlisted paths only | Only with a stated failing symptom; the owner applies after merge |

Not in scope: multi-file features or refactors, anything needing more than 16k of context, anything touching
`k8s/locumview/secrets/`, `*.sops.yaml`, CI definitions, RBAC or NetworkPolicy objects, the hypervisor scripts that
run as root, or Ansible/Terraform runs. Any of these needs a per-task exception (section 3).

### 3. Least privilege

**Git: fork model.** A dedicated Gitea user `linus-bot`, not an administrator, with a password-less login and one
access token (scopes `write:repository` for its own fork and `read:user`; the token is useless against repos where
the account has no write rights). On `mike/locumview` it is a collaborator with **Read** only. It has its own fork,
`linus-bot/locumview`, and that fork is the only place it can push. `lv_propose_change` pushes a `linus/*` branch to
the fork and opens a pull request from the fork to `mike/locumview`. `linus-bot` has no write rights of any kind on
`mike/locumview`, so it cannot push, merge, edit branch protection or delete anything there, whatever its tool code
does. Branch protection on `main` stays as defense in depth: pushes and merges allowed for `mike` only, one approving
review required, force-push off. The token lives in a Secret declared in git without data.

*Documented alternative, only if the fork model has problems* (for example Gitea fork syncing or PR behavior that
gets in the way): `linus-bot` gets **Write** on `mike/locumview`, a protected-branch rule on `*` allows pushes and
merges for `mike` only, and `linus/*` is left unprotected so the bot can push only there. This must be verified by
test before use, and if Gitea's pattern rules cannot express it reliably, a server-side pre-receive hook rejecting any
`linus-bot` push outside `refs/heads/linus/*` is the fallback.

**Cluster.** A ServiceAccount `locumview/linus-reader` with a Role in `locumview` only: `get`, `list` and `watch` on pods,
`pods/log`, events, services, endpoints, deployments, statefulsets, replicasets, jobs, cronjobs, configmaps,
persistentvolumeclaims, ingresses and networkpolicies. No Secrets, no `pods/exec`, no `create`, `patch` or `delete` on
anything, and no cluster-scoped access. (`kubectl diff` needs patch rights, so the drift tool compares fetched objects
with the rendered manifests itself.) Anything broader is a per-task grant: written justification, the owner's
approval, a separate time-boxed RoleBinding, and its removal recorded in the changelog.

**Removing what Linus has today** (prerequisite, done before any agentic tool exists). Deliberate decision
(owner, 2026-10-07): the owner's own general Linus loses cluster-admin too. Its `k3s_status` tool becomes a read-only
cluster viewer with no Secrets and no exec; cluster changes are made by the owner directly or through Claude Code,
never by Linus.
- Delete ClusterRoleBinding `linus-viewer-clusterbinding` (cluster-admin).
- Set `automountServiceAccountToken: false` on the Open WebUI pod, so no tool silently inherits the pod's identity.
  Every tool uses an explicit, mounted, purpose-specific token.
- Rewrite the general `k3s_status` tool as read-only (a cluster-wide viewer role without Secrets or exec), or
  retire it. Its apply, delete, restart and exec functions are removed.
- Narrow `linus-readonly`'s `games` Job creation with a ValidatingAdmissionPolicy that only admits the fixed
  CoreProtect query Job (image `debian:trixie-slim`, read-only `minecraft-data` volume, no hostPath, no privileges).

### 4. Tools, per task

All tools are Open WebUI tools owned by the owner. Decision (owner, 2026-10-07, part of this phase): their code lives
in git at `homelab-infra/linus/tools/` and is synced into Open WebUI from there, so the code Linus runs is reviewed and
versioned. Git is the source of truth; edits made in the Open WebUI editor are overwritten by the next sync. This also
ends the drift between the Open WebUI database and `~/linus-assistant` found on 2026-10-06.

| Tool | Type | Identity | Used by tasks | Limits |
|---|---|---|---|---|
| `lv_repo_read(path, ref)`, `lv_repo_log(range)`, `lv_repo_diff(range)` | Read | `linus-bot` token | 1, 2, 4, 5 | `mike/locumview` (read) and its fork; output trimmed to a token budget |
| `lv_cluster_list(kind)`, `lv_cluster_get(kind, name)` | Read | `linus-reader` | 2, 3 | `locumview` namespace; compact one-line summaries, objects stripped of `managedFields` and status noise |
| `lv_logs(pod, container, tail, grep)` | Read | `linus-reader` | 3 | last 200 lines at most, optional filter |
| `lv_events(since)` | Read | `linus-reader` | 3 | warnings first, 50 at most |
| `lv_drift(manifest_path)` | Read | `linus-reader` and `linus-bot` | 2 | field-by-field comparison, ignores defaulted fields |
| `lv_propose_change(title, body, patch)` | **Write** | `linus-bot` | 1, 4, 5 (and 2 when the owner asks for a PR) | syncs the fork's `main` from `mike/locumview`, creates `linus/<date>-<slug>` in the fork, applies a unified diff to allowlisted paths (`notes/`, `docs/`, `k8s/locumview/` except `secrets/`, `README.md`, `ROADMAP.md`), size caps from section 2, commits as `linus-bot` with an `Audit-Id:` trailer, pushes to the fork, opens a PR from the fork to `mike/locumview` using a template (summary, evidence, tool calls). Refuses if the kill switch is off |

There is exactly one write tool, and it can only write to the fork. Everything else is read-only by construction:
the identity it uses has no write rights where it reads.

### 5. Audit and kill switch

**Audit.** Every tool call writes one JSON line (timestamp, chat ID, tool, arguments, result size, success, and for
writes the branch, commit and PR URL) to `/var/log/linus/audit.jsonl` on a dedicated PVC that the tools can append to
but no tool can read back or rewrite. The nightly backup job snapshots it, so the history is kept by restic
retention even if the live file were changed. Gitea independently records every push and PR by `linus-bot`, and each
PR opened also posts a notification to the `linus-prs` room on the homelab's self-hosted Matrix homeserver (local,
no federation; the homelab's messaging platform from 2026-10-07). A monthly check compares the audit log with Gitea's activity for
`linus-bot`.

**Kill switch, one step:** `linus-writes off` (a script in `homelab-infra/scripts/`) does two independent things:
it sets `writes_enabled: "false"` in ConfigMap `ai/linus-agent-controls`, which `lv_propose_change` reads before
every action, and it sets `prohibit_login` on the `linus-bot` Gitea user, which makes its token useless even if a tool
ignored the flag. `linus-writes on` reverses both. Read tools keep working, so Linus can still report. Turning the
switch off is also the first step of any incident involving Linus.

### 6. How this keeps local AI inside the boundary

- Inference is local: the model runs on MikePC's GPU through the in-cluster `ollama` Service. No prompt, file,
  manifest or log line goes to an external model API.
- The data path is local: the tools talk only to the cluster API and the self-hosted Gitea on the LAN. The persona
  has no web search and no third-party integrations.
- Changes go through review: a person merges every change, and the record (PR, commit, audit line) stays on systems
  the owner controls and backs up.
- The pattern is the product thesis in miniature: a local model, narrow tools, scoped identities, an audit trail and
  human approval. It is exactly what a regulated customer would need to see before allowing an agent near their own
  environment.

### 7. Prerequisites and rollout

1. Phase 3 complete, including Linus's read-only claude-memory access.
2. Public exposure fixed: `linus.ringcatch.io` behind Cloudflare Access (email one-time codes, allowed addresses
   only), or removed from the tunnel.
3. Cluster-admin removed and the `linus-readonly` Job scope narrowed (section 3).
4. Build: `linus-reader`, `linus-bot` with Read on `mike/locumview` and its fork, branch protection, tools in git
   with the sync, the audit PVC, the kill switch.
5. Acceptance tests, all recorded in the changelog:
   - `linus-bot` **cannot push to `mike/locumview`** (any branch, including a new `linus/*` branch) and **cannot
     merge** a pull request there; it also cannot change settings, branch protection or labels, or delete anything.
   - `linus-bot` can push a `linus/*` branch to its fork and open a PR from the fork, and nothing else.
   - `linus-bot` cannot read or write any other repository.
   - `linus-reader` gets "no" for `get secrets`, `create pods/exec` and anything outside `locumview` (`kubectl auth can-i`).
   - The owner's general `k3s_status` gets "no" for Secrets, exec and every write verb.
   - With the switch off, `lv_propose_change` refuses and Gitea refuses the `linus-bot` token.
   - Every test call appears in the audit log, and every PR appears in Gitea's activity for `linus-bot`.
6. Pilot tasks 1 and 2 only for two weeks. Then task 4, then task 5, each after a review of the PRs so far.

## Consequences

**Positive**
- Narrow, repeatable work (changelog entries, drift checks, log summaries) gets faster, and drift gets caught
  routinely instead of by accident.
- Linus loses cluster-admin, which closes the largest standing risk found on 2026-10-06.
- A working, auditable example of local agentic AI inside a boundary, usable as evidence for the product direction.

**Negative / costs**
- A 27B model at 10 tokens/s is slow for anything long; tasks must stay small and tools must keep outputs compact.
- Owner review is the bottleneck by design; low-quality PRs cost review time. The pilot measures this.
- More moving parts: a bot account, a token, a PVC, tools in git and a sync step.
- Linus's general cluster questions become read-only and lose exec and log access outside the namespaces granted.

**Notes**
- Prompt injection is expected: pod logs, events and repo files are untrusted input. The design does not rely on the
  model resisting it. Limited identities, one capped write path into review, and the kill switch bound the damage.
- If LocumView ever processes real patient data, logs read by `lv_logs` may contain it. That data stays on local
  systems, but log summarization for such environments needs its own data-handling review first.

## Update 2026-10-07: the persona is Argus; staged path to coding and a platform agent

Owner direction, 2026-10-07. Everything above still applies except where this section changes it. Plan only: nothing
here is built, and the build stays on hold until the prerequisites at the end of this section are done.

**Name and scope.** The persona is **Argus** (model id `argus`; this ADR called it `linus-locumview`, "agentic
Linus"). It is private to the owner: no access grants to other users, hidden from everyone else. Its definition lives
in git with the other personas (`homelab-infra/linus/personas/`, applied by `apply.py`). The name was freed by
retiring the PV workbench's Argus Discord bot on 2026-10-07; nothing from that bot carries over. The Gitea account
`argus-bot` below is new and unrelated to that bot's old Kubernetes Deployment of the same name. All identities in
sections 3 to 5 take the new name: Gitea user `argus-bot` with its fork `argus-bot/locumview` and branches
`argus/<date>-<slug>`, ServiceAccount `argus-reader`, ConfigMap `argus-agent-controls`, kill switch
`argus-writes off|on`, audit log `/var/log/argus/audit.jsonl`.

**Stages.** Each stage starts only after the previous one has run cleanly and the owner says go.

1. **Read-only knowledge and tools.** The read tools of section 4 (repository, `locumview` namespace objects, logs,
   events, drift) and read-only claude-memory knowledge. No write tool exists in this stage.
2. **Coding through the fork model.** `argus-bot` has Read on `mike/locumview` and writes only to its own fork; it
   opens pull requests and never pushes to `main` or merges, and it never applies anything to the cluster: the owner
   applies after merge, as in section 1. Pre-commit checks run on every Argus PR (see Sandbox). The patch limits of
   section 2 stay as written: about 40 changed lines, 3 files, allowlisted paths only. Added to the excluded paths:
   Argus's own tool server, sandbox and persona definitions (`agent/` and its deployment manifests), so it can never
   propose changes to its own controls. **At most 3 open Argus pull requests at a time:** before opening one, the tool
   server counts `argus-bot`'s open PRs on `mike/locumview` and refuses at 3, telling Argus to wait for review. This
   keeps review load bounded and limits how much an injection could queue up.
3. **Platform agent, later.** Argus becomes the general agent of the LocumView platform. That is a product feature
   with real users and possibly regulated data, so it needs its own ADR first (users and permissions, audit, data
   protection, the EU posture of ADR 0008). Nothing in this ADR authorizes stage 3.

**Sandbox for code execution.** Code Argus writes or runs (tests, linters, pre-commit, applying a patch to check it)
runs only in short-lived Kubernetes Jobs in a dedicated namespace `argus-sandbox`:
- No cluster credentials: a ServiceAccount with no RoleBindings and `automountServiceAccountToken: false`.
- Network: default-deny NetworkPolicy; egress only to DNS and the Gitea service, nothing else (no internet, LAN,
  cluster API or other namespaces). Ingress: none.
- The Job holds only a read-only Gitea token (clone); it never holds `argus-bot`'s write token. It returns a patch
  and its check results to the tool server, which enforces the path allowlist and size caps and does the push itself.
- `ttlSecondsAfterFinished: 600`, `activeDeadlineSeconds: 900`, `backoffLimit: 0`; resource limits (1 CPU, 1 GiB
  memory, 2 GiB ephemeral storage); Pod Security `restricted`, non-root, read-only root filesystem with an `emptyDir`
  workspace; the toolchain image pinned by digest.
- Pre-commit runs in the sandbox before every push, and its output goes into the PR body. Once CI exists (the
  ROADMAP housekeeping item), the same checks also run on every PR in a runner of the same class, with no secrets.

**Tools as a portable tool server.** Argus's tools are not Open WebUI tool code. They are a small tool server in git
(MCP over HTTP, or a similar open protocol), in the `locumview` repo under `agent/`, built as a pinned image and run in
its own namespace `argus` with the `argus-reader` and `argus-bot` identities. Open WebUI connects to it as an external
tool server, and the stage 3 platform agent can reuse it unchanged. This supersedes section 4's "all tools are Open
WebUI tools" for Argus: the Open WebUI pod never holds Argus's tokens. The tool list, limits and single write tool of
section 4 are unchanged. (The general Linus personas' tools still move to `homelab-infra/linus/tools/` as decided.)
Policy lives in the server's code, not in the prompt: path allowlist, size caps, kill-switch check, audit write.

**Prompt injection.** Everything Argus reads is untrusted: repository files, PR comments, commit messages, pod logs,
events, manifests and memory. Instructions found in that content are data, never commands. The containment does not
rely on the model resisting injection: the fork-only write path (no rights on `mike/locumview`), human review of every
PR, the sandbox without credentials or network beyond Gitea, and tool-server policy enforced in code bound what a
successful injection can do to "a pull request the owner rejects".

**Kill switch and audit:** as written in section 5, under the new names, with the audit storage made explicit. The
audit log is a PersistentVolumeClaim `argus-audit` (storage class `local-path`) in namespace `argus`, mounted only by
the tool server; no Argus pod uses a hostPath volume. The nightly restic job of the node that holds the volume backs it
up with every other local-path volume (`backup-mikepc` or `backup-debianbox`, both include all local-path PVs), so the
7 daily, 4 weekly and 6 monthly snapshots keep the history even if the live file were changed. Stdout to cluster logs
was considered and not chosen: the cluster has no log aggregation, and container logs rotate within days, so they
are not an audit record. The tool server also prints each audit line to stdout for live viewing. No tool reads the
audit log back. Until the homelab Matrix server exists (on hold since 2026-10-07), PR notifications come from
Gitea's own notifications instead of a Matrix room.

**Prerequisites (unchanged, current state):**
1. Cloudflare Access in front of Open WebUI (`linus.ringcatch.io`), verified from outside the LAN. Not done: the
   Cloudflare account has no Zero Trust organization yet.
2. Phase 3 complete, including Linus's read-only claude-memory access. Steps 1 to 5 done 2026-10-07; read-only
   access waits for item 1.
3. Cluster-admin removed (done 2026-10-07: binding `linus-viewer-clusterbinding` deleted) and the `linus-readonly`
   Job scope narrowed (pending).

**Acceptance tests added** to section 7, for stage 2: a sandbox Job has no ServiceAccount token mounted, cannot reach
anything except DNS and Gitea (tested against the cluster API, the internet and a LAN host), holds no write token, and
is gone within `ttlSecondsAfterFinished`; a patch touching `agent/` or another excluded path is refused by the tool
server; a fourth PR is refused while 3 are open; the audit volume appears in the next nightly restic snapshot; an
injected instruction planted in a test file does not produce any action outside a PR to the fork.
