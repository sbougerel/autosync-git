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
The stub records (rest of args after repo-dir and done callback) and
synchronously calls the done callback with exit code 0."
  (lambda (_repo done &rest git-args)
    (if (consp call-recorder)
        (setcdr (last call-recorder) (list git-args))
      (setq call-recorder (list git-args)))
    (funcall done 0)
    nil))

(require 'autosync-git)

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

(ert-deftest autosync-git-pull--behind ()
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
                                           '((autosync-git-after-merge-hook)))))
    (autosync-git-pull "/dir")
    (should
     (equal '(("fetch")
              ("merge")
              (autosync-git-after-merge-hook))
            call-recorder))
    (should (not (equal (seconds-to-time 0)
                        (autosync-git--sync-last-pull (cdr (assoc "/dir" autosync-git--sync-alist))))))))

(ert-deftest autosync-git-pull--ahead ()
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
                                           '((autosync-git-after-merge-hook)))))
    (autosync-git-pull "/dir")
    (should
     (equal '(("fetch"))
            call-recorder))
    (should (not (equal (seconds-to-time 0)
                        (autosync-git--sync-last-pull (cdr (assoc "/dir" autosync-git--sync-alist))))))))

(ert-deftest autosync-git-pull--merge-conflict ()
  "Test that merge conflicts are detected and user is notified."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 1 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'behind))
            ((symbol-function 'autosync-git--unmerged-p) (always-return t))
            ((symbol-function 'message) (record-calls-and-return nil))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-merge-hook)))))
    (autosync-git-pull "/dir")
    (should
     (equal '(("fetch")
              ("merge")
              ("Autosync-Git: Merge conflict in %s - please resolve manually" "/dir"))
            call-recorder))))

(ert-deftest autosync-git-pull--merge-failure ()
  "Test that non-conflict merge failures are handled."
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist)
             (list (cons "/dir" (autosync-git--sync-create
                                 :last-pull (seconds-to-time 0)
                                 :next-push (seconds-to-time 0)
                                 :timer 0))))
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
            ((symbol-function 'autosync-git--call-async) (stub-call-async-success))
            ((symbol-function 'autosync-git--call) (record-rest-and-return 1 (cons 1 "")))
            ((symbol-function 'autosync-git--upstream-ancestry) (always-return 'behind))
            ((symbol-function 'autosync-git--unmerged-p) (always-nil))
            ((symbol-function 'message) (record-calls-and-return nil))
            ((symbol-function 'run-hooks) (record-only-and-return
                                           t
                                           '((autosync-git-after-merge-hook)))))
    (autosync-git-pull "/dir")
    (should
     (equal '(("fetch")
              ("merge")
              ("Autosync-Git: Merge failed in %s" "/dir"))
            call-recorder))))

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
  "Test that run-with-timer is not called when a timer already exists."
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

(ert-deftest autosync-git-mode--first-time ()
  (cl-letf (((symbol-value 'call-recorder) nil)
            ((symbol-value 'autosync-git--sync-alist) nil)
            ((symbol-value 'autosync-git-pull-timer) 123)
            ((symbol-function 'autosync-git--toplevel) (always-return "/dir"))
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

(ert-deftest autosync-git--timer-exists--no-timer ()
  "Test that timer-exists returns nil when no matching timer exists."
  (cl-letf (((symbol-value 'timer-list) nil))
    (should-not (autosync-git--timer-exists "/dir"))))

(ert-deftest autosync-git--timer-exists--empty-timer-list ()
  "Test that timer-exists returns nil with empty timer-list."
  (cl-letf (((symbol-value 'timer-list) '()))
    (should-not (autosync-git--timer-exists "/dir"))))

(ert-deftest autosync-git--timer-exists--different-function ()
  "Test that timer-exists returns nil when timer has different function."
  (let ((timer (run-with-timer 1000 nil #'ignore "/dir")))
    (unwind-protect
        (should-not (autosync-git--timer-exists "/dir"))
      (cancel-timer timer))))

(ert-deftest autosync-git--timer-exists--different-repo ()
  "Test that timer-exists returns nil when timer has different repo-dir."
  (let ((timer (run-with-timer 1000 nil #'autosync-git--pull-on-timer "/other-dir")))
    (unwind-protect
        (should-not (autosync-git--timer-exists "/dir"))
      (cancel-timer timer))))

(ert-deftest autosync-git--timer-exists--matching-timer ()
  "Test that timer-exists returns non-nil when matching timer exists."
  (let ((timer (run-with-timer 1000 nil #'autosync-git--pull-on-timer "/dir")))
    (unwind-protect
        (should (autosync-git--timer-exists "/dir"))
      (cancel-timer timer))))

(ert-deftest autosync-git--timer-exists--multiple-timers ()
  "Test that timer-exists finds correct timer among multiple timers."
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
