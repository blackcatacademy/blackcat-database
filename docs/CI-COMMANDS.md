# CI Override Commands

Use these **slash-commands** in a PR comment:

- `/override` – add the override label (bypasses CI gate)
- `/unoverride` – remove the override label
- `@bot override` – alias for `/override`

**Who can use it?**
- Users listed in `.github/ci-blocking-labels.json → overrides.users`, or
- Repository collaborators with `write/maintain/admin` permission.

**Which label is used?**
- First label from `.github/ci-blocking-labels.json → overrides.labels` (default `override:allowed`).

> Auditing: action adds a reaction to the command comment (`🚀` on add, `👀` on remove).
