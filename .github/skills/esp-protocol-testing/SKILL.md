---
name: esp-protocol-testing
description: Design robust tests for ESP serial protocol behavior and transport framing.
---

# ESP protocol testing skill

Use this skill when changing:

- ESP command packet serialization
- SLIP framing or parsing
- timeout/retry behavior
- response parsing and error mapping

Testing expectations:

- assert encoded bytes
- assert parsed values and status flags
- include split-frame and partial-read cases
- preserve hardware-independent execution
