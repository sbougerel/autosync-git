;;; autosync-git.el --- Automatically synchronize a git repository with its upstream -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Sylvain Bougerel

;; Author: Sylvain Bougerel <sylvain.bougerel.devel@gmail.com>
;; Maintainer: Sylvain Bougerel <sylvain.bougerel.devel@gmail.com>
;; Version: 0.5.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: convenience tools git
;; URL: https://github.com/sbougerel/autosync-git

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation, either version 3 of the License, or (at your option) any later
;; version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.
;;
;; You should have received a copy of the GNU General Public License along with
;; this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; [![License GPLv3](https://img.shields.io/badge/license-GPL_v3-green.svg)](http://www.gnu.org/licenses/gpl-3.0.html)
;; [![CI Result](https://github.com/sbougerel/autosync-git/actions/workflows/makefile.yml/badge.svg)](https://github.com/sbougerel/autosync-git/actions)
;;
;; Autosync-Git provides a minor mode to automatically synchronize a local git
;; repository branch with its upstream by invoking `git' directly.  It is
;; intended to be used exceptionally: when git is used solely to synchronize
;; private content between devices or personal backups.  With this use case,
;; there is typically no need to create branches, and all changes can be pushed
;; to the remote as soon as they are committed.  The author created it to
;; synchronize their personal notes between different devices.
;;
;; Autosync-Git should never be used for other use cases and especially not
;; for team settings.
;;
;; To configure a repository to automatically synchronize, turn on
;; `autosync-git-mode' in a buffer, and set the package variables accordingly.
;; Settings can be made permanent by adding `.dir-locals.el' in repositories you
;; want to synchronize.  Example:
;;
;;     ((nil . ((autosync-git-commit-message . "My commit message")
;;              (autosync-git-pull-timer . 300)
;;              (mode . autosync-git))))
;;
;; The configuration above turns on the minor mode for any file visited in the
;; same directory as `.dir-locals.el' or in its sub-directories.  The
;; `autosync-git-commit-message' is used as the commit message for each
;; commit.  The `autosync-git-pull-timer' controls the period between
;; background pull attempts, in seconds.  See the documentation of each variable
;; for more details.

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
;; Then run `doom sync' to install it.

;;; Change Log:
;;
;; 0.5.0 - Fixed a bug, added several improvements.
;;
;; Removed the installed find-file-hook, thereby fixing an issue with other
;; repositories being synced when it is unwanted.
;;
;; Removed the redundant variable `autosync-git-pull-when-visiting': pulling
;; now simply occurs whenever a file is visited and `autosync-git-mode' is
;; active for the file.  Keeping this variable has no effect.
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

;;;###autoload(put 'autosync-git-pull-interval 'safe-local-variable 'integerp)
(defcustom autosync-git-pull-interval 10
  "Minimum interval between any pull attempts, in seconds.

`autosync-git' pulls updates either via a timer or when visiting a
file if `autosync-git-mode' is t for that buffer.

This variable sets the minimum interval between any two pull attempts,
it is always enforced.  This is to ensure that
`autosync-git--pull-on-timer' or `autosync-git--pull-when-visiting'
will never run too close to one another."
  :type 'integer
  :group 'autosync-git)

;;;###autoload(put 'autosync-git-pull-timer 'safe-local-variable 'integerp)
(defcustom autosync-git-pull-timer 300
  "Interval between background pull attempts, in seconds.

`autosync-git' start pulling updates from remotes periodically via a
background timer as soon as a buffer with `autosync-git-mode' visits a
file in a repository.  This variable sets or updates the period of the
background timer.

It is recommended to use directory-local variables (in `.dir-locals.el')
to set this variable value.  `autosync-git' keeps a single copy of
this value per repository.  When `autosync-git-mode' is turned on in a
buffer, the variable value is copied to the per-repository setting,
overriding any previous value."
  :type 'integer
  :group 'autosync-git)

;;;###autoload(put 'autosync-git-push-debounce 'safe-local-variable 'integerp)
(defcustom autosync-git-push-debounce 5
  "Default duration in seconds that must elapse before the next push.

When you save a buffer, wait for `autosync-git-push-debounce' to
elapse before pushing to the remote (again).  This ensures that multiple
file saves in a short period of time do not result in multiple pushes.

It is recommended to use directory-local variables (in `.dir-locals.el')
to set this variable value."
  :type 'integer
  :group 'autosync-git)

;;;###autoload(put 'autosync-git-commit-message 'safe-local-variable 'stringp)
(defcustom autosync-git-commit-message "Automated commit by autosync-git"
  "Commit message to use for each commit.

This variable is buffer-local.  Since the variable is buffer-local, and
commits & pushes are triggered from `write-file-functions', each file
can have its custom commit message.  *Caveat*: when multiple file saves
occur within `autosync-git-push-debounce', the commit message is the
buffer-local value of the first file saved."
  :type 'string
  :group 'autosync-git)

(defcustom autosync-git-after-merge-hook nil
  "Hook run after a merge is completed."
  :type 'hook
  :group 'autosync-git)

(cl-defstruct (autosync-git--sync
               (:constructor autosync-git--sync-create)
               (:copier nil))
  "A synchronisation object for a directory.

Stores timing about the pull and push operations."
  last-pull next-push timer)

(defvar autosync-git--sync-alist ()
  "Global alist of (REPO-DIR . OBJ): sync OBJ for each DIRS.

Do not modify this variable directly.  Visit files in buffers with
`autosync-git-mode' turned on or use `autosync-git-set' instead.")

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
  "Return non-nil if HEAD has commits that are not yet on @{push} in REPO-DIR.
Return nil when @{push} is undefined or already at HEAD."
  (let ((push-rev (autosync-git--call repo-dir "rev-parse" "--verify" "--quiet" "@{push}"))
        (head-rev (autosync-git--call repo-dir "rev-parse" "--verify" "--quiet" "HEAD")))
    (and (zerop (car push-rev))
         (zerop (car head-rev))
         (not (string= (cdr push-rev) (cdr head-rev))))))

;; Operations:

;;;###autoload
(defun autosync-git-pull (path)
  "Fetch and merge (if needed) the repository at PATH.

This interactive function is not throttled, it is executed as soon as it
called.  Merges are synchronous, to minimize possible conflicts with
files modified by Emacs in the repository."
  (interactive "D")
  (let ((repo-dir (autosync-git--toplevel path)))
    (if (not repo-dir)
        (message "Autosync-Git: \"%s\" is not a path to a git repository" path)
      (when-let ((sync (cdr (assoc repo-dir autosync-git--sync-alist))))
        (setf (autosync-git--sync-last-pull sync) (current-time)))
      (autosync-git--call-async
       repo-dir
       (lambda (_)
         (when (memq (autosync-git--upstream-ancestry repo-dir)
                     '(behind diverged))
           (let ((exit-code (car (autosync-git--call repo-dir "merge"))))
             (cond
              ((zerop exit-code)
               (run-hooks 'autosync-git-after-merge-hook))
              ((autosync-git--unmerged-p repo-dir)
               (message "Autosync-Git: Merge conflict in %s - please resolve manually" repo-dir))
              (t
               (message "Autosync-Git: Merge failed in %s" repo-dir))))))
       "fetch"))))

;;;###autoload
(defun autosync-git-push (path message)
  "Create a commit with MESSAGE and push the repository at PATH.

This interactive function is not debounced, it is executed
asynchronously, as soon as it called."
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
              (autosync-git--call-async repo-dir #'ignore "push")))
          "commit" "-a" "-m" message))
       "add" "-A"))))

(defun autosync-git--throttle-pull (repo-dir)
  "Pull change from upstream into REPO-DIR."
  (when-let ((sync (cdr (assoc repo-dir autosync-git--sync-alist))))
    (when (time-less-p
           (time-add (autosync-git--sync-last-pull sync)
                     (seconds-to-time autosync-git-pull-interval))
           (current-time))
      (autosync-git-pull repo-dir))))

(defun autosync-git--pull-when-visiting (repo-dir)
  "Pull upstream change when visiting a file in REPO-DIR."
  (when (buffer-file-name) ; avoid running on *minibuffer* when deselecting, e.g.
    (autosync-git--throttle-pull repo-dir)))

(defun autosync-git--timer-exists (repo-dir)
  "Inspect the list of timers and return t if a matching timer exists.

Check if `timer-list` contains a timer for the function
`autosync-git--pull-on-timer' with the argument REPO-DIR, and if it
does, returns t."
  (cl-some (lambda (timer)
             (and (eq (timer--function timer) #'autosync-git--pull-on-timer)
                  (equal (car (timer--args timer)) repo-dir)))
           timer-list))

(defun autosync-git--pull-on-timer (repo-dir)
  "Periodically pulls REPO-DIR from upstream, return the timer."
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
(define-minor-mode autosync-git-mode
  "Autosync-Git minor mode.

Turn on `autosync-git-mode' with `.dir-locals.el' in repositories you want to
synchronize; example:

    ((nil . ((autosync-git-commit-message . \"My commit message\")
             (autosync-git-pull-timer . 300)
             (mode . autosync-git))))

Customize these values to your liking."
  :init-value nil
  :global nil
  :lighter " ↕"
  :group 'autosync-git
  (if autosync-git-mode
      (let ((repo-dir (autosync-git--toplevel)))
        (if (not repo-dir)
            (autosync-git-mode -1)
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
          (add-hook 'after-save-hook #'autosync-git--push-after-save nil t)))
    (remove-hook 'after-save-hook #'autosync-git--push-after-save t)))

(provide 'autosync-git)
;;; autosync-git.el ends here
