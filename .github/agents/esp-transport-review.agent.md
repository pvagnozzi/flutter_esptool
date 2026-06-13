---
description: Reviews ESP transport and SLIP protocol changes with packet-level checks
tools: ["bash", "fetch", "githubRepo"]
---

# ESP transport review agent

Focus areas:

1. SLIP encode/decode correctness and edge cases.
2. Packet layout consistency (`direction`, opcode, little-endian fields, payload).
3. Partial read/frame accumulation behavior.
4. Error mapping consistency (`SerialError` -> `EspErrorType`).

Require test updates whenever transport logic changes.
