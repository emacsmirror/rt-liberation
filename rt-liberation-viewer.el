;;; rt-liberation-viewer.el --- Emacs interface to RT  -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Free Software Foundation, Inc.
;;
;; Authors: Yoni Rabkin <yrk@gnu.org>
;;
;; This file is a part of rt-liberation.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3 of the
;; License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
;; MA 02111-1307, USA.


;;; Comments:
;; By the end of 2020 is was clear that a more robust way of viewing
;; tickets was preferable.


;;; Code:
(require 'rt-liberation)


(defconst rt-liber-viewer-font-lock-keywords
  (let ((header-regexp (regexp-opt '("id: " "Ticket: " "TimeTaken: "
				     "Type: " "Field: " "OldValue: "
				     "NewValue: " "Data: "
				     "Description: " "Created: "
				     "Creator: " "Attachments: ") t)))
    (list
     (list (concat "^" header-regexp ".*$") 0
	   'font-lock-comment-face)))
  "Expressions to font-lock for RT ticket viewer.")


(defun rt-liber-jump-to-latest-correspondence ()
  "Move point to the newest correspondence section."
  (interactive)
  (let (latest-point)
    (save-excursion
      (goto-char (point-max))
      (when (re-search-backward rt-liber-correspondence-regexp
				(point-min) t)
	(setq latest-point (point))))
    (if latest-point
	(progn
	  (goto-char latest-point)
	  (rt-liber-next-section-in-viewer))
      (message "no correspondence found"))))

(defun rt-liber-viewer-visit-in-browser ()
  "Visit this ticket in the RT Web interface."
  (interactive)
  (let ((id (rt-liber-ticket-id-only rt-liber-ticket-local)))
    (if id
	(browse-url
	 (concat rt-liber-base-url "Ticket/Display.html?id=" id))
      (error "no ticket currently in view"))))

(defun rt-liber-display-ticket-history (ticket-alist &optional assoc-browser)
  "Display history for ticket.

TICKET-ALIST alist of ticket data.
ASSOC-BROWSER if non-nil should be a ticket browser."
  (let* ((ticket-id (rt-liber-ticket-id-only ticket-alist))
	 (contents (rt-liber-rest-run-ticket-history-base-query ticket-id))
	 (new-ticket-buffer (get-buffer-create
			     (concat "*RT Ticket #" ticket-id "*"))))
    (with-current-buffer new-ticket-buffer
      (let ((inhibit-read-only t))
	(erase-buffer)
	(insert contents)
	(goto-char (point-min))
	(rt-liber-viewer-mode)
	(set
	 (make-local-variable 'rt-liber-ticket-local)
	 ticket-alist)
	(when assoc-browser
	  (set
	   (make-local-variable 'rt-liber-assoc-browser)
	   assoc-browser))
	(set-buffer-modified-p nil)
	(setq buffer-read-only t)))
    (switch-to-buffer new-ticket-buffer)))

(defun rt-liber-viewer-mode-quit ()
  "Bury the ticket viewer."
  (interactive)
  (bury-buffer))

(defun rt-liber-viewer-show-ticket-browser ()
  "Return to the ticket browser buffer."
  (interactive)
  (let ((id (rt-liber-ticket-id-only rt-liber-ticket-local)))
    (if id
	(let ((target-buffer
	       (if rt-liber-assoc-browser
		   (buffer-name rt-liber-assoc-browser)
		 (buffer-name rt-liber-browser-buffer-name))))
	  (if target-buffer
	      (switch-to-buffer target-buffer)
	    (error "associated ticket browser buffer no longer exists"))
	  (rt-liber-browser-move-point-to-ticket id))
      (error "no ticket currently in view"))))

(defun rt-liber-next-section-in-viewer ()
  "Move point to next section."
  (interactive)
  (forward-line 1)
  (when (not (re-search-forward rt-liber-content-regexp (point-max) t))
    (message "no next section"))
  (goto-char (point-at-bol)))

(defun rt-liber-previous-section-in-viewer ()
  "Move point to previous section."
  (interactive)
  (forward-line -1)
  (when (not (re-search-backward rt-liber-content-regexp (point-min) t))
    (message "no previous section"))
  (goto-char (point-at-bol)))

(defconst rt-liber-viewer-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") 'rt-liber-viewer-mode-quit)
    (define-key map (kbd "n") 'rt-liber-next-section-in-viewer)
    (define-key map (kbd "N") 'rt-liber-jump-to-latest-correspondence)
    (define-key map (kbd "p") 'rt-liber-previous-section-in-viewer)
    (define-key map (kbd "V") 'rt-liber-viewer-visit-in-browser)
    (define-key map (kbd "m") 'rt-liber-viewer-answer)
    (define-key map (kbd "M") 'rt-liber-viewer-answer-this)
    (define-key map (kbd "t") 'rt-liber-viewer-answer-provisionally)
    (define-key map (kbd "T") 'rt-liber-viewer-answer-provisionally-this)
    (define-key map (kbd "F") 'rt-liber-viewer-answer-verbatim-this)
    (define-key map (kbd "c") 'rt-liber-viewer-comment)
    (define-key map (kbd "C") 'rt-liber-viewer-comment-this)
    (define-key map (kbd "g") 'revert-buffer)
    (define-key map (kbd "SPC") 'scroll-up)
    (define-key map (kbd "DEL") 'scroll-down)
    (define-key map (kbd "h") 'rt-liber-viewer-show-ticket-browser)
    map)
  "Key map for ticket viewer.")

(define-derived-mode rt-liber-viewer-mode nil
  "RT Liberation Viewer"
  "Major Mode for viewing RT tickets.
\\{rt-liber-viewer-mode-map}"
  (set
   (make-local-variable 'font-lock-defaults)
   '((rt-liber-viewer-font-lock-keywords)))
  (set (make-local-variable 'revert-buffer-function)
       #'rt-liber-refresh-ticket-history)
  (set (make-local-variable 'buffer-stale-function)
       (lambda (&optional _noconfirm) 'slow))
  (when rt-liber-jump-to-latest
    (rt-liber-jump-to-latest-correspondence))
  (run-hooks 'rt-liber-viewer-hook))

(defun rt-liber-refresh-ticket-history (&optional _ignore-auto _noconfirm)
  (interactive)
  (if rt-liber-ticket-local
      (rt-liber-display-ticket-history rt-liber-ticket-local
				       rt-liber-assoc-browser)
    (error "not viewing a ticket")))

;; wrapper functions around specific functions provided by a backend

(declare-function
 rt-liber-gnus-compose-reply-to-requestor
 "rt-liberation-gnus.el")
(declare-function
 rt-liber-gnus-compose-reply-to-requestor-to-this
 "rt-liberation-gnus.el")
(declare-function
 rt-liber-gnus-compose-reply-to-requestor-verbatim-this
 "rt-liberation-gnus.el")
(declare-function
 rt-liber-gnus-compose-provisional
 "rt-liberation-gnus.el")
(declare-function
 rt-liber-gnus-compose-provisional-to-this
 "rt-liberation-gnus.el")
(declare-function
 rt-liber-gnus-compose-comment
 "rt-liberation-gnus.el")
(declare-function
 rt-liber-gnus-compose-comment-this
 "rt-liberation-gnus.el")

(defun rt-liber-viewer-answer ()
  "Answer the ticket."
  (interactive)
  (cond ((featurep 'rt-liberation-gnus)
	 (rt-liber-gnus-compose-reply-to-requestor))
	(t (error "no function defined"))))

(defun rt-liber-viewer-answer-this ()
  "Answer the ticket using the current context."
  (interactive)
  (cond ((featurep 'rt-liberation-gnus)
	 (rt-liber-gnus-compose-reply-to-requestor-to-this))
	(t (error "no function defined"))))

(defun rt-liber-viewer-answer-verbatim-this ()
  "Answer the ticket using the current context verbatim."
  (interactive)
  (cond ((featurep 'rt-liberation-gnus)
	 (rt-liber-gnus-compose-reply-to-requestor-verbatim-this))
	(t (error "no function defined"))))

(defun rt-liber-viewer-answer-provisionally ()
  "Provisionally answer the ticket."
  (interactive)
  (cond ((featurep 'rt-liberation-gnus)
	 (rt-liber-gnus-compose-provisional))
	(t (error "no function defined"))))

(defun rt-liber-viewer-answer-provisionally-this ()
  "Provisionally answer the ticket using the current context."
  (interactive)
  (cond ((featurep 'rt-liberation-gnus)
	 (rt-liber-gnus-compose-provisional-to-this))
	(t (error "no function defined"))))

(defun rt-liber-viewer-comment ()
  "Comment on the ticket."
  (interactive)
  (cond ((featurep 'rt-liberation-gnus)
	 (rt-liber-gnus-compose-comment))
	(t (error "no function defined"))))

(defun rt-liber-viewer-comment-this ()
  "Comment on the ticket using the current context."
  (interactive)
  (cond ((featurep 'rt-liberation-gnus)
	 (rt-liber-gnus-compose-comment-this))
	(t (error "no function defined"))))


(provide 'rt-liberation-viewer)

;;; rt-liberation-viewer.el ends here.
