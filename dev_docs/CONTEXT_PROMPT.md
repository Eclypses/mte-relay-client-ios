## Context

This task mirrors the Android library testing modernization we recently completed (deterministic tests + test seams + coverage gate + CI branch behavior + changelog/release hygiene), adapted to this Swift Package Manager (SPM) library.

Read these project docs/files first (if present):
- library context doc
- README
- CI pipeline config
- release script
- CHANGELOG.md
- Package.swift and any scripts/config used for test/coverage/lint

## Rules

- Ask clarifying questions only when truly blocked; otherwise proceed with deterministic implementation.
- Keep changes minimal and focused on testing/quality/release workflow modernization.
- Do not rewrite git history.
- Preserve public runtime behavior.
- If architecture is ambiguous, state assumptions and continue.
- Update changelog/context/testing docs after implementation.
- Do not commit unless explicitly requested.

## Task

