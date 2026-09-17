---
name: model-selection
description: >-
  Required before spawning a subagent or selecting or changing an agent's model
  or reasoning effort.
---

# Model Selection

This installation uses the **@profile@** profile.

Optimise for the cheapest reliable completion using these defaults:

- **Ordinary subagent:** GPT-5.6 Luna, **high** effort.
- **New coordination subagent:** GPT-5.6 Sol, **high** effort.
  Coordination means directing other agents and integrating their results;
  a difficult individual task does not by itself qualify.

@provider-guidance@
For an existing coordinator, preserve Sol and its current effort in the work
profile, or Astra or Sol and its current effort in the personal profile.
Astra is unavailable for work; do not select or retain it for work coordination.

Use model IDs and effort supported by the configured harness. Keep delegated
work on the same approved provider and proprietary data within approved work
providers. Do not invent IDs or silently substitute an unsupported pair.

Use other models or model families only when the user explicitly requests them.
If there is uncertainty about the role, whether the default can complete the
task reliably, or the available model, effort, or provider, ask the user before
choosing. Reuse decisions already settled in the conversation.

Use benchmarks only as evidence when reviewing these preferences with the user.
