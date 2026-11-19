---
name: model-selection
description: >-
  Required before spawning a subagent or selecting or changing an agent's model
  or reasoning effort.
---

# Model Selection

Profile: **@profile@**. Prefer the cheapest model that reliably finishes the task.

- Ordinary subagent: `@subagent-model@`, high effort.
- New coordinator (directs subagents and integrates their results; a hard task
  alone does not qualify): `@coordinator-model@`, high effort.
- Keep an existing coordinator's model and effort. Never select or retain Astra.
- Use only IDs and options the harness lists; never invent or silently
  substitute them.
- Keep delegated work on the parent's provider unless the user asks otherwise,
  and proprietary data on approved work providers.
- Use other models only when the user asks. Ask when the role, model, effort or
  provider is unclear, or the default may not finish the task; reuse settled
  decisions.
@provider-guidance@
