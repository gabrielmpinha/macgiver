# Repository Guidelines

## Commit conventions

- Write every commit message in English.
- Use the Conventional Commits format:

  ```text
  <type>(<scope>): <short description>
  ```

- Use a clear scope such as `menu-bar`, `keyboard`, `keep-awake`, `docs`, `build`, or `repo`.
- Use these commit types when applicable: `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `chore`, and `ci`.
- Keep the subject concise and descriptive. For non-trivial changes, add a commit body explaining what changed and why.
- Do not add `Co-authored-by` trailers or any other assistant attribution.
- Do not mention Codex or the assistant in commit messages, bodies, or trailers.

## Push policy

- Create commits locally when requested or when the work is complete.
- Never run `git push` unless the user explicitly requests it in the current message.
- Never force-push or rewrite remote history unless the user explicitly requests it.

## Verification

- Check `git status` before committing.
- Run relevant build and test commands before committing when code changes are involved.
- Keep generated build artifacts and local development files out of commits according to `.gitignore`.
