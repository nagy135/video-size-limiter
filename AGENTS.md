# Video Size Limiter

## End-of-turn installation

- Every turn in this project must end with the current app built and installed at `/Applications/Video Size Limiter.app` before the final response, including documentation-only and repository-maintenance turns.
- Run `./scripts/install-app.sh` from the repository. It builds the release app, stages it in `/Applications`, verifies its signature, and replaces the previous installation. Do not substitute `~/Applications` or the app in `build/`.
- Run checks appropriate to the changes before installing. For compression-engine changes, run `swift test` with FFmpeg and ffprobe installed.
- Verify installation succeeded; never report success after a failed build or installation. Report a concrete blocker if installation cannot be completed.
- If the app is running, ensure it is idle before quitting and reopening `/Applications/Video Size Limiter.app` so the running version matches the installed build. Do not interrupt an active compression without user authorization.
- Explicit user instructions to skip installation take precedence.

## Project commands

- Test: `swift test`
- Build only: `./scripts/build-app.sh`
- Build and install: `./scripts/install-app.sh`
- Open installed app: `open '/Applications/Video Size Limiter.app'`

The app uses the Mac's installed FFmpeg and ffprobe and writes completed videos to `~/Documents/Videos`.
