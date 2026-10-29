# Catalyst: LocumView development and learning platform

Owner direction: 2026-10-29. Catalyst is a **core LocumView product offering and open-source contribution
project**, alongside the organization-led LocumView workspace. The clinical reference build is RHEL;
SUSE / openSUSE is In progress and Debian is Planned within its distribution-agnostic direction. Current workstream status comes from
[ROADMAP.md](../../ROADMAP.md#catalyst-build-and-contribution-plan).

## Purpose and audience

Encourage clinicians and other domain experts to deepen their IT engineering and building skills. People who
understand a problem should be able to prototype, inspect, test and improve its tools, collaborate effectively
with engineers, and contribute useful work back to open source. Clinical experience is one starting point;
researchers, scientists, educators and experts in other fields share the same foundation.

AI accelerates explanation, implementation and review while the person develops understanding and judgment.
Progress means being able to explain a design, debug a failure, write a meaningful test and maintain a system.
Generated code or course completion alone is not evidence of those skills.

## Why Alpine, and which languages

Alpine provides a small foundation built around musl and BusyBox, with apk for packages and OpenRC for services.
Those choices fit a lightweight, explicit and inspectable engineering workspace, useful on modest hardware and
in VDI guests. Packages are added deliberately and configuration stays reviewable. Resource efficiency must be
measured for the actual workload; a small OS alone is not evidence of secure clinical delivery. See
[Alpine's rationale](https://alpinelinux.org/about/).

Alpine is also an intentional learning choice: gain fluency in lightweight and containerized Linux platforms
and the resource optimization important to medical devices and embedded health technology. Learners should
understand dependencies, packaging, service boundaries and resource limits, then measure memory, CPU, storage
and response time against a project's requirements. Device gateways and simulated telemetry provide practical
contexts for those skills.

C and Rust are core to the systems and embedded development direction. Planned exercises cover device
interfaces, C interoperability, cross-compilation, debugging and resource-aware programming. Alpine is the
development and Linux learning environment; firmware may target bare-metal hardware, an RTOS or another Linux
system. Each target needs its own toolchain, simulator or hardware evidence and resource measurements. See the
[Embedded Rust Book](https://docs.rust-embedded.org/book/intro/index.html) for embedded and C/Rust foundations.

Catalyst is designed for development in any language through the appropriate native toolchain, project container
or supported runtime. Rust, C, Python, Go and TypeScript are the shared starting stack, not a restriction. Additional
languages and prebuilt tools need compatibility and editor/debugger checks, including musl/glibc boundaries.

Within LocumView, the main use case is a secure VDI development workspace for clinical technology: interoperability
services, synthetic workflows, device simulators, AI evaluation and supporting infrastructure. General-purpose
standalone use remains available. The hosted security, identity, transport, persistence, reconnect and isolation
acceptance gates below are still Planned; the current local VM is not evidence that hosted VDI is ready.

## Product boundaries

| Offering | Primary role | Independent acceptance |
|---|---|---|
| LocumView workspace | Organization-led Linux workspace with data sovereignty as its goal; clinical reference built on RHEL | RHEL evidence is specific to that build; SUSE / openSUSE In progress, Debian Planned, and every target needs distribution-specific delivery and hardening evidence |
| Catalyst | AI-focused engineering workstation, practical learning and open-source contribution | Alpine workstation, toolchains/editors, AI permissions, learning and public-release evidence |

Catalyst shares LocumView's design philosophy and product family. Its standalone installation requires no
LocumView subscription, account, cluster or clinical desktop. Optional hosted delivery is a later adapter with
its own transport, identity, storage, persistence and access review. Do not replace Alpine, rename runtime
interfaces or apply RHEL/SUSE controls to Catalyst by assertion.

## Build sequence and acceptance

1. **Engineering foundation.** Preserve the working Alpine/OpenRC/Sway stack, Fish, Git, LazyVim, VSCodium and
   rootless containers. Rust is strategic; retain C, Python, Go and TypeScript. Prove both editor tool bridges,
   formatting, diagnostics, tests, debugging and bounded C interoperability. Then prove clean build, recovery,
   overrides and selected physical hardware. Existing VM results do not establish a finished distribution.
2. **AI-assisted building.** Reuse the existing OpenCode, Codex and Claude Code clients and Vera persona plan.
   Validate one explicit backend, scoped context, visible changes, human review and tests. Show the actual
   provider/model; no silent cloud fallback. Authentication, model costs and source/data transfer are explicit
   owner choices. Unified Vera, speech and editor context integration each need their own evidence.
3. **Learning by building.** Keep Engineering Mode the default. Add optional Guided, Collaborative and Independent
   practice, original exercises, explanations, code review and increasing independence. Cover Linux/Git,
   programming, APIs, testing/debugging, containers, networking and cloud-native infrastructure. Persist private
   progress across restarts and assess demonstrated skills rather than assumed knowledge. Planned lightweight
   Linux/container and C/Rust embedded exercises must record a reproducible workload, resource budgets and
   measured results, with simulator and hardware evidence identified separately.
4. **Contribution and public release.** Review the selected Apache-2.0 license, third-party notices and assets;
   publish reviewed implementation source through the owner's release process. Provide a tested quick start,
   contribution guide, code of conduct, issue/PR templates and approachable documented tasks. Start with one
   small reproducible project and expand only after feedback. Do not advertise a downloadable release or an
   available contribution repository before it exists.
5. **Optional domains and delivery.** Build additive systems, AI/ML and clinical engineering projects with synthetic
   fixtures and simulators. Reuse shared toolchains. Test cloud/cluster/VDI adapters independently and preserve
   standalone use. Real data, devices, access changes and deployments retain their owner approval gates.

## Contribution pathways

Contributions should include code, reproducible bug reports, documentation, accessibility, learning exercises,
tests and domain requirements. Clinicians can explain workflow constraints and evaluate synthetic examples;
engineers can review architecture, debugging, security and reproducibility. Neither group has to master the
other's entire profession to contribute. Maintainers review changes and their evidence before integration.

The initial public website gives Catalyst its own page and navigation tab, presents it alongside the desktop
products and explains its mission with real prototype screenshots. It links to the product roadmap and invites
early collaborators through the existing contact route while public implementation release is Planned.

## Evidence and safety boundaries

Verified implementation evidence includes a working Alpine VM desktop, a dependency-free native Rust/C example
with fmt, strict Clippy, four boundary tests, deliberate compiler/lint diagnostics and GDB, plus managed LazyVim
Rust hover, definition, completion, formatting and diagnostic appearance/clearing. These are bounded engineering
checks, not a complete editor, agent, hardware or hosted-product acceptance.

Vera's unified runtime, persistent Learning Mode, selectable domain profiles, starter-project library and
Catalyst browser VDI are Planned. Use synthetic clinical data and simulated devices. Domain correctness,
privacy, clinical validation and human review are separate from language-level memory safety. Public learning
materials contain no personal progress, private endpoints, credentials or real patient information.

This plan changes product scope and documentation. It authorizes no production deployment, source publication,
account/access change, runtime rename, laptop installation or expansion of the agent infrastructure.
