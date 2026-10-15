# 0005: Access policies are declared as data and reviewed as rendered Cedar

- **Status:** Accepted (2026-10-14), proven 2026-10-15
- **Deciders:** platform team

## Context

Raw Cedar scattered through Terraform is hard to read, review and lint. Reviewers need to see the effect of a change, not only the input that produced it.

## Decision

- The module renders Cedar from a **declarative input** (groups, identity groups, owner, justification, sensitive endpoints) with deterministic output and a machine readable header.
- Three layers: plan time **validation**, a **lint** gate (parse with the official Cedar CLI, no unscoped permit, owner and justification, device context on sensitive endpoints), and **golden file** tests.
- The deployment repository keeps a **reviewed copy** of every rendered policy in `policies/`; a test fails if they differ, so every access change shows its Cedar diff in the pull request.
- Raw Cedar is allowed through an escape hatch with mandatory security review.

## Consequences

- Each access change touches two files (the intent and the effect): intended friction.
- Reviewers read Cedar diffs, which are short and readable.
- See [approval gate](../approval-gate.md) for the worked examples.
