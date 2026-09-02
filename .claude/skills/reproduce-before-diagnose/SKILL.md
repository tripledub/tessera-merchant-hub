---
name: reproduce-before-diagnose
description: Use when investigating a bug or issue the user reports, before forming a theory about its cause. Elicit and replay the user's exact click-by-click steps and observe the actual failure rather than guessing from code or log reading alone.
---

# Reproduce Before Diagnose

When a user reports a bug, do not theorize about the cause from reading code or logs alone.

1. Get the **exact, concrete sequence of actions** that triggers it — which button, which file, in what order, from what state. Vague descriptions ("processing is stuck", "upload isn't working") are not enough; ask for or extract the click-by-click steps.
2. **Replay those exact steps** (or trace the precise code path they describe) before proposing a cause. A plausible-sounding theory that isn't grounded in the actual repro is often wrong.
3. If your first read of the symptom doesn't match what the user is describing, say so and re-ask rather than running with your own interpretation — a misread symptom sends the fix in the wrong direction.

## Why this matters here

In this project, diagnosing before eliciting the exact repro has repeatedly cost extra correction rounds:

- The agent read "processing" as referring to an app state and investigated the wrong flow. The real bug only surfaced once the user spelled out: "I uploaded a single file - all good. Tried to upload a second, original file and new file appear in list of files to upload + Upload button is disabled."
- The agent dismissed anomalous behavior as normal. The real bug only became clear once the user described the exact trigger: "I opened [the] file archive and there was a subfolder. I selected all and dragged onto dropzone."

Both bugs were reproducible and diagnosable immediately once the exact steps were known — the time lost was in theorizing before eliciting them.
