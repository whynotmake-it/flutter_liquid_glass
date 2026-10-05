# Tooling audit and convergence proposal

Audited at `5e82cdb88`, 2026-10-03. No runtime tooling was changed or deleted.
The pre-existing working-tree edit to `docs/TODO.md` is untouched.

- [Audit](tooling-audit.md): entry points, callers, defects, stale inputs,
  reference inventory, and reproducibility of every results document.
- [Convergence plan](001-converge-tooling.md): the proposed keep/delete boundary,
  interfaces, migration order, documentation changes, and verification gates.

| Plan | Priority | Effort | Dependency | Status |
| --- | --- | --- | --- | --- |
| 001: Converge matching and benchmarks without losing evidence | P1 | L | Recover or explicitly classify historical evidence first | PROPOSED |

The user requested an audit and proposal, not destructive cleanup. Do not execute
deletions, recapture references, access devices, fetch assets, or commit merely
because a file appears in the proposal.
