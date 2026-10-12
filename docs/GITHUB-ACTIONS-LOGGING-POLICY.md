# GitHub Actions Logging Policy

Status: **REQUIRED**

Every workflow that builds, tests, compiles, links, packages, or runs diagnostics must preserve diagnostically useful stdout/stderr in a durable artifact.

## Required behavior

1. Pipe the native command's combined stdout/stderr to a workspace log file.
2. Preserve and return the native command's actual exit code.
3. Upload the log artifact with `if: always()` so both PASS and FAIL runs retain evidence.
4. Give artifacts deterministic, run-specific names.
5. Keep logs long enough to diagnose recent failures.

## Failed-run diagnostic flow

For any failed run:

1. identify the exact workflow run ID;
2. identify the failed job ID;
3. fetch the raw job log **once**;
4. if usable, inspect the first meaningful/root error;
5. if raw log is unusable, do **not** retry it;
6. fetch the run's durable log artifact;
7. inspect the artifact log content;
8. only then patch source or workflow logic.

Never infer root cause from run status, job status, step names, conversation history, or memory.

If neither raw log nor artifact can be consumed because of connector/tool limitations, report the exact blocked boundary and stop rather than looping.

## Current tvOS CI artifact

The tvOS workflow writes:

`ci-logs/tvos-build-test.log`

and uploads it with `actions/upload-artifact@v4` using a run-specific artifact name.
