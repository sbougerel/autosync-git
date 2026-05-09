;;; autosync-git-tests.el --- Tests for autosync-git -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2023 Sylvain Bougerel
;;

;; Author: Sylvain Bougerel <sylvain.bougerel.devel@gmail.com>
;; Maintainer: Sylvain Bougerel <sylvain.bougerel.devel@gmail.com>

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;;  Test 'autosync-git'.

;;; Code:

(require 'cl-lib)
(require 'ert)

(defun always-return (value)
  "Return VALUE always, regardless of its arguments."
  (lambda (&rest _) value))

(defun always-nil ()
  "Return nil always, alias of `always-return'."
  (always-return nil))

(defvar call-recorder nil
  "Record the arguments of the last call to `record-and-return'.")

(defun record-calls-and-return (value)
  "Return VALUE always, and record any call's arguments in LIST-VAR."
  (lambda (&rest args)
    (if (consp call-recorder)
        (setcdr (last call-recorder) (list args))
      (setq call-recorder (list args)))
    value))

(defun record-only-and-return (value expected)
  "Return VALUE always, record only EXPECTED."
  (lambda (&rest args)
    (if (member args expected)
        (if (consp call-recorder)
            (setcdr (last call-recorder) (list args))
          (setq call-recorder (list args))))
    value))

(defun record-rest-and-return (skip value)
  "Return VALUE; record argument tail after SKIP positions.
Lets a stub for a helper that takes a REPO-DIR (and possibly a
callback) record only the trailing git arguments, so the recorded
sequence matches the git command line that was issued."
  (lambda (&rest args)
    (let ((rest (nthcdr skip args)))
      (if (consp call-recorder)
          (setcdr (last call-recorder) (list rest))
        (setq call-recorder (list rest))))
    value))

(defun stub-call-async-success ()
  "Stub for `autosync-git--call-async' that records git args and succeeds.
Records the rest of args (after repo-dir and done callback) and
synchronously calls the done callback with exit code 0."
  (lambda (_repo done &rest git-args)
    (if (consp call-recorder)
        (setcdr (last call-recorder) (list git-args))
      (setq call-recorder (list git-args)))
    (funcall done 0)
    nil))

(require 'autosync-git)

;;;; Push:

(ert-deftest autosync-git-push--ahead ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--needs-push-p) (always-return t)))
    (autosync-git-push "/dir" "other message")
    (should
     (equal '(("add" "-A")
              ("commit" "-a" "-m" "other message")
              ("push"))
            call-recorder))))

(ert-deftest autosync-git-push--no-changes ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--needs-push-p) (always-nil)))
    (autosync-git-push "/dir" "other message")
    (should
     (equal '(("add" "-A")
              ("commit" "-a" "-m" "other message"))
            call-recorder))))

;;;; Pull:

(ert-deftest autosync-git-pull--behind-ff ()
  "Behind upstream: fast-forward, run after-pull-hook."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'behind))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-pull-hook)))))
    (autosync-git-pull "/dir")
    (should
     (equal '(("fetch")
              ("merge" "--ff-only")
              (autosync-git-after-pull-hook))
            call-recorder))
    (should (not (equal (seconds-to-time 0)
                        (autosync-git--sync-last-pull (cdr (assoc "/dir" autosync-git--sync-alist))))))))

(ert-deftest autosync-git-pull--in-sync ()
  "In sync with upstream: fetch only, no merge, no hook."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'in-sync))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-pull-hook)))))
    (autosync-git-pull "/dir")
    (should (equal '(("fetch")) call-recorder))))

(ert-deftest autosync-git-pull--ahead ()
  "Local ahead of upstream: fetch only, no merge."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'ahead))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-pull-hook)))))
    (autosync-git-pull "/dir")
    (should (equal '(("fetch")) call-recorder))))

(ert-deftest autosync-git-pull--diverged-clean-rebase ()
  "Diverged + probe clean: rebase onto upstream, run hook."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git-pull-style) 'rebase)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'diverged))
            ((symbol-function 'autosync-git--probe-clean-p) (always-return t))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-pull-hook)))))
    (autosync-git-pull "/dir")
    (should
     (equal '(("fetch")
              ("rebase" "@{upstream}")
              (autosync-git-after-pull-hook))
            call-recorder))))

(ert-deftest autosync-git-pull--diverged-clean-merge ()
  "Diverged + probe clean + style merge: merge upstream."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git-pull-style) 'merge)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'diverged))
            ((symbol-function 'autosync-git--probe-clean-p) (always-return t))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-pull-hook)))))
    (autosync-git-pull "/dir")
    (should
     (equal '(("fetch")
              ("merge")
              (autosync-git-after-pull-hook))
            call-recorder))))

