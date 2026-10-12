# SiTV-ATV — MANDATORY AGENT ENTRY GATE

Status: **REQUIRED / REPO SOURCE OF TRUTH**

This file prevents repeated work, state drift, stale-branch diagnosis, and GitHub Actions diagnosis without real logs.

## 0. STOP GATE

Before diagnosis, code edits, workflow changes, player/DRM changes, or handoff continuation:

1. verify repository and current repository state from GitHub;
2. read this `AGENTS.md` from the branch/ref being worked on;
3. read `docs/PROJECT-STATE.md` if present;
4. read `docs/GITHUB-ACTIONS-LOGGING-POLICY.md` if present;
5. inspect current repository state before relying on conversation memory.

Repository state wins over conversation memory or handoff summaries.

## 1. LATEST WORKFLOW RUN IS THE CI SOURCE OF TRUTH

Before **every** CI diagnosis, CI status report, or continuation after a previous run:

1. fetch the latest workflow runs for the **entire repository with no branch filter**;
2. select the run with the highest/current `run_number` (normally the first latest run returned);
3. read `run_number`, `id`, `head_branch`, `head_sha`, `status`, and `conclusion` directly from that run;
4. treat that run's `head_branch` as the active CI branch for the next diagnostic step;
5. only then fetch jobs/logs/artifacts for that exact `run_id`.

**Forbidden:**
- starting CI diagnosis from a branch name remembered from an earlier run, conversation, or handoff;
- using `?branch=...` to decide what the repository's latest run is;
- assuming the active dev branch has not changed;
- continuing to diagnose an older run after a newer run exists, unless explicitly investigating historical behavior;
- reporting an older run number as current without first refreshing repository-wide workflow runs.

If the user/UI reports a newer run number than the agent currently sees, immediately refresh the **repository-wide** workflow run list before doing anything else.

Before changing code because of a failed run, verify that the run's `head_sha` still matches the relevant current branch HEAD. If branch HEAD has advanced to a newer run, refresh from step 1 and diagnose the newer run instead unless the older run is explicitly requested.

## 2. NO REPEATED WORK / NO STATE DRIFT

Before proposing or repeating a fix, verify whether it already exists on the current branch.

Forbidden:
- retrying the same raw-log path after fallback conditions are reached;
- inferring a compiler/build root cause from run metadata or step names;
- claiming a fix/checkpoint exists without re-fetching it;
- modifying `main` or another branch when the active work is on a dev branch unless explicitly requested.

## 3. GITHUB ACTIONS DIAGNOSTIC GATE

For every failed GitHub Action:

1. refresh repository-wide workflow runs and identify the exact current workflow run ID;
2. identify exact failed job ID;
3. fetch raw job log **once**;
4. if real log text is returned, find the first meaningful/root error;
5. if raw log is empty, inaccessible, suppressed, truncated, `Skipped`, or otherwise unusable, **do not retry the same path**;
6. immediately fetch the durable log artifact required by `docs/GITHUB-ACTIONS-LOGGING-POLICY.md`;
7. inspect the actual artifact log;
8. only after real error text is visible may code/workflow logic be changed.

If neither raw log nor durable artifact can be consumed because of connector/tool limitations, report the exact blocked boundary and STOP. Do not redesign logging unless repository evidence proves logging is missing or broken.

## 4. BRANCH / SCOPE GATE

Before every write:
- verify the target branch from current GitHub state, not memory;
- preserve `main` unless explicitly asked to change it;
- keep experimental player/DRM work on dev branches;
- do not widen scope beyond the current task without evidence.

## 5. VERIFICATION BEFORE REPORTING SUCCESS

After every write/change, re-fetch the changed file/commit/workflow and verify the intended content is present.

Never report `done`, `fixed`, `saved`, or `locked` based only on an attempted write call.

## 6. PROJECT SCOPE LOCKS

Current SiTV-ATV scope:
- tvOS native app;
- no EPG;
- no QR input;
- playlist sources, groups, favorites, channel playback;
- AVPlayer for native-compatible streams;
- VLCKit fallback for supported non-DRM streams;
- DASH/ClearKey work remains isolated and must only use authorized keys/licenses and permissively licensed dependencies.

Do not claim AVPlayer or VLCKit supports DASH/CENC/ClearKey unless proven by source and tests.
