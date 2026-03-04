# KUMO Router Label Manager v5.0.0 — Audit, Test & Package Design

**Date**: 2026-03-03
**Goal**: Comprehensive multi-agent audit, test suite creation, bug fixes, and Inno Setup installer packaging.

## Target

- **Version**: v5.0.0 (unified across all files)
- **Deployment**: Inno Setup Windows installer (.exe) with Start Menu shortcuts
- **Scope**: Full audit of PowerShell GUI (~3,900 lines) and Python backend (~5,500 lines)

## Pipeline: 3 Waves

### Wave 1 — Parallel Audit (4 agents)

| Agent | Focus | Deliverable |
|-------|-------|------------|
| Code Reviewer | PS 5.1 compat, logic errors, dead code, WinForms bugs | Prioritized bug list |
| Silent Failure Hunter | Swallowed exceptions, empty catch blocks, bad fallbacks in REST/Telnet/TCP | Silent failure points |
| Security Engineer | HTTP plaintext, Telnet creds, input sanitization, file path traversal | Security findings with severity |
| Code Explorer | Architecture map, dead code, version mismatches, undocumented behavior | Architecture report |

### Wave 2 — Fix, Harden & Test (sequential)

1. Senior Fullstack Dev — implement all audit fixes
2. QA Engineer — create pytest suite for Python backend
3. Code Simplifier — final cleanup pass

### Wave 3 — Package & Release

1. DevOps Engineer — Inno Setup installer, version alignment, launcher
2. Final Code Review — verify before release commit

## Version Alignment

Unify to v5.0.0 in:
- `pyproject.toml` (currently 3.0.0)
- `VERSION.md` (currently 2.0.0)
- `KUMO-Label-Manager.ps1` title bar (already v5.0)
- Inno Setup installer metadata

## Out of Scope

- Web interface, mobile app, cloud sync
- Auto-update mechanism
- Code signing
- Lightware MX2 completion (separate effort)