(ert-deftest autosync-git-pull--diverged-conflict-refused ()
  "Diverged + probe dirty: refuse, message, no op."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'diverged))
            ((symbol-function 'autosync-git--probe-clean-p) (always-nil))
            ((symbol-function 'message) (record-calls-and-return nil)))
    (autosync-git-pull "/dir")
    ;; Expect fetch only, then a refusal message; no rebase/merge call.
    (should (equal "fetch" (caar call-recorder)))
    (should (= 2 (length call-recorder)))
    (should (string-match-p "would conflict with upstream"
                            (caar (last call-recorder))))))

(ert-deftest autosync-git-pull--diverged-force-conflict ()
  "Diverged + force: skip probe, run rebase, conflict detected, message."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git-pull-style) 'rebase)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 1 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'diverged))
            ((symbol-function 'autosync-git--probe-clean-p)
             (lambda (&rest _) (error "Probe should not be called when FORCE")))
            ((symbol-function 'autosync-git--unmerged-p) (always-return t))
            ((symbol-function 'message) (record-calls-and-return nil)))
    (autosync-git-pull "/dir" t)
    (should (equal '("fetch") (car call-recorder)))
    (should (equal '("rebase" "@{upstream}") (cadr call-recorder)))
    ;; Last entry is the message about the conflict; manual resolution implied.
    (should (string-match-p "resolve manually" (caar (last call-recorder))))))

(ert-deftest autosync-git-pull--no-upstream ()
  "No upstream configured: fetch then message, no merge/rebase."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'no-upstream))
            ((symbol-function 'message) (record-calls-and-return nil)))
    (autosync-git-pull "/dir")
    (should (equal '("fetch") (car call-recorder)))
    (should (string-match-p "no upstream" (caar (last call-recorder))))))

;;;; Status:

(ert-deftest autosync-git-status--in-sync ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'in-sync))
            ((symbol-function 'autosync-git--dirty-p) (always-nil))
            ((symbol-function 'autosync-git--unmerged-p) (always-nil))
            ((symbol-function 'message) (record-calls-and-return nil)))
    (autosync-git-status "/dir")
    (should (equal '(("Autosync-Git: %s" "/dir, clean, in sync"))
                   call-recorder))))

(ert-deftest autosync-git-status--diverged-dirty ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'diverged))
            ((symbol-function 'autosync-git--ahead-behind) (always-return (cons 2 3)))
            ((symbol-function 'autosync-git--dirty-p) (always-return t))
            ((symbol-function 'autosync-git--unmerged-p) (always-nil))
            ((symbol-function 'message) (record-calls-and-return nil)))
    (autosync-git-status "/dir")
    (should (equal '(("Autosync-Git: %s"
                      "/dir, dirty, diverged: ahead 2, behind 3"))
                   call-recorder))))

(ert-deftest autosync-git-status--unmerged ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'in-sync))
            ((symbol-function 'autosync-git--dirty-p) (always-return t))
            ((symbol-function 'autosync-git--unmerged-p) (always-return t))
            ((symbol-function 'message) (record-calls-and-return nil)))
    (autosync-git-status "/dir")
    (should (equal '(("Autosync-Git: %s"
                      "/dir, dirty, in sync, unmerged paths"))
                   call-recorder))))

;;;; Sync:

(ert-deftest autosync-git-sync--behind-then-push ()
  "Sync when local is behind: fast-forward then push."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 0 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'behind))
            ((symbol-function 'autosync-git--needs-push-p) (always-return t))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-pull-hook)))))
    (autosync-git-sync "/dir")
    (should
     (equal '(("fetch")
              ("merge" "--ff-only")
              (autosync-git-after-pull-hook)
              ("add" "-A")
              ("commit" "-a" "-m" "Automated commit by autosync-git")
              ("push"))
            call-recorder))))

(ert-deftest autosync-git-sync--in-sync-no-op ()
  "Sync when in sync and nothing to push: only fetch happens."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'in-sync))
            ((symbol-function 'autosync-git--needs-push-p) (always-nil)))
    (autosync-git-sync "/dir")
    (should (equal '(("fetch")) call-recorder))))

(ert-deftest autosync-git-sync--refused-skips-push ()
  "Sync skips the push step when the pull is refused (probe predicts conflict)."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'diverged))
            ((symbol-function 'autosync-git--probe-clean-p) (always-nil))
            ;; Even though local has commits beyond @{push}, the diverged-refused
            ;; pull means a push would be rejected, so we skip it.
            ((symbol-function 'autosync-git--needs-push-p) (always-return t))
            ((symbol-function 'message) (record-calls-and-return nil)))
    (autosync-git-sync "/dir")
    (should-not (cl-some (lambda (entry)
                           (member entry '(("add" "-A") ("push"))))
                         call-recorder))))

;;;; Dir-locals guard:

(ert-deftest autosync-git--alist-claims-mode-p--positive ()
  (should (autosync-git--alist-claims-mode-p
           '((nil . ((autosync-git-commit-message . "X")
                    (mode . autosync-git)))))))

(ert-deftest autosync-git--alist-claims-mode-p--negative ()
  (should-not (autosync-git--alist-claims-mode-p
               '((nil . ((autosync-git-commit-message . "X"))))))
  (should-not (autosync-git--alist-claims-mode-p
               '((nil . ((mode . some-other-mode)))))))

(ert-deftest autosync-git--alist-claims-mode-p--malformed ()
  (should-not (autosync-git--alist-claims-mode-p nil))
  (should-not (autosync-git--alist-claims-mode-p '(garbage)))
  (should-not (autosync-git--alist-claims-mode-p '((nil)))))

(ert-deftest autosync-git--alist-claims-mode-p--multiple-selectors ()
  (should (autosync-git--alist-claims-mode-p
           '((nil . ((some-var . 1)))
             (text-mode . ((mode . autosync-git))))))
  (should-not (autosync-git--alist-claims-mode-p
               '((nil . ((some-var . 1)))
                 (text-mode . ((mode . other-mode)))))))

;;;; Throttle and timer:

(ert-deftest autosync-git--throttle-pull--elapsed ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git-pull) (record-calls-and-return t)))
    (autosync-git--throttle-pull "/dir")
    (should
     (equal '(("/dir"))
            call-recorder))))

(ert-deftest autosync-git--throttle-pull--throttled ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time (current-time))
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git-pull) (record-calls-and-return t)))
    (autosync-git--throttle-pull "/dir")
    (should
     (equal nil
            call-recorder))))

(ert-deftest autosync-git--push-after-save--elapsed ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git-commit-message) "commit message")
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'run-with-timer) (record-calls-and-return t)))
    (autosync-git--push-after-save)
    (should
     (equal (list (list autosync-git-push-debounce nil
                        #'autosync-git-push "/dir" "commit message"))
            call-recorder))))

(ert-deftest autosync-git--push-after-save--debounced ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git-commit-message) "commit message")
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time (time-add (current-time)
                                                                       autosync-git-push-debounce))
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'run-with-timer) (record-calls-and-return t)))
    (autosync-git--push-after-save)
    (should
     (equal nil
            call-recorder))))

(ert-deftest autosync-git--pull-on-timer--trigger ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 1234))))
            ((symbol-function 'autosync-git--throttle-pull) (record-calls-and-return t))
            ((symbol-function 'autosync-git--timer-exists) (always-nil))
            ((symbol-function 'run-with-timer) (record-calls-and-return t)))
    (autosync-git--pull-on-timer "/dir")
    (should
     (equal (list (list "/dir")
                  (list 1234 nil #'autosync-git--pull-on-timer "/dir"))
            call-recorder))))

(ert-deftest autosync-git--pull-on-timer--no-timer-when-exists ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 1234))))
            ((symbol-function 'autosync-git--throttle-pull) (record-calls-and-return t))
            ((symbol-function 'autosync-git--timer-exists) (always-return t))
            ((symbol-function 'run-with-timer) (record-calls-and-return t)))
    (autosync-git--pull-on-timer "/dir")
    (should
     (equal (list (list "/dir"))
            call-recorder))))

;;;; Mode:

(ert-deftest autosync-git-mode--first-time ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist) nil)
            ((symbol-value 'autosync-git-pull-timer) 123)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--dir-locals-claims-mode-p) (always-return t))
            ((symbol-function 'autosync-git--pull-on-timer) (record-calls-and-return t))
            ((symbol-function 'autosync-git--pull-when-visiting) (record-calls-and-return t))
            ((symbol-function 'add-hook)  (record-calls-and-return t))
            ((symbol-function 'remove-hook)  (record-calls-and-return t)))
    (with-temp-buffer
      (autosync-git-mode)
      (should
       (equal autosync-git--sync-alist
              (list (cons "/dir"
                          (autosync-git--sync-create
                           :last-pull (seconds-to-time 0)
                           :next-push (seconds-to-time 0)
                           :timer autosync-git-pull-timer)))))
      (should (equal
               (list (list "/dir")
                     (list 'after-save-hook #'autosync-git--push-after-save nil t))
               call-recorder)))))

(ert-deftest autosync-git-mode--next-time ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir"
                         (autosync-git--sync-create
                          :last-pull (seconds-to-time 0)
                          :next-push (seconds-to-time 0)
                          :timer autosync-git-pull-timer))))
            ((symbol-value 'autosync-git-pull-timer) 123)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--dir-locals-claims-mode-p) (always-return t))
            ((symbol-function 'autosync-git--pull-on-timer) (record-calls-and-return t))
            ((symbol-function 'autosync-git--pull-when-visiting) (record-calls-and-return t))
            ((symbol-function 'add-hook)  (record-calls-and-return t))
            ((symbol-function 'remove-hook)  (record-calls-and-return t)))
    (with-temp-buffer
      (autosync-git-mode)
      (should (equal
               (list (list "/dir")
                     (list 'after-save-hook #'autosync-git--push-after-save nil t))
               call-recorder)))))

(ert-deftest autosync-git-mode--not-repo ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist) nil)
            ((symbol-value 'autosync-git-pull-timer) 123)
            ((symbol-function 'autosync-git--toplevel) (always-return nil))
            ((symbol-function 'autosync-git--pull-on-timer) (record-calls-and-return t))
            ((symbol-function 'autosync-git--pull-when-visiting) (record-calls-and-return t))
            ((symbol-function 'add-hook)  (record-calls-and-return t))
            ((symbol-function 'remove-hook)  (record-calls-and-return t)))
    (with-temp-buffer
      (autosync-git-mode)
      (should (equal
               (list
                (list 'after-save-hook #'autosync-git--push-after-save t))
               call-recorder)))))

(ert-deftest autosync-git-mode--dir-locals-rejects ()
  "Mode refuses to activate when no dir-locals claims it."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist) nil)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--dir-locals-claims-mode-p) (always-nil))
            ((symbol-function 'autosync-git--pull-on-timer) (record-calls-and-return t))
            ((symbol-function 'autosync-git--pull-when-visiting) (record-calls-and-return t))
            ((symbol-function 'add-hook)  (record-calls-and-return t))
            ((symbol-function 'remove-hook)  (record-calls-and-return t)))
    (with-temp-buffer
      (autosync-git-mode)
      (should-not autosync-git-mode)
      (should (equal autosync-git--sync-alist nil))
      ;; Only the disable-hook removal should have run.
      (should (equal
               (list (list 'after-save-hook #'autosync-git--push-after-save t))
               call-recorder)))))

(ert-deftest autosync-git-mode--dir-locals-skip ()
  "When `autosync-git-skip-dir-locals-check', activate without dir-locals."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist) nil)
            ((symbol-value 'autosync-git-pull-timer) 123)
            ((symbol-value 'autosync-git-skip-dir-locals-check) t)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--dir-locals-claims-mode-p)
             (lambda (&rest _) (error "Should not be called when skipping check")))
            ((symbol-function 'autosync-git--pull-on-timer) (record-calls-and-return t))
            ((symbol-function 'autosync-git--pull-when-visiting) (record-calls-and-return t))
            ((symbol-function 'add-hook)  (record-calls-and-return t))
            ((symbol-function 'remove-hook)  (record-calls-and-return t)))
    (with-temp-buffer
      (autosync-git-mode)
      (should autosync-git-mode))))

;;;; Timer-exists helper:

(ert-deftest autosync-git--timer-exists--no-timer ()
  (cl-letf (((symbol-value 'timer-list) nil))
    (should-not (autosync-git--timer-exists "/dir"))))

(ert-deftest autosync-git--timer-exists--empty-timer-list ()
  (cl-letf (((symbol-value 'timer-list) '()))
    (should-not (autosync-git--timer-exists "/dir"))))

(ert-deftest autosync-git--timer-exists--different-function ()
  (let ((timer (run-with-timer 1000 nil #'ignore "/dir")))
    (unwind-protect
        (should-not (autosync-git--timer-exists "/dir"))
      (cancel-timer timer))))

(ert-deftest autosync-git--timer-exists--different-repo ()
  (let ((timer (run-with-timer 1000 nil #'autosync-git--pull-on-timer "/other-dir")))
    (unwind-protect
        (should-not (autosync-git--timer-exists "/dir"))
      (cancel-timer timer))))

(ert-deftest autosync-git--timer-exists--matching-timer ()
  (let ((timer (run-with-timer 1000 nil #'autosync-git--pull-on-timer "/dir")))
    (unwind-protect
        (should (autosync-git--timer-exists "/dir"))
      (cancel-timer timer))))

(ert-deftest autosync-git--timer-exists--multiple-timers ()
  (let ((timer1 (run-with-timer 1000 nil #'ignore "/dir"))
        (timer2 (run-with-timer 1000 nil #'autosync-git--pull-on-timer "/other-dir"))
        (timer3 (run-with-timer 1000 nil #'autosync-git--pull-on-timer "/dir")))
    (unwind-protect
        (should (autosync-git--timer-exists "/dir"))
      (cancel-timer timer1)
      (cancel-timer timer2)
      (cancel-timer timer3))))

(provide 'autosync-git-tests)
;;; autosync-git-tests.el ends here
