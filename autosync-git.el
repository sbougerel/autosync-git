;;; autosync-git.el --- Automatically synchronize a git repository with its upstream -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Sylvain Bougerel

;; Author: Sylvain Bougerel <sylvain.bougerel.devel@gmail.com>
;; Maintainer: Sylvain Bougerel <sylvain.bougerel.devel@gmail.com>
;; Version: 1.0.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: convenience tools git
;; URL: https://github.com/sbougerel/autosync-git

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; [![CI Result](https://github.com/sbougerel/autosync-git/actions/workflows/makefile.yml/badge.svg)](https://github.com/sbougerel/autosync-git/actions)
;;
;; Autosync-Git automatically synchronizes a local git repository branch with
;; its upstream by invoking `git' directly.  It targets the narrow use case of
;; keeping a *personal* repository in sync between devices: private notes,
;; configuration backups, or any single-author "save the current state to the
;; cloud" workflow.  Autosync-Git is NOT suitable for team workflows; do not use
;; it on shared branches.
;;
;; The entry point is `autosync-git-mode', a buffer-local minor mode that
;; installs a periodic background pull and a debounced after-save push for the
;; buffer's repository.  It is normally turned on via `.dir-locals.el' (see
;; Configuration below) so that visiting any file under a sync'd repository
;; activates the automation.
;;
;; The four interactive commands below can also be invoked manually,
;; independently of the mode:
;;
;;     M-x autosync-git-pull      Fetch and update the local branch.
;;     M-x autosync-git-push      Stage all changes, commit, and push.
;;     M-x autosync-git-status    One-line summary (clean/dirty, ahead/behind).
;;     M-x autosync-git-sync      Pull, then push.
;;
;; ### Pull strategy
;;
;; Autosync-git tries its best to pull from upstream without disturbing your
;; current work.  `autosync-git-pull' uses a probe-then-rebase strategy:
;;
;; 1. Fetch from upstream.
;; 2. Compare HEAD to @{upstream}.  In-sync or ahead: nothing to do.
;;    Behind: fast-forward (conflict-free).  Diverged: probe before acting.
;; 3. The probe uses `git merge-tree` to perform a 3-way merge in memory
;;    without touching the working tree.  If the probe is conflict-free,
;;    the configured operation (rebase or merge) runs.  Otherwise the
;;    operation is cancelled and the working tree is left untouched.
;;
;; The default operation is rebase, controlled by `autosync-git-pull-style'; set
;; it to `merge' to create a merge commit instead.  Rebase is the default
;; because personal-sync commits are auto-generated snapshots, where preserving
;; original SHAs matters less than keeping history linear.
;;
;; A prefix arg (`C-u M-x autosync-git-pull`) skips the probe and runs the
;; configured operation regardless, which may leave the working tree in REBASE
;; or MERGING state for manual resolution.
;;
;; Note: `git merge-tree --write-tree` requires git 2.38 or newer.  On older git
;; versions the probe always reports a conflict and the pull falls back to
;; refusing -- failing closed.  Use `C-u' or upgrade git.
;;
;; ### Configuration
;;
;; Activate the mode in a repository via `.dir-locals.el'.  Example:
;;
;;     ((nil . ((autosync-git-commit-message . "My commit message")
;;              (autosync-git-pull-timer . 300)
;;              (autosync-git-pull-style . rebase) ; optionally
;;              (mode . autosync-git))))
;;
;; This activates `autosync-git-mode' in any file visited under the directory
;; containing the `.dir-locals.el'.  The mode installs a background pull timer
;; and a debounced after-save push, so files saved in the repository are pushed
;; shortly after, and remote changes are pulled periodically.
;;
;; See each variable's docstring for tuning.
;;
;; ### Defensive programatic activation
;;
;; `autosync-git-mode' will always activate when invoked interactively, but will
;; refuse to activate unless a `.dir-locals.el' (or `.dir-locals-2.el') in or
;; above the buffer's directory contains `(mode . autosync-git)`.  This guards
;; against tooling that misapplies dir-locals across unrelated buffers, which
;; has been observed to silently trigger automatic git operations on the wrong
;; repository.  Set `autosync-git-skip-dir-locals-check' to `t' to bypass this
;; when activating the mode programmatically without `.dir-locals.el'.

;;; Installation:
;;
;; With `straight.el' and `use-package.el', add this to your `~/.emacs.d/init.el':
;;
;;     (use-package autosync-git
;;       :straight (:host github
;;                  :repo "sbougerel/autosync-git"
;;                  :files ("*.el")))
;;
;; And restart Emacs.  If you're using Doom Emacs, add this to your
;; `~/.doom.d/packages.el':
;;
;;     (package! autosync-git
;;       :recipe (:host github
;;                :repo "sbougerel/autosync-git"
;;                :files ("*.el")))
;;
;; Then add the following to `~/.doom.d/config.el':
;;
;;     (use-package! autosync-git)
;;
;; Then run `doom sync` to install it.
;;
;; A MELPA submission is planned for the future.

;;; Change Log:
;;
;; 1.0.0 - Renamed from autosync-magit; dropped the magit dependency.
;;
;; The package is now `autosync-git' and calls `git' directly via `process-file'
;; (sync) and `make-process' (async).  This is a breaking change: the package
;; name, file name, and every `autosync-magit-*' identifier are renamed to
;; `autosync-git-*'.
;;
;; New commands: `autosync-git-status' and `autosync-git-sync'.
;;
;; New pull strategy.  `autosync-git-pull' uses `git merge-tree` to probe for
;; conflicts before changing the working tree.  When divergent branches would
;; merge cleanly, the operation runs (rebase by default, configurable via
;; `autosync-git-pull-style').  When the probe predicts conflicts, the working
;; tree is left untouched.  A prefix arg skips the probe and runs the operation
;; unconditionally.
;;
;; Defensive activation.  `autosync-git-mode' now refuses to activate
;; programmatically unless `.dir-locals.el' explicitly claims the mode, guarding
;; against tooling that misapplies dir-locals across buffers.  Override with
;; `autosync-git-skip-dir-locals-check'.
;;
;; Rename.  `autosync-magit-*' mode and variables are now `autosync-git-*'.
;; `autosync-magit-*' symbols remains as aliases; this makes `autosync-git'
;; conflict with `autosync-magit'.
;;
;; 0.5.0 - Fixed a bug, added several improvements.
;;
;; Removed the installed find-file-hook, thereby fixing an issue with other
;; repositories being synced when it is unwanted.
;;
;; Removed the redundant variable `autosync-git-pull-when-visiting': pulling now
;; simply occurs whenever a file is visited and `autosync-git-mode' is active
;; for the file.  Keeping this variable has no effect.
;;
;; Eliminated timers when more than one timer exists for the same repository.
;;
;; Don't run hooks when the merge fails, and informs the user.
;;
;; 0.4.0 - Introduces a background timer for periodic pull.
;;
;; This is superior to the previous pull-on-events model, which does not work
;; fast enough in a variety of use cases.  Add
;; `autosync-git-pull-when-visiting' and `autosync-git-pull-timer' for
;; background periodic pull.  Users are advised to switch from setting
;; `autosync-git-pull-interval' to setting `autosync-git-pull-timer' in
;; directory-local variables.  Additionally, the deprecated variable
;; `autosync-git-dirs' was removed.  For users that wish to start
;; synchronisation as soon as Emacs starts, they may simply visit the directory
;; in a temporary buffer during initialisation.
;;
;; 0.3.0 - Merges are synchronous, all other operations are asynchronous.
;;
;; This prevents possible concurrency issues with `find-file-hook' functions.
;;
;; 0.2.0 - Use per-directory local variables.
;;
;; Deprecation of `autosync-git-dirs' in favor of `.dir-locals.el'.
;;
;; 0.1.0 - initial release

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; Definitions:
(defgroup autosync-git nil
  "Automatically synchronize a git repository with its upstream."
  :group 'tools)

;;;###autoload
(define-obsolete-variable-alias
  'autosync-magit-pull-interval
  'autosync-git-pull-interval
  "1.0.0")

;;;###autoload(put 'autosync-git-pull-interval 'safe-local-variable 'integerp)
(defcustom autosync-git-pull-interval 10
  "Minimum seconds between two pull attempts in the same repository.

Throttles pulls triggered by buffer visits and by the background timer
so that they never run closer than this interval apart."
  :type 'integer
  :group 'autosync-git
  :package-version '(autosync-git . "0.1.0"))

;;;###autoload
(define-obsolete-variable-alias
  'autosync-magit-pull-timer
  'autosync-git-pull-timer
  "1.0.0")

;;;###autoload(put 'autosync-git-pull-timer 'safe-local-variable 'integerp)
(defcustom autosync-git-pull-timer 300
  "Period in seconds of the background pull timer.

The timer is started when `autosync-git-mode' first activates in a
repository and runs as long as Emacs is alive.  Set this in
`.dir-locals.el' so each repository can have its own cadence; the value
is copied into a per-repository setting on activation, and later mode
activations in the same repository update that value."
  :type 'integer
  :group 'autosync-git
  :package-version '(autosync-git . "0.4.0"))

;;;###autoload
(define-obsolete-variable-alias
  'autosync-magit-pull-debounce
  'autosync-git-pull-debounce
  "1.0.0")

;;;###autoload(put 'autosync-git-push-debounce 'safe-local-variable 'integerp)
(defcustom autosync-git-push-debounce 5
  "Seconds to wait after a buffer save before pushing to the remote.

Multiple saves within this window collapse into a single push.
Set this in `.dir-locals.el' for per-repository tuning."
  :type 'integer
  :group 'autosync-git
  :package-version '(autosync-git . "0.1.0"))

;;;###autoload
(define-obsolete-variable-alias
  'autosync-magit-commit-message
  'autosync-git-commit-message
  "1.0.0")

;;;###autoload(put 'autosync-git-commit-message 'safe-local-variable 'stringp)
(defcustom autosync-git-commit-message "Automated commit by autosync-git"
  "Commit message used by `autosync-git-push' and the after-save push.

May be set buffer-locally for per-file customization.  When several
saves coalesce within `autosync-git-push-debounce', only the
buffer-local value from the first save is used."
  :type 'string
  :group 'autosync-git
  :package-version '(autosync-git . "0.1.0"))

(define-obsolete-variable-alias
  'autosync-magit-after-merge-hook
  'autosync-git-after-pull-hook
  "1.0.0")

(defcustom autosync-git-after-pull-hook nil
  "Hook run after `autosync-git-pull' successfully updates the local branch.

The hook does not run when the pull is a no-op (already in sync, or
local is ahead) or when it fails (conflict, missing upstream)."
  :type 'hook
  :group 'autosync-git
  :package-version '(autosync-git . "1.0.0"))

;;;###autoload(put 'autosync-git-pull-style 'safe-local-variable 'symbolp)
(defcustom autosync-git-pull-style 'rebase
  "Strategy used by `autosync-git-pull' when local and upstream have diverged.

When the local and upstream branches have diverged but the merge
of the two would not produce conflicts (as predicted by
`git merge-tree'), `autosync-git-pull' will:

- `rebase' (default): rebase local commits onto @{upstream}.  History
  stays linear; commits get new SHAs.  Best for personal-sync
  repositories where commits are auto-generated snapshots and linear
  history is preferable.

- `merge': create a merge commit joining the two branches.  Preserves
  original commit SHAs.

When the probe predicts a conflict, the operation is refused and the
working tree is left untouched.  Use a prefix arg with
`autosync-git-pull' to skip the probe and run the operation
unconditionally (which may leave a REBASE or MERGING state)."
  :type '(choice (const :tag "Rebase onto upstream" rebase)
          (const :tag "Merge upstream into local" merge))
  :group 'autosync-git
  :package-version '(autosync-git . "1.0.0"))

(defcustom autosync-git-skip-dir-locals-check nil
  "When non-nil, do not verify that `.dir-locals.el' claims this mode.

By default, `autosync-git-mode' refuses to activate from
`.dir-locals.el' unless that file (or `.dir-locals-2.el' in or above the
buffer's directory) contains `(mode . autosync-git)'.  This is a
defensive measure against tooling that misapplies dir-locals across
unrelated buffers.

Interactive activation (\\[autosync-git-mode]) bypasses the check
unconditionally, so you only need this variable when activating the mode
programmatically from elisp code (e.g. from your init file) without
`.dir-locals.el'."
  :type 'boolean
  :group 'autosync-git
  :package-version '(autosync-git . "1.0.0"))

(cl-defstruct (autosync-git--sync
               (:constructor autosync-git--sync-create)
               (:copier nil))
  "A synchronisation object for a directory.

Stores timing about the pull and push operations."
  last-pull next-push timer)

(defvar autosync-git--sync-alist ()
  "Alist mapping REPO-DIR to its `autosync-git--sync' state object.

Populated when `autosync-git-mode' activates in a repository for
the first time.  Do not modify directly.")

;; Process layer:
;;
;; Two thin wrappers around `process-file' (synchronous) and `make-process'
;; (asynchronous).  Both take REPO-DIR explicitly and rely on
;; `default-directory' binding rather than the buffer's; this keeps every
;; invocation free of buffer-local side effects.

(defun autosync-git--process-buffer (repo-dir)
  "Return the diagnostic process buffer for REPO-DIR, creating it if needed."
  (get-buffer-create (format "*autosync-git: %s*" repo-dir)))

(defun autosync-git--call (repo-dir &rest args)
  "Run \"git ARGS\" synchronously in REPO-DIR.
Return a cons (EXIT-CODE . OUTPUT) where OUTPUT is trimmed stdout."
  (with-temp-buffer
    (let* ((default-directory (file-name-as-directory repo-dir))
           (exit (apply #'process-file "git" nil t nil args)))
      (cons exit (string-trim (buffer-string))))))

(defun autosync-git--call-async (repo-dir done &rest args)
  "Run \"git ARGS\" asynchronously in REPO-DIR.
Call DONE with the integer exit code when the process terminates.
Return the process object."
  (let* ((default-directory (file-name-as-directory repo-dir))
         (proc (apply #'start-file-process
                      "autosync-git"
                      (autosync-git--process-buffer repo-dir)
                      "git" args)))
    (set-process-sentinel
     proc
     (lambda (p _event)
       (when (memq (process-status p) '(exit signal))
         (funcall done (process-exit-status p)))))
    proc))

(defun autosync-git--toplevel (&optional path)
  "Return the toplevel of the git repository containing PATH, or nil.
PATH defaults to `default-directory'."
  (let ((result (autosync-git--call (or path default-directory)
                                    "rev-parse" "--show-toplevel")))
    (when (zerop (car result))
      (file-name-as-directory (cdr result)))))

(defun autosync-git--upstream-ancestry (repo-dir)
  "Return the ancestry between HEAD and @{upstream} in REPO-DIR.
One of: `in-sync', `behind', `ahead', `diverged', `no-upstream'."
  (if (not (zerop (car (autosync-git--call
                        repo-dir "rev-parse" "--verify" "--quiet" "@{upstream}"))))
      'no-upstream
    (let ((head-anc-up (zerop (car (autosync-git--call
                                    repo-dir "merge-base" "--is-ancestor"
                                    "HEAD" "@{upstream}"))))
          (up-anc-head (zerop (car (autosync-git--call
                                    repo-dir "merge-base" "--is-ancestor"
                                    "@{upstream}" "HEAD")))))
      (cond ((and head-anc-up up-anc-head) 'in-sync)
            (head-anc-up 'behind)
            (up-anc-head 'ahead)
            (t 'diverged)))))

(defun autosync-git--unmerged-p (repo-dir)
  "Return non-nil if there are unmerged paths in REPO-DIR."
  (not (string-empty-p
        (cdr (autosync-git--call repo-dir
                                 "diff" "--name-only" "--diff-filter=U")))))

(defun autosync-git--needs-push-p (repo-dir)
  "Return non-nil if HEAD differs from @{push} in REPO-DIR.
Return nil when @{push} is undefined or already at HEAD."
  (let ((push (autosync-git--call repo-dir
                                  "rev-parse" "--verify" "--quiet" "@{push}"))
        (head (autosync-git--call repo-dir
                                  "rev-parse" "--verify" "--quiet" "HEAD")))
    (and (zerop (car push))
         (zerop (car head))
         (not (string= (cdr push) (cdr head))))))

(defun autosync-git--probe-clean-p (repo-dir)
  "Return non-nil if HEAD merges cleanly with @{upstream} in REPO-DIR.

Uses `git merge-tree --write-tree' to predict conflicts without touching
the worktree.  Requires git 2.38 or newer.  On older git versions the
probe will report a conflict (exit non-zero) and `autosync-git-pull'
will refuse to act, which fails closed."
  (zerop (car (autosync-git--call repo-dir
                                  "merge-tree" "--write-tree"
                                  "HEAD" "@{upstream}"))))

(defun autosync-git--ahead-behind (repo-dir)
  "Return (AHEAD . BEHIND) commit counts vs @{upstream} for REPO-DIR.
Both values are integers.  Returns nil if @{upstream} is unset."
  (let ((result (autosync-git--call repo-dir
                                    "rev-list" "--left-right" "--count"
                                    "HEAD...@{upstream}")))
    (when (zerop (car result))
      (let ((parts (split-string (cdr result) "[ \t]+" t)))
        (cons (string-to-number (car parts))
              (string-to-number (cadr parts)))))))

(defun autosync-git--dirty-p (repo-dir)
  "Return non-nil if REPO-DIR has any uncommitted change."
  (not (string-empty-p
        (cdr (autosync-git--call repo-dir "status" "--porcelain")))))

;; Dir-locals guard:

(defun autosync-git--alist-claims-mode-p (alist)
  "Return non-nil if dir-locals ALIST contain (mode . autosync-git) anywhere."
  (cl-some (lambda (entry)
             (let ((vars (cdr-safe entry)))
               (and (listp vars)
                    (cl-some (lambda (pair)
                               (and (consp pair)
                                    (eq (car pair) 'mode)
                                    (eq (cdr pair) 'autosync-git)))
                             vars))))
           alist))

(defun autosync-git--dir-locals-claims-mode-p (&optional file)
  "Return non-nil if a dir-locals file for FILE claims `autosync-git-mode'.

Walks up from FILE (defaulting to `default-directory') looking for
`.dir-locals.el' and `.dir-locals-2.el', reads each, and checks whether
any selector's variable alist contains
`(mode . autosync-git)'.

Used as a defensive check before activating the minor mode, so that
buffers visited via tooling that mishandles dir-locals do not
accidentally trigger automatic git operations."
  (let ((dir (file-name-directory
              (expand-file-name (or file default-directory))))
        (claims nil))
    (dolist (basename '(".dir-locals.el" ".dir-locals-2.el"))
      (when-let* ((dl (locate-dominating-file dir basename))
                  (path (expand-file-name basename dl))
                  ((file-readable-p path))
                  (alist (with-temp-buffer
                           (insert-file-contents path)
                           (condition-case nil
                               (read (current-buffer))
                             (error nil)))))
        (when (autosync-git--alist-claims-mode-p alist)
          (setq claims t))))
    claims))

;; Operations:

;;;###autoload
(defun autosync-git-pull (path &optional force)
  "Fetch and update the local branch of repository at PATH.

By default, the local branch is updated only when it can be done without
conflicts.  The exact operation is selected by
`autosync-git-pull-style' (`rebase' or `merge').  Behaviour by ancestry
of HEAD vs @{upstream}:

- in-sync, ahead, no-upstream: no-op (with a message for missing
  upstream).
- behind: fast-forward.
- diverged: probe with `git merge-tree'; only proceed if clean.

With prefix arg FORCE, skip the conflict probe and run the configured
operation regardless.  This may leave the working tree in REBASE or
MERGING state for manual resolution.

`autosync-git-after-pull-hook' runs only when the local branch
actually changed."
  (interactive "D\nP")
  (autosync-git--pull-impl path force nil))

(defun autosync-git--pull-impl (path force after)
  "Execute pull for PATH; call AFTER with a result symbol on completion.

FORCE has the same meaning as in `autosync-git-pull'.  AFTER, if
non-nil, is a function of one argument and is invoked with one of:

- `updated'    local moved forward (fast-forward, rebase, or merge).
- `unchanged'  pull was a no-op (in-sync or already ahead).
- `refused'    diverged from upstream and the probe predicted a
               conflict; worktree was left untouched.
- `conflicted' ran with FORCE and left a conflict in the worktree
               for manual resolution.
- `failed'     missing repository or upstream, or git failed
               unexpectedly."
  (let ((repo-dir (autosync-git--toplevel path)))
    (if (not repo-dir)
        (progn
          (message "Autosync-Git: \"%s\" is not a path to a git repository" path)
          (when after (funcall after 'failed)))
      (when-let ((sync (cdr (assoc repo-dir autosync-git--sync-alist))))
        (setf (autosync-git--sync-last-pull sync) (current-time)))
      (autosync-git--call-async
       repo-dir
       (lambda (_)
         (let ((result (autosync-git--apply-pull repo-dir force)))
           (when after (funcall after result))))
       "fetch"))))

(defun autosync-git--apply-pull (repo-dir force)
  "Apply the pull operation to REPO-DIR after fetch has completed.
Return a result symbol; see `autosync-git--pull-impl' for the list of
possible values.  FORCE has the same meaning as in `autosync-git-pull'."
  (pcase (autosync-git--upstream-ancestry repo-dir)
    ((or 'in-sync 'ahead) 'unchanged)
    ('behind
     (autosync-git--run-fast-forward repo-dir))
    ('diverged
     (autosync-git--run-diverged repo-dir force))
    ('no-upstream
     (message "Autosync-Git: \"%s\" has no upstream configured" repo-dir)
     'failed)))

(defun autosync-git--run-fast-forward (repo-dir)
  "Fast-forward HEAD to @{upstream} in REPO-DIR.
Run `autosync-git-after-pull-hook' on success.  Return `updated'
on success or `failed' otherwise."
  (let ((exit (car (autosync-git--call repo-dir "merge" "--ff-only"))))
    (cond
     ((zerop exit)
      (message "Autosync-Git: pulled \"%s\" (fast-forward)" repo-dir)
      (run-hooks 'autosync-git-after-pull-hook)
      'updated)
     (t
      (message "Autosync-Git: Fast-forward failed in \"%s\"" repo-dir)
      'failed))))

(defun autosync-git--run-diverged (repo-dir force)
  "Reconcile diverged HEAD and @{upstream} in REPO-DIR.
Without FORCE, refuse to act when the probe predicts conflicts.  Return
one of `updated', `refused', `conflicted', or `failed'."
  (if (and (not force) (not (autosync-git--probe-clean-p repo-dir)))
      (progn
        (message "Autosync-Git: \"%s\" would conflict with upstream; \
worktree left untouched (use C-u to force)" repo-dir)
        'refused)
    (autosync-git--run-pull-op repo-dir force)))

(defun autosync-git--run-pull-op (repo-dir force)
  "Run the configured pull operation in REPO-DIR.
On clean exit, run `autosync-git-after-pull-hook' and return `updated'.
On conflict without FORCE, abort the operation so the worktree stays
clean and return `refused'.  With FORCE, leave the conflict in the
worktree and return `conflicted'.  Other non-zero exits return `failed'."
  (let* ((style autosync-git-pull-style)
         (cmd (pcase style
                ('rebase (list "rebase" "@{upstream}"))
                ('merge  (list "merge"))
                (_ (error "Invalid `autosync-git-pull-style': %S" style))))
         (exit (car (apply #'autosync-git--call repo-dir cmd))))
    (cond
     ((zerop exit)
      (message "Autosync-Git: pulled \"%s\" (%s)" repo-dir style)
      (run-hooks 'autosync-git-after-pull-hook)
      'updated)
     ((autosync-git--unmerged-p repo-dir)
      (cond
       (force
        (message "Autosync-Git: Conflict in \"%s\" - resolve manually" repo-dir)
        'conflicted)
       (t
        (autosync-git--abort-pull-op repo-dir style)
        (message "Autosync-Git: Conflict in \"%s\" - aborted, worktree restored"
                 repo-dir)
        'refused)))
     (t
      (message "Autosync-Git: %s failed in \"%s\"" style repo-dir)
      'failed))))

(defun autosync-git--abort-pull-op (repo-dir style)
  "Abort an in-progress STYLE operation in REPO-DIR."
  (autosync-git--call repo-dir
                      (pcase style
                        ('rebase "rebase")
                        ('merge  "merge"))
                      "--abort"))

;;;###autoload
(defun autosync-git-status (path)
  "Display a one-line status summary for the repository at PATH.

Reports working-tree state (clean/dirty), ahead/behind counts vs
upstream, and any unmerged paths."
  (interactive "D")
  (let ((repo-dir (autosync-git--toplevel path)))
    (if (not repo-dir)
        (message "Autosync-Git: \"%s\" is not a path to a git repository" path)
      (message "Autosync-Git: %s" (autosync-git--status-string repo-dir)))))

(defun autosync-git--status-string (repo-dir)
  "Build a one-line status summary for REPO-DIR."
  (let* ((ancestry (autosync-git--upstream-ancestry repo-dir))
         (counts (when (memq ancestry '(behind ahead diverged))
                   (autosync-git--ahead-behind repo-dir)))
         (parts (list repo-dir
                      (if (autosync-git--dirty-p repo-dir) "dirty" "clean")
                      (pcase ancestry
                        ('in-sync     "in sync")
                        ('no-upstream "no upstream")
                        ('behind      (format "behind %d" (cdr counts)))
                        ('ahead       (format "ahead %d" (car counts)))
                        ('diverged    (format "diverged: ahead %d, behind %d"
                                              (car counts) (cdr counts))))
                      (when (autosync-git--unmerged-p repo-dir) "unmerged paths"))))
    (mapconcat #'identity (delq nil parts) ", ")))

;;;###autoload
(defun autosync-git-sync (path &optional force)
  "Synchronize the repository at PATH: pull, then push.

Runs `autosync-git-pull' with FORCE and, on completion, pushes when the
pull leaves the local branch in a clean state vs the remote (i.e. the
pull result is `updated' or `unchanged').  Pulls that are refused,
conflicted, or failed do not trigger a push attempt, since `git push'
would be rejected as non-fast-forward."
  (interactive "D\nP")
  (let ((repo-dir (autosync-git--toplevel path)))
    (if (not repo-dir)
        (message "Autosync-Git: \"%s\" is not a path to a git repository" path)
      (autosync-git--pull-impl
       repo-dir force
       (lambda (result)
         (when (and (memq result '(updated unchanged))
                    (autosync-git--needs-push-p repo-dir))
           (autosync-git-push repo-dir
                              (or autosync-git-commit-message
                                  (default-value 'autosync-git-commit-message)))))))))

;;;###autoload
(defun autosync-git-push (path message)
  "Create a commit with MESSAGE and push the repository at PATH.

Stages all changes, commits with MESSAGE, and pushes if HEAD has moved
past @{push}.  All git invocations run asynchronously."
  (interactive "D\nMCommit message: ")
  (let ((repo-dir (autosync-git--toplevel path)))
    (if (not repo-dir)
        (message "Autosync-Git: \"%s\" is not a path to a git repository" path)
      (autosync-git--call-async
       repo-dir
       (lambda (_)
         (autosync-git--call-async
          repo-dir
          (lambda (_)
            (when (autosync-git--needs-push-p repo-dir)
              (autosync-git--call-async
               repo-dir
               (lambda (_)
                 (message "Autosync-Git: pushed \"%s\"" path))
               "push")))
          "commit" "-a" "-m" message))
       "add" "-A"))))

(defun autosync-git--throttle-pull (repo-dir)
  "Pull REPO-DIR if `autosync-git-pull-interval' has elapsed since the last try.

Acts as the gate in front of every automatic pull (timer-driven or
visit-driven), so that a flurry of triggers cannot turn into a flurry of
git invocations."
  (when-let ((sync (cdr (assoc repo-dir autosync-git--sync-alist))))
    (when (time-less-p
           (time-add (autosync-git--sync-last-pull sync)
                     (seconds-to-time autosync-git-pull-interval))
           (current-time))
      (autosync-git-pull repo-dir))))

(defun autosync-git--pull-when-visiting (repo-dir)
  "Pull REPO-DIR (throttled) when visiting a real file buffer.

Skips non-file buffers like the minibuffer, which can otherwise trigger
a pull on every selection change."
  (when (buffer-file-name)
    (autosync-git--throttle-pull repo-dir)))

(defun autosync-git--timer-exists (repo-dir)
  "Return non-nil if `timer-list' has a pull timer for REPO-DIR.

Matches a timer whose function is `autosync-git--pull-on-timer'
and whose first argument equals REPO-DIR."
  (cl-some (lambda (timer)
             (and (eq (timer--function timer) #'autosync-git--pull-on-timer)
                  (equal (car (timer--args timer)) repo-dir)))
           timer-list))

(defun autosync-git--pull-on-timer (repo-dir)
  "Pull REPO-DIR from upstream and reschedule the next pull.

Recurring driver for the background timer started in
`autosync-git-mode'.  Skips rescheduling if another timer for REPO-DIR
already exists, so multiple buffers in the same repository never
multiply the timer count."
  (when-let ((time-triggered (current-time))
             (sync (cdr (assoc repo-dir autosync-git--sync-alist))))
    (autosync-git--throttle-pull repo-dir)
    ;; Evaluate if another timer for the same repository already exists, and if
    ;; that's the case, do not re-create the timer.
    (unless (autosync-git--timer-exists repo-dir)
      (run-with-timer (max 1 (- (autosync-git--sync-timer sync)
                                (floor (float-time (time-subtract nil time-triggered)))))
                      nil #'autosync-git--pull-on-timer repo-dir))))

(defun autosync-git--push-after-save (&optional _)
  "Push change upstream with a debounce."
  (let* ((repo-dir (autosync-git--toplevel))
         (sync (cdr (assoc repo-dir autosync-git--sync-alist))))
    (when (and sync
               (time-less-p
                (autosync-git--sync-next-push sync)
                (current-time)))
      (setf (autosync-git--sync-next-push sync)
            (time-add (current-time) autosync-git-push-debounce))
      (run-with-timer autosync-git-push-debounce nil
                      #'autosync-git-push
                      repo-dir autosync-git-commit-message))))

;;;###autoload
(define-obsolete-function-alias 'autosync-magit-mode 'autosync-git-mode "1.0.0")

;;;###autoload
(define-minor-mode autosync-git-mode
  "Automatically synchronize this repository with its upstream.

Activates a background pull timer and a debounced after-save push.
Intended to be turned on via `.dir-locals.el' in repositories you want
to keep in sync; example:

    ((nil . ((autosync-git-commit-message . \"My commit message\")
             (autosync-git-pull-timer . 300)
             (autosync-git-pull-style . rebase)
             (mode . autosync-git))))

When activated from `.dir-locals.el', the mode refuses to enable unless
that file explicitly claims it via `(mode . autosync-git)' \\=- a
defensive check against tooling that misapplies dir-locals across
buffers.  Interactive activation (\\[autosync-git-mode]) bypasses this
check.  See `autosync-git-skip-dir-locals-check' to also bypass for
non-interactive elisp callers."
  :init-value nil
  :global nil
  :lighter " ↕"
  :group 'autosync-git
  (if autosync-git-mode
      (let ((repo-dir (autosync-git--toplevel)))
        (cond
         ((not repo-dir)
          (autosync-git-mode -1))
         ((not (or autosync-git-skip-dir-locals-check
                   (eq this-command 'autosync-git-mode)
                   (autosync-git--dir-locals-claims-mode-p
                    (or buffer-file-name default-directory))))
          ;; Defensive: refuse activation when no `.dir-locals.el' in the
          ;; buffer's tree claims this mode.  Catches accidental activation via
          ;; tooling that mishandles dir-locals across buffers.  Interactive M-x
          ;; (which sets `this-command') and the skip variable both bypass this
          ;; guard.
          (autosync-git-mode -1))
         (t
          (let ((sync (cdr (assoc repo-dir autosync-git--sync-alist))))
            (if sync
                ;; Repo already visited: update timer local value and pull
                (progn
                  (setf (autosync-git--sync-timer sync)
                        autosync-git-pull-timer)
                  (autosync-git--pull-when-visiting repo-dir))
              ;; First file visited in repo: add to alist, launch timer to pull
              (push (cons repo-dir
                          (autosync-git--sync-create
                           :last-pull (seconds-to-time 0)
                           :next-push (seconds-to-time 0)
                           :timer autosync-git-pull-timer))
                    autosync-git--sync-alist)
              (autosync-git--pull-on-timer repo-dir)))
          (add-hook 'after-save-hook #'autosync-git--push-after-save nil t))))
    (remove-hook 'after-save-hook #'autosync-git--push-after-save t)))

(provide 'autosync-git)
;;; autosync-git.el ends here
