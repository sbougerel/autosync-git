<a href="https://github.com/sbougerel/autosync-git"><img src="https://www.gnu.org/software/emacs/images/emacs.png" alt="Emacs Logo" width="80" height="80" align="right"></a>
## autosync-git.el
*Automatically synchronize a git repository with its upstream*

---
[![License GPLv3](https://img.shields.io/badge/license-GPL_v3-green.svg)](http://www.gnu.org/licenses/gpl-3.0.html)

[![CI Result](https://github.com/sbougerel/autosync-git/actions/workflows/makefile.yml/badge.svg)](https://github.com/sbougerel/autosync-git/actions)

Autosync-Git automatically synchronizes a local git repository branch with
its upstream by invoking `git` directly.  It targets the narrow use case of
keeping a *personal* repository in sync between devices: private notes,
configuration backups, or any single-author "save the current state to the
cloud" workflow.  Autosync-Git is NOT suitable for team workflows; do not use
it on shared branches.

The entry point is `autosync-git-mode`, a buffer-local minor mode that
installs a periodic background pull and a debounced after-save push for the
buffer's repository.  It is normally turned on via `.dir-locals.el` (see
Configuration below) so that visiting any file under a sync'd repository
activates the automation.

The four interactive commands below can also be invoked manually,
independently of the mode:

    M-x autosync-git-pull      Fetch and update the local branch.
    M-x autosync-git-push      Stage all changes, commit, and push.
    M-x autosync-git-status    One-line summary (clean/dirty, ahead/behind).
    M-x autosync-git-sync      Pull, then push.

### Pull strategy

Autosync-git tries its best to pull from upstream without disturbing your
current work.  `autosync-git-pull` uses a probe-then-rebase strategy:

1. Fetch from upstream.
2. Compare HEAD to @{upstream}.  In-sync or ahead: nothing to do.
   Behind: fast-forward (conflict-free).  Diverged: probe before acting.
3. The probe uses `git merge-tree` to perform a 3-way merge in memory
   without touching the working tree.  If the probe is conflict-free,
   the configured operation (rebase or merge) runs.  Otherwise the
   operation is cancelled and the working tree is left untouched.

The default operation is rebase, controlled by `autosync-git-pull-style`; set
it to `merge` to create a merge commit instead.  Rebase is the default
because personal-sync commits are auto-generated snapshots, where preserving
original SHAs matters less than keeping history linear.

A prefix arg (`C-u M-x autosync-git-pull`) skips the probe and runs the
configured operation regardless, which may leave the working tree in REBASE
or MERGING state for manual resolution.

Note: `git merge-tree --write-tree` requires git 2.38 or newer.  On older git
versions the probe always reports a conflict and the pull falls back to
refusing -- failing closed.  Use `C-u` or upgrade git.

### Configuration

Activate the mode in a repository via `.dir-locals.el`.  Example:

    ((nil . ((autosync-git-commit-message . "My commit message")
             (autosync-git-pull-timer . 300)
             (autosync-git-pull-style . rebase) ; optionally
             (mode . autosync-git))))

This activates `autosync-git-mode` in any file visited under the directory
containing the `.dir-locals.el`.  The mode installs a background pull timer
and a debounced after-save push, so files saved in the repository are pushed
shortly after, and remote changes are pulled periodically.

See each variable's docstring for tuning.

### Defensive programatic activation

`autosync-git-mode` will always activate when invoked interactively, but will
refuse to activate unless a `.dir-locals.el` (or `.dir-locals-2.el`) in or
above the buffer's directory contains `(mode . autosync-git)`.  This guards
against tooling that misapplies dir-locals across unrelated buffers, which
has been observed to silently trigger automatic git operations on the wrong
repository.  Set `autosync-git-skip-dir-locals-check` to `t` to bypass this
when activating the mode programmatically without `.dir-locals.el`.

### Installation


With `straight.el` and `use-package.el`, add this to your `~/.emacs.d/init.el`:

    (use-package autosync-git
      :straight (:host github
                 :repo "sbougerel/autosync-git"
                 :files ("*.el")))

And restart Emacs.  If you're using Doom Emacs, add this to your
`~/.doom.d/packages.el`:

    (package! autosync-git
      :recipe (:host github
               :repo "sbougerel/autosync-git"
               :files ("*.el")))

Then add the following to `~/.doom.d/config.el`:

    (use-package! autosync-git)

Then run `doom sync` to install it.

A MELPA submission is planned for the future.

### Change Log


1.0.0 - Renamed from autosync-magit; dropped the magit dependency.

The package is now `autosync-git` and calls `git` directly via `process-file`
(sync) and `make-process` (async).  This is a breaking change: the package
name, file name, and every `autosync-magit-*` identifier are renamed to
`autosync-git-*`.

New commands: `autosync-git-status` and `autosync-git-sync`.

New pull strategy.  `autosync-git-pull` uses `git merge-tree` to probe for
conflicts before changing the working tree.  When divergent branches would
merge cleanly, the operation runs (rebase by default, configurable via
`autosync-git-pull-style`).  When the probe predicts conflicts, the working
tree is left untouched.  A prefix arg skips the probe and runs the operation
unconditionally.

Defensive activation.  `autosync-git-mode` now refuses to activate unless
`.dir-locals.el` explicitly claims the mode, guarding against tooling that
misapplies dir-locals across buffers.  Override with
`autosync-git-skip-dir-locals-check`.

Variable rename: `autosync-magit-after-merge-hook` is now
`autosync-git-after-pull-hook`.  The `autosync-git-after-merge-hook` symbol
remains as an obsolete alias.

0.5.0 - Fixed a bug, added several improvements.

Removed the installed find-file-hook, thereby fixing an issue with other
repositories being synced when it is unwanted.

Removed the redundant variable `autosync-git-pull-when-visiting`: pulling now
simply occurs whenever a file is visited and `autosync-git-mode` is active
for the file.  Keeping this variable has no effect.

Eliminated timers when more than one timer exists for the same repository.

Don't run hooks when the merge fails, and informs the user.

0.4.0 - Introduces a background timer for periodic pull.

This is superior to the previous pull-on-events model, which does not work
fast enough in a variety of use cases.  Add
`autosync-git-pull-when-visiting` and `autosync-git-pull-timer` for
background periodic pull.  Users are advised to switch from setting
`autosync-git-pull-interval` to setting `autosync-git-pull-timer` in
directory-local variables.  Additionally, the deprecated variable
`autosync-git-dirs` was removed.  For users that wish to start
synchronisation as soon as Emacs starts, they may simply visit the directory
in a temporary buffer during initialisation.

0.3.0 - Merges are synchronous, all other operations are asynchronous.

This prevents possible concurrency issues with `find-file-hook` functions.

0.2.0 - Use per-directory local variables.

Deprecation of `autosync-git-dirs` in favor of `.dir-locals.el`.

0.1.0 - initial release



### Customization Documentation

#### `autosync-git-pull-interval`

Minimum seconds between two pull attempts in the same repository.

Throttles pulls triggered by buffer visits and by the background timer
so that they never run closer than this interval apart.

#### `autosync-git-pull-timer`

Period in seconds of the background pull timer.

The timer is started when `autosync-git-mode` first activates in a
repository and runs as long as Emacs is alive.  Set this in
`.dir-locals.el` so each repository can have its own cadence; the value
is copied into a per-repository setting on activation, and later mode
activations in the same repository update that value.

#### `autosync-git-push-debounce`

Seconds to wait after a buffer save before pushing to the remote.

Multiple saves within this window collapse into a single push.
Set this in `.dir-locals.el` for per-repository tuning.

#### `autosync-git-commit-message`

Commit message used by `autosync-git-push` and the after-save push.

May be set buffer-locally for per-file customization.  When several
saves coalesce within `autosync-git-push-debounce`, only the
buffer-local value from the first save is used.

#### `autosync-git-after-pull-hook`

Hook run after `autosync-git-pull` successfully updates the local branch.

The hook does not run when the pull is a no-op (already in sync, or
local is ahead) or when it fails (conflict, missing upstream).

#### `autosync-git-pull-style`

Strategy used by `autosync-git-pull` when local and upstream have diverged.

When the local and upstream branches have diverged but the merge
of the two would not produce conflicts (as predicted by
`git merge-tree'), `autosync-git-pull` will:

- `rebase` (default): rebase local commits onto @{upstream}.  History
  stays linear; commits get new SHAs.  Best for personal-sync
  repositories where commits are auto-generated snapshots and linear
  history is preferable.

- `merge`: create a merge commit joining the two branches.  Preserves
  original commit SHAs.

When the probe predicts a conflict, the operation is refused and the
working tree is left untouched.  Use a prefix arg with
`autosync-git-pull` to skip the probe and run the operation
unconditionally (which may leave a REBASE or MERGING state).

#### `autosync-git-skip-dir-locals-check`

When non-nil, do not verify that `.dir-locals.el` claims this mode.

By default, `autosync-git-mode` refuses to activate from
`.dir-locals.el` unless that file (or `.dir-locals-2.el` in or above the
buffer's directory) contains `(mode . autosync-git)'.  This is a
defensive measure against tooling that misapplies dir-locals across
unrelated buffers.

Interactive activation (\[autosync-git-mode]) bypasses the check
unconditionally, so you only need this variable when activating the mode
programmatically from elisp code (e.g. from your init file) without
`.dir-locals.el`.

### Function and Macro Documentation

#### `(autosync-git-pull PATH &optional FORCE)`

Fetch and update the local branch of repository at PATH.
By default, the local branch is updated only when it can be done without
conflicts.  The exact operation is selected by
`autosync-git-pull-style` (`rebase` or `merge`).  Behaviour by ancestry
of HEAD vs @{upstream}:
- in-sync, ahead, no-upstream: no-op (with a message for missing
  upstream).
- behind: fast-forward.
- diverged: probe with `git merge-tree'; only proceed if clean.
With prefix arg FORCE, skip the conflict probe and run the configured
operation regardless.  This may leave the working tree in REBASE or
MERGING state for manual resolution.
`autosync-git-after-pull-hook` runs only when the local branch
actually changed.

#### `(autosync-git-status PATH)`

Display a one-line status summary for the repository at PATH.
Reports working-tree state (clean/dirty), ahead/behind counts vs
upstream, and any unmerged paths.

#### `(autosync-git-sync PATH &optional FORCE)`

Synchronize the repository at PATH: pull, then push.
Runs `autosync-git-pull` with FORCE and, on completion, pushes when the
pull leaves the local branch in a clean state vs the remote (i.e. the
pull result is `updated` or `unchanged`).  Pulls that are refused,
conflicted, or failed do not trigger a push attempt, since `git push'
would be rejected as non-fast-forward.

#### `(autosync-git-push PATH MESSAGE)`

Create a commit with MESSAGE and push the repository at PATH.
Stages all changes, commits with MESSAGE, and pushes if HEAD has moved
past @{push}.  All git invocations run asynchronously.

-----
<div style="padding-top:15px;color: #d0d0d0;">
Markdown README file generated by
<a href="https://github.com/mgalgs/make-readme-markdown">make-readme-markdown.el</a>
</div>
