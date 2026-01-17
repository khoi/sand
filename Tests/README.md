# Local E2E Tests

This directory contains local, bash-based end-to-end tests for the sand CLI:

- `Tests/run` runs all cases
- `Tests/lib/common.sh` holds shared helpers
- `Tests/cases/*.t` are individual test cases

## Run

From the repo root:

```
./Tests/run
```

## Environment variables

You can customize the run with the following variables:

- `SAND_BIN`: path to an existing sand binary (skips `swift build`).
- `SAND_E2E_IMAGE`: Tart OCI image to use (default `ghcr.io/cirruslabs/ubuntu:latest`).
- `SAND_E2E_TIMEOUT_SEC`: timeout for `sand run` (default `900`).
- `SAND_E2E_IP_WAIT_SEC`: timeout for `tart ip --wait` (default `180`).
- `SAND_E2E_SKIP_DOCTOR`: if set, skips the `doctor` test.
- `SAND_E2E_SSH_USER`, `SAND_E2E_SSH_PASSWORD`, `SAND_E2E_SSH_PORT`: SSH creds for the guest (defaults `admin/admin/22`).
- `SAND_E2E_RUNNER_PREFIX`: prefix for generated runner names (default `sand-e2e`).

## Notes

- These tests are intended for local verification only (no CI).
- Each test uses a unique runner name to avoid interfering with existing sand services.
- Some cases intentionally stop VMs, trigger restarts, or send signals to the `sand` process.
