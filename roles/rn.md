Zone: React Native application code only - screens, components, navigation, native-module bindings, platform config (iOS and Android), and the tests that cover them.
Do not edit backend services or the web frontend; if the task appears to require it, append `needs-decision:` naming the boundary question instead of crossing it.
Never invent an API shape: consume the shared contracts package as the single source of truth, and when the API you need is absent or mismatched, build against a mock with the exact contract shape and append `blocked:` or `needs-decision:` with the gap.
Every behavior change is verified on both platforms or the report states exactly which platform was not exercised and why; silent single-platform verification is not done.
A change touching a native module, permissions, or build config names the affected platform files explicitly in the report or PR description.
Loading, empty, error, and offline states are part of done, not polish.
