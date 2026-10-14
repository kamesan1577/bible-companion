# Exact committed source export

Requires Node.js 24+ and Git. No npm install, network access, cloud account, GitHub authentication, or deployment is needed. Run from the repository root:

```sh
node --test scripts/export-source.test.mjs
node scripts/export-source.mjs --output ../bible-source-release
```

The default exports HEAD only when tracked and nonignored untracked worktree state is clean. Commit the reviewed release first. The output directory must not exist, its parent must exist, and it must be outside the repository. Existing files, directories, and symlinks are never overwritten.

To preserve a specific existing commit even while other work continues:

```sh
git rev-parse HEAD
node scripts/export-source.mjs --commit FULL_COMMIT_OBJECT_ID --output ../bible-source-exact
```

Use the recorded full object ID in place of the placeholder. Short unambiguous IDs are accepted; moving branch/tag names are rejected. Explicit-commit mode ignores worktree edits, staging changes, untracked files, and ignored files. Those changes are NOT backed up. A historical commit may predate this exporter; the exporting script itself is included only if committed in the selected tree.

## Deliverables and verification

The new private local directory contains:

- `bible-companion-<full-commit>.tar`: all regular files in that exact Git commit, under `bible-companion/`.
- `manifest.json`: full commit and tree IDs, archive byte length and SHA-256, and each file's path, Git blob ID, executable mode, byte length, and SHA-256.

```sh
sha256sum ../bible-source-exact/bible-companion-*.tar
cat ../bible-source-exact/manifest.json
# Inspect before extraction; extract only into a new review directory.
tar -tf ../bible-source-exact/bible-companion-*.tar
mkdir ../bible-source-review
tar -xf ../bible-source-exact/bible-companion-*.tar -C ../bible-source-review
```

Compare the archive hash to `archiveSha256`. Export the same commit again to another new output directory and compare both files with `cmp`; they must be byte-identical. The archive uses deterministic POSIX ustar headers, fixed zero timestamps/ownership, Git tree order, and modes 0644/0755. It does not use `git archive`, so local Git archive configuration or committed `export-ignore`/`export-subst` attributes cannot silently omit or rewrite source. Every Git read disables replacement objects, so local `git replace` refs cannot substitute another commit, tree, or blob. Invalid UTF-8 filename bytes are rejected instead of being silently renamed or merged.

## Privacy and limitations

Only Git objects are read as archive content. No `.git` history/config, ignored credentials, dependencies, caches, databases, or runtime state are collected. If known private/generated paths, symlinks, submodules, or private key headers are tracked in the selected commit, the entire export fails instead of silently removing them. Overlong paths unsupported by portable ustar also fail. This is a conservative guard, not comprehensive secret detection: review committed source for credentials and private data before delivering or publishing it. The script is intended for this source-sized repository and assembles the archive in memory.

The manifest is outside the tar to avoid a circular archive hash. This is a source snapshot, not a Git history backup or signed provenance attestation. It does not prove successful builds, native-device tests, or production readiness. Exporting does not create a remote repository or upload anything. GitHub creation and user delivery are separate authorized steps.
