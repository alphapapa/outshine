;;; outshine.el --- outline with outshine outshines outline

;; Copyright (c) 2013-2020 Thorsten Jolitz and contributors.

;; Author: Thorsten Jolitz
;; Maintainer: Thibault Polge <thibault@thb.lt>
;; Maintainer: Adam Porter <adam@alphapapa.net>
;; Version: 4.0-pre
;; URL: https://github.com/alphapapa/outshine
;; Package-Requires: ((outorg "2.0") (cl-lib "0.5"))
;; Licence: GPL2+
;; Keywords: convenience, outlines, Org

;;; License:

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 2 of the License, or
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

;; Outshine attempts to bring the look & feel of Org-mode to the (GNU
;; Emacs) world outside of the Org major-mode.  For more information,
;; please see the readme file in the git repo.

;;; Code:

;;;; Requirements

(eval-when-compile
  ;; FIXME: Remove
  (require 'cl))
(require 'outline)
(require 'outorg)
(require 'outshine-org-cmds)
;; necessary before Emacs 24.3  FIXME: Remove
(require 'newcomment)
(require 'cl-lib)

;;;; Declarations

(declare-function outorg-edit-as-org "outorg")
(declare-function outorg-copy-edits-and-exit "outorg")
(declare-function navi-map-keyboard-to-key "navi-mode")
(declare-function navi-search-and-switch "navi-mode")
(declare-function navi-get-regexp "navi-mode")
(declare-function idomenu "idomenu")
(declare-function imenu-choose-buffer-index "imenu")
(declare-function org-agenda-remove-restriction-lock "org-agenda")

;;;; Constants

(defconst outshine-max-level 8
  "Maximal level of headlines recognized.")

;; copied from org-source.el
(defconst outshine-level-faces
  '(outshine-level-1 outshine-level-2 outshine-level-3 outshine-level-4
                     outshine-level-5 outshine-level-6 outshine-level-7
                     outshine-level-8))

(defconst outshine-protected-variables
  '(outline-regexp outline-level outline-heading-end-regexp)
  "Variables to save and restore around `outshine-mode'.
Please report a bug if this needs to be changed.")

(defconst outshine-oldschool-elisp-outline-regexp-base
  (format "[;]\\{1,%d\\}" outshine-max-level)
  ;; FIXME: Remove if possible.
  "Oldschool Emacs Lisp base for calculating `outline-regexp'.")

(defconst outshine-comment-tag "comment"
  "Tag that marks subtrees as commented.
Commented subtrees do not open during visibility cycling.")

(defconst outshine-latex-documentclass-regexp
  "^[[:space:]]*\\\\documentclass\\(?:\\[.+]\\)?{\\(.+\\)}"
  "Regexp matching the document class in a LaTeX doc.")

;;;; Variables

(defvar outshine-mode-map
  (make-sparse-keymap)
  "The keymap for `outshine-mode'.")

(defvar-local outshine-protected-variables-values nil
  "The values of variables defined by `outshine-protected-variables'.")

(defvar-local outshine-font-lock-keywords nil
  "Font locking keywords defined in the current buffer.")

;; from `outline-magic'
(defvar-local outshine-promotion-headings nil
  "A sorted list of headings used for promotion/demotion commands.
Set this to a list of headings as they are matched by `outline-regexp',
top-level heading first.  If a mode or document needs several sets of
outline headings (for example numbered and unnumbered sections), list
them set by set, separated by a nil element.  See the example for
`texinfo-mode' in the file commentary.")

(defvar-local outshine-delete-leading-whitespace-from-outline-regexp-base-p nil
  "If non-nil, delete leading whitespace from outline-regexp-base.")

(defvar-local outshine-enforce-no-comment-padding-p nil
  "If non-nil, make sure no comment-padding is used in heading.")

(defvar outshine-regexp-base ""
  "Actual base for calculating the outline-regexp")

(defvar-local outshine-normalized-comment-start ""
  "Comment-start regexp without leading and trailing whitespace")

(defvar-local outshine-normalized-comment-end ""
  "Comment-end regexp without leading and trailing whitespace")

(defvar-local outshine-normalized-outline-regexp-base ""
  "Outline-regex-base without leading and trailing whitespace")

;; show number of hidden lines in folded subtree
(defvar outshine-show-hidden-lines-cookies-p nil
  "If non-nil, commands for hidden-lines cookies are activated.")

;; remember if hidden-lines cookies are shown or hidden
(defvar outshine-hidden-lines-cookies-on-p nil
  "If non-nil, hidden-lines cookies are shown, otherwise hidden.")

(defvar-local outshine-imenu-default-generic-expression nil
  "Expression assigned by default to `imenu-generic-expression'.")

(defvar-local outshine-imenu-generic-expression nil
  "Expression assigned to `imenu-generic-expression'.")

(defvar outshine-self-insert-command-undo-counter 0
  "Used for outshine speed-commands.")

(defvar outshine-open-comment-trees nil
  "Cycle comment-subtrees anyway when non-nil.")

(defvar outshine-current-buffer-visibility-state nil
  "Stores current visibility state of buffer.")

(defvar-local outshine-use-outorg-last-headline-marker (make-marker)
  "Marker for last headline edited with outorg.")

(defvar outshine-imenu-preliminary-generic-expression nil
  "Imenu variable.")

(defvar outshine-agenda-files ()
  "List of absolute file names of outshine-agenda-files.")

(defvar outshine-agenda-include-org-agenda-p nil
  "Include Org Agenda files in Outshine Agenda when non-nil.")

(defvar outshine-agenda-old-org-agenda-files nil
  "Storage for old value of `org-agenda-files'")

;;;; Faces

(defgroup outshine-faces nil
  "Faces in Outshine."
  :tag "Outshine Faces"
  :group 'outshine
  :group 'faces)

;; from `org-compat.el'
(defun outshine-compatible-face (inherits specs)
  ;; FIXME: Remove this function.  Shouldn't be necessary anymore.
  "Make a compatible face specification.
If INHERITS is an existing face and if the Emacs version supports it,
just inherit the face.  If INHERITS is set and the Emacs version does
not support it, copy the face specification from the inheritance face.
If INHERITS is not given and SPECS is, use SPECS to define the face.
XEmacs and Emacs 21 do not know about the `min-colors' attribute.
For them we convert a (min-colors 8) entry to a `tty' entry and move it
to the top of the list.  The `min-colors' attribute will be removed from
any other entries, and any resulting duplicates will be removed entirely."
  (when (and inherits
             (facep inherits)
             (not specs))
    (setq specs (or specs
                    (get inherits 'saved-face)
                    (get inherits 'face-defface-spec))))
  (cond ((and inherits
              (facep inherits)
              (not (featurep 'xemacs))
              ;; FIXME: Remove version checks, or move elsewhere.
              (>= emacs-major-version 22)
              ;; do not inherit outline faces before Emacs 23
              (or (>= emacs-major-version 23)
                  (not (string-match "\\`outline-[0-9]+"
                                     (symbol-name inherits)))))
         (list (list t :inherit inherits)))

        ((or (featurep 'xemacs)
             (< emacs-major-version 22))
         ;; These do not understand the `min-colors' attribute.
         ;; FIXME: Rename variables meaningfully.
         ;; FIXME: Convert to `cl-loop'.
         (let (r e a)
           (while (setq e (pop specs))
             (cond ((memq (car e) '(t default))
                    (push e r))
                   ((setq a (member '(min-colors 8) (car e)))
                    (nconc r (list (cons (cons '(type tty)
                                               (delq (car a) (car e)))
                                         (cdr e)))))
                   ((setq a (assq 'min-colors (car e)))
                    (setq e (cons (delq a (car e))
                                  (cdr e)))
                    (unless (assoc (car e) r)
                      (push e r)))
                   (t (when (assoc (car e) r)
                        (push e r)))))
           (nreverse r)))

        (t specs)))
(put 'outshine-compatible-face 'lisp-indent-function 1)

;; The following face definitions are from `org-faces.el'
;; originally copied from font-lock-function-name-face
(defface outshine-level-1
  (outshine-compatible-face 'outline-1
    '((((class color) (min-colors 88)
        (background light)) (:foreground "Blue1"))
      (((class color) (min-colors 88)
        (background dark)) (:foreground "LightSkyBlue"))
      (((class color) (min-colors 16)
        (background light)) (:foreground "Blue"))
      (((class color) (min-colors 16)
        (background dark)) (:foreground "LightSkyBlue"))
      (((class color) (min-colors 8)) (:foreground "blue" :bold t))
      (t (:bold t))))
  "Face used for level 1 headlines."
  :group 'outshine-faces)

;; originally copied from font-lock-variable-name-face
(defface outshine-level-2
  (outshine-compatible-face 'outline-2
    '((((class color) (min-colors 16)
        (background light)) (:foreground "DarkGoldenrod"))
      (((class color) (min-colors 16)
        (background dark))  (:foreground "LightGoldenrod"))
      (((class color) (min-colors 8)
        (background light)) (:foreground "yellow"))
      (((class color) (min-colors 8)
        (background dark))  (:foreground "yellow" :bold t))
      (t (:bold t))))
  "Face used for level 2 headlines."
  :group 'outshine-faces)

;; originally copied from font-lock-keyword-face
(defface outshine-level-3
  (outshine-compatible-face 'outline-3
    '((((class color) (min-colors 88)
        (background light)) (:foreground "Purple"))
      (((class color) (min-colors 88)
        (background dark))  (:foreground "Cyan1"))
      (((class color) (min-colors 16)
        (background light)) (:foreground "Purple"))
      (((class color) (min-colors 16)
        (background dark))  (:foreground "Cyan"))
      (((class color) (min-colors 8)
        (background light)) (:foreground "purple" :bold t))
      (((class color) (min-colors 8)
        (background dark))  (:foreground "cyan" :bold t))
      (t (:bold t))))
  "Face used for level 3 headlines."
  :group 'outshine-faces)

;; originally copied from font-lock-comment-face
(defface outshine-level-4
  (outshine-compatible-face 'outline-4
    '((((class color) (min-colors 88)
        (background light)) (:foreground "Firebrick"))
      (((class color) (min-colors 88)
        (background dark))  (:foreground "chocolate1"))
      (((class color) (min-colors 16)
        (background light)) (:foreground "red"))
      (((class color) (min-colors 16)
        (background dark))  (:foreground "red1"))
      (((class color) (min-colors 8)
        (background light))  (:foreground "red" :bold t))
      (((class color) (min-colors 8)
        (background dark))   (:foreground "red" :bold t))
      (t (:bold t))))
  "Face used for level 4 headlines."
  :group 'outshine-faces)

;; originally copied from font-lock-type-face
(defface outshine-level-5
  (outshine-compatible-face 'outline-5
    '((((class color) (min-colors 16)
        (background light)) (:foreground "ForestGreen"))
      (((class color) (min-colors 16)
        (background dark)) (:foreground "PaleGreen"))
      (((class color) (min-colors 8)) (:foreground "green"))))
  "Face used for level 5 headlines."
  :group 'outshine-faces)

;; originally copied from font-lock-constant-face
(defface outshine-level-6
  (outshine-compatible-face 'outline-6
    '((((class color) (min-colors 16)
        (background light)) (:foreground "CadetBlue"))
      (((class color) (min-colors 16)
        (background dark)) (:foreground "Aquamarine"))
      (((class color) (min-colors 8)) (:foreground "magenta")))) "Face used for level 6 headlines."
  :group 'outshine-faces)

;; originally copied from font-lock-builtin-face
(defface outshine-level-7
  (outshine-compatible-face 'outline-7
    '((((class color) (min-colors 16)
        (background light)) (:foreground "Orchid"))
      (((class color) (min-colors 16)
        (background dark)) (:foreground "LightSteelBlue"))
      (((class color) (min-colors 8)) (:foreground "blue"))))
  "Face used for level 7 headlines."
  :group 'outshine-faces)

;; originally copied from font-lock-string-face
(defface outshine-level-8
  (outshine-compatible-face 'outline-8
    '((((class color) (min-colors 16)
        (background light)) (:foreground "RosyBrown"))
      (((class color) (min-colors 16)
        (background dark)) (:foreground "LightSalmon"))
      (((class color) (min-colors 8)) (:foreground "green"))))
  "Face used for level 8 headlines."
  :group 'outshine-faces)

;;;; Customization

;;;;; Custom Groups

(defgroup outshine nil
  "Enhanced library for outline navigation in source code buffers."
  :prefix "outshine-"
  ;; MAYBE: Change parent group.
  :group 'lisp)

;;;;; Custom Vars

;; FIXME: Remove unnecessary `:group' from customs.

(defcustom outshine-imenu-show-headlines-p t
  "Non-nil means use calculated outline-regexp for imenu."
  :group 'outshine
  :type 'boolean)

(defcustom outshine-fontify t
  ;; `quote' instead of ' to avoid conversion of ' in for example C-h v
  ;; (`describe-variable').
  "When to fontify the outshine headings in a buffer.

Possible values are:

 `t'        Always (the default).
 `nil'      Never.
 function   A Lisp predicate function with no arguments. For example
            `(lambda () (not (derived-mode-p (quote prog-mode))))'
            fontifies only when not in a programming mode.

`t' and `nil' can be used for a file local variable to make an
exception for certain files or to be independent of the user's
customization."
  :group 'outshine
  :type '(choice :value ""
                 (const :tag "Always (the default)" t)
                 (const :tag "Never" nil)
                 (function :tag "Function"))
  :safe (lambda (v) (memq v '(t nil))))

;; from `org'
(defcustom outshine-fontify-whole-heading-line nil
  "Non-nil means fontify the whole line for headings.
This is useful when setting a background color for the
poutshine-level-* faces."
  :group 'outshine
  :type 'boolean)

(defcustom outshine-regexp-outcommented-p t
  "Non-nil if regexp-base is outcommented to calculate outline-regexp."
  :group 'outshine
  :type 'boolean)

;; was "[][+]"
(defcustom outshine-regexp-special-chars
  "[][}{,+[:digit:]\\]"
  "Regexp for detecting (special) characters in outline-regexp.
These special chars will be stripped when the outline-regexp is
transformed into a string, e.g. when the outline-string for a
certain level is calculated. "
  :group 'outshine
  :type 'regexp)

;; from `outline-magic'
(defcustom outshine-cycle-emulate-tab nil
  "Where should `outshine-cycle' emulate TAB.
nil    Never
white  Only in completely white lines
t      Everywhere except in headlines"
  :group 'outshine
  :type '(choice (const :tag "Never" nil)
                 (const :tag "Only in completely white lines" white)
                 (const :tag "Everywhere except in headlines" t)
                 ))

;; startup options
(defcustom outshine-startup-folded-p nil
  "Non-nil means files will be opened with all but top level headers folded."
  :group 'outshine
  :type 'boolean)

(defcustom outshine-hidden-lines-cookie-left-delimiter "["
  "Left delimiter of cookie that shows number of hidden lines."
  :group 'outshine
  :type 'string)

(defcustom outshine-hidden-lines-cookie-right-delimiter "]"
  "Left delimiter of cookie that shows number of hidden lines."
  :group 'outshine
  :type 'string)

(defcustom outshine-hidden-lines-cookie-left-signal-char "#"
  "Left signal character of cookie that shows number of hidden lines."
  :group 'outshine
  :type 'string)

(defcustom outshine-hidden-lines-cookie-right-signal-char ""
  "Right signal character of cookie that shows number of hidden lines."
  :group 'outshine
  :type 'string)

(defcustom outshine-regexp-base-char "*"
  "Character used in outline-regexp base."
  :group 'outshine
  :type 'string)

;; old regexp: "[*]+"
(defvar outshine-default-outline-regexp-base
  ;; MAYBE: Define this with a custom setter.
  (format "[%s]\\{1,%d\\}"
          outshine-regexp-base-char outshine-max-level)
  "Default base for calculating the outline-regexp")

(defvar outshine-hidden-lines-cookie-format-regexp
  (concat
   "\\( "
   (regexp-quote outshine-hidden-lines-cookie-left-delimiter)
   (regexp-quote outshine-hidden-lines-cookie-left-signal-char)
   "\\)"
   "\\([[:digit:]]+\\)"
   "\\("
   (regexp-quote outshine-hidden-lines-cookie-right-signal-char)
   ;; FIXME robust enough?
   (format "\\%s" outshine-hidden-lines-cookie-right-delimiter)
   "\\)")
  "Matches cookies that show number of hidden lines for folded subtrees.")

(defvar outshine-cycle-silently nil
  "Suppress visibility-state-change messages when non-nil.")

(defcustom outshine-org-style-global-cycling-at-bob-p nil
  "Configure the behavior of `outshine-cycle` on beginning of buffer.

When the point is on a heading and at the beginning of the
buffer (that is, when the first character of the buffer is the
start of a headline, and the point is on it), the behavior of
`outshine-cycle' is controlled by this variable:

 - If nil, cycle the heading normally like in Org mode.
 - Otherwise, cycle the entire buffer, ignoring the heading at point."
  :group 'outshine
  :type 'boolean)

(defcustom outshine-use-speed-commands nil
  "Non-nil means activate single letter commands at beginning of a headline.
This may also be a function to test for appropriate locations
where speed commands should be active, e.g.:

    (setq outshine-use-speed-commands
      (lambda ()  ( ...your code here ... ))"
  :group 'outshine
  :type '(choice
          (const :tag "Never" nil)
          (const :tag "At beginning of headline stars" t)
          (function)))

(defcustom outshine-latex-classes
  '(("scrbook" . ((1 . "^[[:space:]]*\\\\part\\*?{\\(.+\\)}")
                  (2 . "^[[:space:]]*\\\\chapter\\*?{\\(.+\\)}")
                  (3 . "^[[:space:]]*\\\\section\\*?{\\(.+\\)}")
                  (4 . "^[[:space:]]*\\\\subsection\\*?{\\(.+\\)}")
                  (5 . "^[[:space:]]*\\\\subsubsection\\*?{\\(.+\\)}")
                  (6 . "^[[:space:]]*\\\\paragraph\\*?{\\(.+\\)}")
                  (7 . "^[[:space:]]*\\\\subparagraph\\*?{\\(.+\\)}")))
    ("book" . ((1 . "^[[:space:]]*\\\\part\\*?{\\(.+\\)}")
               (2 . "^[[:space:]]*\\\\chapter\\*?{\\(.+\\)}")
               (3 . "^[[:space:]]*\\\\section\\*?{\\(.+\\)}")
               (4 . "^[[:space:]]*\\\\subsection\\*?{\\(.+\\)}")
               (5 . "^[[:space:]]*\\\\subsubsection\\*?{\\(.+\\)}")))
    ("report" . ((1 . "^[[:space:]]*\\\\part\\*?{\\(.+\\)}")
                 (2 . "^[[:space:]]*\\\\chapter\\*?{\\(.+\\)}")
                 (3 . "^[[:space:]]*\\\\section\\*?{\\(.+\\)}")
                 (4 . "^[[:space:]]*\\\\subsection\\*?{\\(.+\\)}")
                 (5 . "^[[:space:]]*\\\\subsubsection\\*?{\\(.+\\)}")))
    ("scrartcl" . ((1 . "^[[:space:]]*\\\\section\\*?{\\(.+\\)}")
                   (2 . "^[[:space:]]*\\\\subsection\\*?{\\(.+\\)}")
                   (3 . "^[[:space:]]*\\\\subsubsection\\*?{\\(.+\\)}")
                   (4 . "^[[:space:]]*\\\\paragraph\\*?{\\(.+\\)}")
                   (5 . "^[[:space:]]*\\\\subparagraph\\*?{\\(.+\\)}")))
    ("article" . ((1 . "^[[:space:]]*\\\\section\\*?{\\(.+\\)}")
                  (2 . "^[[:space:]]*\\\\subsection\\*?{\\(.+\\)}")
                  (3 . "^[[:space:]]*\\\\subsubsection\\*?{\\(.+\\)}")
                  (4 . "^[[:space:]]*\\\\paragraph\\*?{\\(.+\\)}")
                  (5 . "^[[:space:]]*\\\\subparagraph\\*?{\\(.+\\)}"))))
  "Sectioning structure of LaTeX classes.
For each class, the outline level and a regexp matching the latex
section are given (with section title in submatch 1)."
  :group 'outshine
  :type '(alist :key-type string
                :value-type alist))

(defcustom outshine-preserve-delimiter-whitespace nil
  "Non-nil means that whitespace present at the start or end of
`comment-start' is preserved when matching headline syntax. By
default, such space is removed to support language modes which
erroneously include it in `comment-start', but for other
languages, such as Haskell, the trailing whitespace is
significant."
  :group 'outshine
  :type 'boolean)

;;;; Minor mode

;;;###autoload
(define-minor-mode outshine-mode
  "Outshine brings the look&feel of Org-mode to the (GNU Emacs)
world outside of the Org major-mode."
  :init-value nil
  :lighter " Outshine"
  (if outshine-mode
      (outshine--minor-mode-activate)
    (outshine--minor-mode-deactivate)))

(defun outshine--minor-mode-activate ()
  "Activate Outshine.

Don't use this function, the public interface is
`outshine-mode'."

  ;; Ensure outline is on
  (unless outline-minor-mode
    (outline-minor-mode 1))

  ;; Save variables
  (setq outshine-protected-variables-values (mapcar 'symbol-value outshine-protected-variables))

  ;; Install deactivation hook
  (add-hook 'outline-minor-mode-hook 'outshine--outline-minor-mode-hook)

  ;; Advise org-store-log-note
  (defadvice org-store-log-note (around org-store-log-note-around activate)
    ;; FIXME: Try to use `outshine-use-outorg' to do this instead of advice.
    "Outcomment inserted log-note in Outshine buffers."
    (let ((outshine-log-note-beg-marker
           ;; stay before inserted text
           (copy-marker (outshine-mimic-org-log-note-marker) nil))
          (outshine-log-note-end-marker
           ;; stay after inserted text
           (copy-marker (outshine-mimic-org-log-note-marker) t)))
      ad-do-it
      (unless (derived-mode-p 'org-mode 'org-agenda-mode)
        (outshine-comment-region outshine-log-note-beg-marker
                                 outshine-log-note-end-marker))
      (move-marker outshine-log-note-beg-marker nil)
      (move-marker outshine-log-note-end-marker nil)))

  ;; Compute basic outline regular expressions
  (outshine-set-outline-regexp-base)
  (outshine-normalize-regexps)

  (let ((out-regexp (outshine-calc-outline-regexp)))
    (outshine-set-local-outline-regexp-and-level
     out-regexp
     'outshine-calc-outline-level
     outline-heading-end-regexp)
    (setq outshine-promotion-headings
          (outshine-make-promotion-headings-list 8))
    ;; imenu preparation
    (and outshine-imenu-show-headlines-p
         (set (make-local-variable
               'outshine-imenu-preliminary-generic-expression)
              `((nil ,(concat out-regexp "\\(.*$\\)") 1)))
         (if imenu-generic-expression
             (add-to-list 'imenu-generic-expression
                          (car outshine-imenu-preliminary-generic-expression))
           (setq imenu-generic-expression
                 outshine-imenu-preliminary-generic-expression)))
    (when outshine-startup-folded-p
      (condition-case error-data
          (outline-hide-sublevels 1)
        ('error (message "No outline structure detected"))))
    (when (pcase outshine-fontify
            (`t t)
            (`nil nil)
            ((pred functionp) (funcall outshine-fontify))
            (_ (user-error "Invalid value for variable `outshine-fontify'")))
      (outshine-fontify-headlines out-regexp))))

(defun outshine--minor-mode-deactivate ()
  "Deactivate Outshine.

Don't use this function, the public interface is
`outshine-mode'."
  ;; Restore variables
  (cl-mapc 'set outshine-protected-variables outshine-protected-variables-values)

  ;; Show everything
  (outline-show-all)

  ;; Deactivate font-lock
  (outshine-unfontify))

;;;###autoload
(defun outshine-hook-function ()
  "DEPRECATED, use `outshine-mode'."
  (warn "`outshine-hook-function' has been deprecated, use `outshine-mode'")
  (outshine-mode 1))

(defun outshine--outline-minor-mode-hook ()
  "Deactivate `outshine-mode' if `outshine-mode' but not `outline-minor-mode'.

This function will be hooked to `outline-minor-mode'."
  (when (and outshine-mode
             (not outline-minor-mode))
    (outshine-mode 0)))

;;;; Functions

(defun outshine-mimic-org-log-note-marker ()
  (if (version< (org-version) "8.3")
      ;; `org-log-beginning' added in Org 8.3
      org-log-note-marker
    (with-current-buffer (marker-buffer org-log-note-marker)
      (goto-char org-log-note-marker)
      (copy-marker (org-log-beginning)))))

;;;;; Define keys with fallback

;; copied and adapted from Alexander Vorobiev
;; http://www.mail-archive.com/emacs-orgmode@gnu.org/msg70648.html
(defmacro outshine-define-key (keymap key def condition &optional mode)
  "Define key with fallback.

Binds KEY to definition DEF in keymap KEYMAP, the binding is
active when the CONDITION is true. Otherwise turns MODE off and
re-enables previous definition for KEY. If MODE is nil, tries to
recover it by stripping off \"-map\" from KEYMAP name.

DEF must be a quoted symbol of an interactive command.

This interns a named function `outshine-kbd-[key-name]' with the
appropriate docstring so that calling `describe-key' on KEY
produces a more informative output."
  (declare (indent defun))
  (let ((fn-name
         (intern (format "outshine-kbd-%s"
                         (if (eq (car-safe key) 'kbd)
                             (cadr key)
                           key))))
        (docstring
         (format "Run the interactive command `%s' if the following condition \
is satisfied:\n\n    %s\n
Otherwise, fallback to the original binding of %s in the current mode."
                 (cadr def) ;; def is a quoted symbol (quote sym)
                 condition key))
        (mode-name
         (cond (mode mode)
               ((string-match
                 (rx (group (1+ any)) "-map" eol) (symbol-name keymap))
                (intern (match-string 1 (symbol-name keymap))))
               (t (error "Could not deduce mode name from keymap name")))))
    `(progn
       (defun ,fn-name ()
         ,docstring
         (interactive)
         (call-interactively
          (if ,condition
              ,def
            ;; turn mode off and recover the original function
            (let ((,mode-name nil))
              (or (key-binding ,key)
                  ,(if (equal (kbd "<tab>") key)
                       (key-binding (kbd "TAB")))
                  (lambda nil (interactive) (message "`%s' can do nothing useful here." (key-description ,key))))))))
       (define-key ,keymap ,key (quote ,fn-name)))))

;;;;;; original macro (obsolete)

;; Note: the new macro uses a quoted symbol for the binding DEF, matching
;; the signature of `define-key'.
(make-obsolete 'outshine-define-key-with-fallback 'outshine-define-key "3.0")
(defmacro outshine-define-key-with-fallback
    (keymap key def condition &optional mode)
  "Define key with fallback.
Binds KEY to definition DEF in keymap KEYMAP, the binding is
active when the CONDITION is true. Otherwise turns MODE off and
re-enables previous definition for KEY. If MODE is nil, tries to
recover it by stripping off \"-map\" from KEYMAP name."
  (declare (indent 2))
  `(define-key
     ,keymap
     ,key
     (lambda (&optional arg)
       (interactive "P")
       (if ,condition ,def
         (let* ((,(if mode mode
                    (let* ((keymap-str (symbol-name keymap))
                           (mode-name-end
                            (- (string-width keymap-str) 4)))
                      (if (string=
                           "-map"
                           (substring keymap-str mode-name-end))
                          (intern (substring keymap-str 0 mode-name-end))
                        (message
                         "Could not deduce mode name from keymap name")
                        (intern "dummy-sym"))
                      )) nil)
                ;; Check for `<tab>'.  It translates to `TAB' which
                ;; will prevent `(key-binding ...)' from finding the
                ;; original binding.
                (original-func (if (equal (kbd "<tab>") ,key)
                                   (or (key-binding ,key)
                                       (key-binding (kbd "TAB")))
                                 (key-binding ,key))))
           (condition-case nil
               (call-interactively original-func)
             (error nil)))))))

;;;;; Normalize regexps

;; from http://emacswiki.org/emacs/ElispCookbook#toc6
(defun outshine-chomp (str)
  "Chomp leading and trailing whitespace from STR."
  (save-excursion
    (save-match-data
      (while (string-match
              "\\`\n+\\|^\\s-+\\|\\s-+$\\|\n+\\'"
              str)
        (setq str (replace-match "" t t str)))
      str)))

(defun outshine-set-outline-regexp-base ()
  "Return the actual outline-regexp-base."
  (if (and
       (not (outshine-modern-header-style-in-elisp-p))
       (eq major-mode 'emacs-lisp-mode))
      (progn
        (setq outshine-enforce-no-comment-padding-p t)
        (setq outshine-regexp-base
              outshine-oldschool-elisp-outline-regexp-base))
    (setq outshine-enforce-no-comment-padding-p nil)
    (setq outshine-regexp-base
          outshine-default-outline-regexp-base)))

(defun outshine-normalize-regexps ()
  "Chomp leading and trailing whitespace from outline regexps."
  (and comment-start
       (setq outshine-normalized-comment-start
             (if outshine-preserve-delimiter-whitespace
                 comment-start
               (outshine-chomp comment-start))))
  (and comment-end
       (setq outshine-normalized-comment-end
             (outshine-chomp comment-end)))
  (and outshine-regexp-base
       (setq outshine-normalized-outline-regexp-base
             (outshine-chomp outshine-regexp-base))))

;;;;; Calculate outline-regexp and outline-level

;; dealing with special case of oldschool headers in elisp (;;;+)
(defun outshine-modern-header-style-in-elisp-p (&optional buffer)
  "Return nil, if there is no match for a outshine-style header.
Searches in BUFFER if given, otherwise in current buffer."
  (let ((buf (or buffer (current-buffer))))
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (re-search-forward
         ;; (format "^;; [%s]+ " outshine-regexp-base-char)
         (format "^;; [%s]\\{1,%d\\} "
                 outshine-regexp-base-char outshine-max-level)
         nil 'NOERROR)))))

(defun outshine-calc-comment-region-starter ()
  "Return comment-region starter as string.
Based on `comment-start' and `comment-add'."
  (if (or (not comment-add) (eq comment-add 0))
      outshine-normalized-comment-start
    (let ((comment-add-string outshine-normalized-comment-start))
      (dotimes (i comment-add comment-add-string)
        (setq comment-add-string
              (concat comment-add-string outshine-normalized-comment-start))))))

(defun outshine-calc-comment-padding ()
  "Return comment-padding as string"
  (cond
   ;; comment-padding is nil
   ((not comment-padding) " ")
   ;; comment-padding is integer
   ((integer-or-marker-p comment-padding)
    (let ((comment-padding-string ""))
      (dotimes (i comment-padding comment-padding-string)
        (setq comment-padding-string
              (concat comment-padding-string " ")))))
   ;; comment-padding is string
   ((stringp comment-padding)
    comment-padding)
   (t (error "No valid comment-padding"))))

(defun outshine-calc-outline-regexp ()
  ;; FIXME: Rename function.
  "Return the outline regexp for the current mode."
  (concat (when (and outshine-regexp-outcommented-p
                     (or comment-start
                         ;; MAYBE: Should this be `warn'?
                         (message (concat "Cannot calculate outcommented outline-regexp without `comment-start' character defined"))))
            (concat (regexp-quote (outshine-calc-comment-region-starter))
                    (if outshine-enforce-no-comment-padding-p
                        ""
                      (outshine-calc-comment-padding))))
          outshine-normalized-outline-regexp-base
          " "))

;; TODO how is this called (match-data?) 'looking-at' necessary?
(defun outshine-calc-outline-level ()
  "Calculate the right outline level for the
  outshine-regexp"
  (save-excursion
    (save-match-data
      (and
       (looking-at (outshine-calc-outline-regexp))
       ;; ;; FIXME this works?
       ;; (looking-at outline-regexp)
       (let ((m-strg (match-string-no-properties 0)))
         (if outshine-enforce-no-comment-padding-p
             ;; deal with oldschool elisp headings (;;;+)
             (setq m-strg
                   (split-string
                    (substring m-strg 2)
                    nil
                    'OMIT-NULLS))
           ;; orgmode style elisp heading (;; *+)
           (setq m-strg
                 (split-string
                  m-strg
                  (format "%s" outshine-normalized-comment-start)
                  'OMIT-NULLS)))
         (length
          (mapconcat
           (lambda (str)
             (car
              (split-string
               str
               " "
               'OMIT-NULLS)))
           m-strg
           "")))
       ))))

;;;;; Set outline-regexp and outline-level

(defun outshine-set-local-outline-regexp-and-level
    (start-regexp &optional level-fn end-regexp)
  "Set `outline-regexp' locally to START-REGEXP.
Optionally set `outline-level' to LEVEL-FN and
`outline-heading-end-regexp' to END-REGEXP."
  (setq-local outline-regexp start-regexp)
  (when level-fn
    (setq-local outline-level level-fn))
  (when end-regexp
    (setq-local outline-heading-end-regexp end-regexp)))

;;;;; Show number of lines in hidden body

;; Calc and show line number of hidden body for all visible headlines
(defun outshine-write-hidden-lines-cookies ()
  "Show line number of hidden lines in folded headline."
  (and outshine-show-hidden-lines-cookies-p
       (save-excursion
         (goto-char (point-min))
         (and (outline-on-heading-p)
              (outshine-hidden-lines-cookie-status-changed-p)
              (outshine-set-hidden-lines-cookie))
         (while (not (eobp))
           (outline-next-visible-heading 1)
           (and (outline-on-heading-p)
                (outshine-hidden-lines-cookie-status-changed-p)
                (outshine-set-hidden-lines-cookie))))))

(defun outshine-hidden-lines-cookie-status-changed-p ()
  "Return non-nil if hidden-lines cookie needs modification."
  (save-excursion
    (save-match-data
      (or (not (outshine-body-visible-p))
          (re-search-forward
           outshine-hidden-lines-cookie-format-regexp
           (line-end-position)
           'NO-ERROR)))))

(defun outshine-set-hidden-lines-cookie ()
  "Calculate and set number of hidden lines in folded headline."
  (let* ((folded-p (not (outshine-body-visible-p)))
         (line-num-current-header (line-number-at-pos))
         (line-num-next-visible-header
          (save-excursion
            (outline-next-visible-heading 1)
            (line-number-at-pos)))
         (body-lines
          (1- (- line-num-next-visible-header line-num-current-header))))
    (if (re-search-forward
         outshine-hidden-lines-cookie-format-regexp
         (line-end-position)
         'NO-ERROR)
        (cond
         ((not folded-p) (replace-match ""))
         (folded-p (replace-match (format "%s" body-lines) nil nil nil 2)))
      (outline-show-entry)
      (save-excursion
        (end-of-line)
        (insert
         (format
          " %s%s%s%s%s"
          outshine-hidden-lines-cookie-left-delimiter
          outshine-hidden-lines-cookie-left-signal-char
          body-lines
          outshine-hidden-lines-cookie-right-signal-char
          outshine-hidden-lines-cookie-right-delimiter)))
      (outline-hide-entry))))
;; ;; FIXME
;; ;; outline-flag-region: Variable binding depth exceeds max-specpdl-size
;; (add-hook 'outline-view-change-hook
;;           'outshine-write-hidden-lines-cookies)

;;;;; Return outline-string at given level

(defun outshine-calc-outline-string-at-level (level)
  "Return outline-string at level LEVEL."
  (let ((base-string (outshine-calc-outline-base-string-at-level level)))
    (if (not outshine-regexp-outcommented-p)
        base-string
      (concat (outshine-calc-comment-region-starter)
              (if outshine-enforce-no-comment-padding-p
                  ""
                (outshine-calc-comment-padding))
              base-string
              " "))))

(defun outshine-calc-outline-base-string-at-level (level)
  "Return outline-base-string at level LEVEL."
  (let* ((star (outshine-transform-normalized-outline-regexp-base-to-string))
         (stars star))
    (dotimes (i (1- level) stars)
      (setq stars (concat stars star)))))

(defun outshine-transform-normalized-outline-regexp-base-to-string ()
  "Transform 'outline-regexp-base' to string by stripping off special chars."
  (replace-regexp-in-string
   outshine-regexp-special-chars
   ""
   outshine-normalized-outline-regexp-base))

;; make demote/promote from `outline-magic' work
(defun outshine-make-promotion-headings-list (max-level)
  "Make a sorted list of headings used for promotion/demotion commands.
Set this to a list of MAX-LEVEL headings as they are matched by `outline-regexp',
top-level heading first."
  (let ((list-of-heading-levels
         `((,(outshine-calc-outline-string-at-level 1) . 1))))
    (dotimes (i (1- max-level) list-of-heading-levels)
      (add-to-list
       'list-of-heading-levels
       `(,(outshine-calc-outline-string-at-level (+ i 2)) . ,(+ i 2))
       'APPEND))))

;;;;; Fontify the headlines

(defsubst outshine-font-lock-flush ()
  "Calls `font-lock-flush' or equivalent.
Compatibility with Emacs versions <25."
  (if (fboundp #'font-lock-flush)
      (font-lock-flush)
    ;; Copied from Emacs 25 font-lock.el, changed to call
    ;; `jit-lock-refontify' directly
    (and font-lock-mode
         font-lock-fontified
         (jit-lock-refontify))))

(defun outshine-fontify-headlines (outline-regexp)
  "Calculate heading regexps for font-lock mode."
  (let* ((outline-rgxp (substring outline-regexp 0 -8))
         (heading-1-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{1\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (heading-2-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{2\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (heading-3-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{3\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (heading-4-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{4\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (heading-5-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{5\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (heading-6-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{6\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (heading-7-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{7\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (heading-8-regexp
          (format "%s%s%s%s"
                  outline-rgxp
                  "\\{8\\} \\(.*"
                  (if outshine-fontify-whole-heading-line "\n?" "")
                  "\\)"))
         (font-lock-new-keywords
          `((,heading-1-regexp 1 'outshine-level-1 t)
            (,heading-2-regexp 1 'outshine-level-2 t)
            (,heading-3-regexp 1 'outshine-level-3 t)
            (,heading-4-regexp 1 'outshine-level-4 t)
            (,heading-5-regexp 1 'outshine-level-5 t)
            (,heading-6-regexp 1 'outshine-level-6 t)
            (,heading-7-regexp 1 'outshine-level-7 t)
            (,heading-8-regexp 1 'outshine-level-8 t))))

    (add-to-list 'outshine-font-lock-keywords font-lock-new-keywords)
    (font-lock-add-keywords nil font-lock-new-keywords)
    (outshine-font-lock-flush)))

(defun outshine-unfontify ()
  "Remove existing fontification."

  (font-lock-remove-keywords nil (car outshine-font-lock-keywords))
  (setq outshine-font-lock-keywords nil)
  (outshine-font-lock-flush))

;;;;;; Functions for speed-commands

(defun outshine-defkey (keymap key def)
  "Define a KEY in a KEYMAP with definition DEF."
  (define-key keymap key def))

(defun outshine-remap (map &rest commands)
  "In MAP, remap the functions given in COMMANDS.
COMMANDS is a list of alternating OLDDEF NEWDEF command names."
  (let (new old)
    (while commands
      (setq old (pop commands) new (pop commands))
      (if (fboundp 'command-remapping)
          (outshine-defkey map (vector 'remap old) new)
        (substitute-key-definition old new map global-map)))))

(outshine-remap outshine-mode-map
                'self-insert-command 'outshine-self-insert-command)

;;;;;; Functions for hiding comment-subtrees

(defun outshine-hide-comment-subtrees-in-region (beg end)
  "Re-hide all comment subtrees after a visibility state change."
  (save-excursion
    (let* ((re (concat ":" outshine-comment-tag ":")))
      (goto-char beg)
      (while (re-search-forward re end t)
        (when (outline-on-heading-p t)
          (outshine-flag-subtree t)
          (outline-end-of-subtree))))))

(defun outshine-flag-subtree (flag)
  (save-excursion
    (outline-back-to-heading t)
    (outline-end-of-heading)
    (outline-flag-region (point)
                         (progn (outline-end-of-subtree) (point))
                         flag)))

(defun outshine-hide-comment-subtrees ()
  "Re-hide all comment subtrees after a visibility state change."
  (let ((state outshine-current-buffer-visibility-state))
    (when (and (not outshine-open-comment-trees)
               (not (memq state '(overview folded))))
      (save-excursion
        (let* ((globalp (memq state '(contents all)))
               (beg (if globalp
                        (point-min)
                      (point)))
               (end (if globalp
                        (point-max)
                      (outline-end-of-subtree))))
          (outshine-hide-comment-subtrees-in-region beg end)
          (goto-char beg)
          (when (looking-at (concat ".*:" outshine-comment-tag ":"))
            (message "%s" (substitute-command-keys "Subtree is tagged as comment and stays closed.  Use \\[outshine-force-cycle-comment] to cycle anyway."))))))))

;; ;; FIXME max-lisp-eval-depth exceeded error when turned on
;; ;; with max-lisp-eval-depth set to 600
;; (add-hook 'outline-view-change-hook
;;        'outshine-hide-comment-subtrees)

(defun outshine-comment-region (beg end &optional arg)
  "Use comment-style that always inserts at BOL.
Call `comment-region' with a comment-style that guarantees
   insertion of comment-start markers at beginning-of-line."
  (interactive "r")
  (let ((comment-style
         (if (member comment-style '(indent-or-triple indent))
             'plain
           comment-style)))
    (comment-region beg end arg)))

;;;;;; Additional outline functions

;;;;;;  Functions from `outline-magic'

;; FIXME: Use Org or outline- replacements for as many of these as possible.

(defun outshine-cycle-emulate-tab ()
  "Check if TAB should be emulated at the current position."
  ;; This is called after the check for point in a headline,
  ;; so we can assume we are not in a headline
  (if (and (eq outshine-cycle-emulate-tab 'white)
           (save-excursion
             (beginning-of-line 1) (looking-at "[ \t]+$")))
      t
    outshine-cycle-emulate-tab))

(defun outshine-change-level (delta)
  "Workhorse for `outline-demote' and `outline-promote'."
  (let* ((headlist (outshine-headings-list))
         (atom (outshine-headings-atom headlist))
         (re (concat "^" outline-regexp))
         (transmode (and transient-mark-mode mark-active))
         beg end)

    ;; Find the boundaries for this operation
    (save-excursion
      (if transmode
          (setq beg (min (point) (mark))
                end (max (point) (mark)))
        (outline-back-to-heading)
        (setq beg (point))
        (outline-end-of-heading)
        (outline-end-of-subtree)
        (setq end (point)))
      (setq beg (move-marker (make-marker) beg)
            end (move-marker (make-marker) end))

      (let (head newhead level newlevel static)

        ;; First a dry run to test if there is any trouble ahead.
        (goto-char beg)
        (while (re-search-forward re end t)
          (outshine-change-heading headlist delta atom 'test))

        ;; Now really do replace the headings
        (goto-char beg)
        (while (re-search-forward re end t)
          (outshine-change-heading headlist delta atom))))))

(defun outshine-headings-list ()
  "Return a list of relevant headings, either a user/mode defined
list, or an alist derived from scanning the buffer."
  (let (headlist)
    (cond
     (outshine-promotion-headings
      ;; configured by the user or the mode
      (setq headlist outshine-promotion-headings))

     ((and (eq major-mode 'outline-mode) (string= outline-regexp "[*\^L]+"))
      ;; default outline mode with original regexp
      ;; this need special treatment because of the \f in the regexp
      (setq headlist '(("*" . 1) ("**" . 2))))  ; will be extrapolated

     (t ;; Check if the buffer contains a complete set of headings
      (let ((re (concat "^" outline-regexp)) head level)
        (save-excursion
          (goto-char (point-min))
          (while (re-search-forward re nil t)
            (save-excursion
              (beginning-of-line 1)
              (setq head (outshine-cleanup-match (match-string 0))
                    level (funcall outline-level))
              (add-to-list  'headlist (cons head level))))))
      ;; Check for uniqueness of levels in the list
      (let* ((hl headlist) entry level seen nonunique)
        (while (setq entry (car hl))
          (setq hl (cdr hl)
                level (cdr entry))
          (if (and (not (outshine-static-level-p level))
                   (member level seen))
              ;; We have two entries for the same level.
              (add-to-list 'nonunique level))
          (add-to-list 'seen level))
        (if nonunique
            (error "Cannot promote/demote: non-unique headings at level %s\nYou may want to configure `outline-promotion-headings'."
                   (mapconcat 'int-to-string nonunique ","))))))
    ;; OK, return the list
    headlist))

(defun outshine-change-heading (headlist delta atom &optional test)
  "Change heading just matched by `outline-regexp' by DELTA levels.
HEADLIST can be either an alist ((\"outline-match\" . level)...) or a
straight list like `outshine-promotion-headings'. ATOM is a character
if all headlines are composed of a single character.
If TEST is non-nil, just prepare the change and error if there are problems.
TEST nil means, really replace old heading with new one."
  (let* ((head (outshine-cleanup-match (match-string 0)))
         (level (save-excursion
                  (beginning-of-line 1)
                  (funcall outline-level)))
         (newhead  ; compute the new head
          (cond
           ((= delta 0) t)
           ((outshine-static-level-p level) t)
           ((null headlist) nil)
           ((consp (car headlist))
            ;; The headlist is an association list
            (or (car (rassoc (+ delta level) headlist))
                (and atom
                     (> (+ delta level) 0)
                     (make-string (+ delta level) atom))))
           (t
            ;; The headlist is a straight list - grab the correct element.
            (let* ((l (length headlist))
                   (n1 (- l (length (member head headlist)))) ; index old
                   (n2 (+ delta n1)))                         ; index new
              ;; Careful checking
              (cond
               ((= n1 l) nil)                ; head not found
               ((< n2 0) nil)                ; newlevel too low
               ((>= n2 l) nil)               ; newlevel too high
               ((let* ((tail (nthcdr (min n1 n2) headlist))
                       (nilpos (- (length tail) (length (memq nil tail)))))
                  (< nilpos delta))          ; nil element between old and new
                nil)
               (t (nth n2 headlist))))))))      ; OK, we have a match!
    (if (not newhead)
        (error "Cannot shift level %d heading \"%s\" to level %d"
               level head (+ level delta)))
    (if (and (not test) (stringp newhead))
        (save-excursion
          (beginning-of-line 1)
          (or (looking-at (concat "[ \t]*\\(" (regexp-quote head) "\\)"))
              (error "Please contact maintainer"))
          (replace-match (outshine-cleanup-match newhead) t t nil 1)))))

(defun outshine-headings-atom (headlist)
  "Use the list created by `outshine-headings-list' and check if all
headings are polymers of a single character, e.g. \"*\".
If yes, return this character."
  (if (consp (car headlist))
      ;; this is an alist - it makes sense to check for atomic structure
      (let ((re (concat "\\`"
                        (regexp-quote (substring (car (car headlist)) 0 1))
                        "+\\'")))
        (if (not (delq nil (mapcar (lambda (x) (not (string-match re (car x))))
                                   headlist)))
            (string-to-char (car (car headlist)))))))

(defun outshine-cleanup-match (s)
  "Remove text properties and start/end whitespace from a string."
  (set-text-properties 1 (length s) nil s)
  (save-match-data
    (if (string-match "^[ \t]+" s) (setq s (replace-match "" t t s)))
    (if (string-match "[ \t]+$" s) (setq s (replace-match "" t t s))))
  s)

(defun outshine-static-level-p (level)
  "Test if a level should not be changed by level promotion/demotion."
  (>= level 1000))

;;;;;; Special Case Latex-Mode

;; (defun outshine-get-latex-documentclass (&optional buf-or-name no-check-p)
;;   "Return latex document class of current-buffer.
;; If BUF-OR-NAME is non-nil, use it instead of current buffer. If
;; NO-CHECK-P is non-nil, assume BUF-OR-NAME is ok (i.e. live and in
;; latex-mode) and just use it."
;;   (catch 'exit
;;   (let ((buf (cond
;;            ((and buf-or-name no-check-p) buf-or-name)
;;            ((and buf-or-name
;;                  (buffer-live-p buf-or-name)
;;                  (with-current-buffer buf-or-name
;;                    (eq major-mode 'latex-mode)))
;;             buf-or-name)
;;            ((eq major-mode 'latex-mode) (current-buffer))
;;            (t (throw 'exit nil)))))
;;     (with-current-buffer buf
;;       (save-excursion
;;      (save-restriction
;;        (widen)
;;        (goto-char (point-min))
;;        (re-search-forward outshine-latex-documentclass-regexp
;;                           nil 'NOERROR 1)
;;        (org-no-properties (match-string 1))))))))

;;;;;; Agenda Functions

;; (defun outshine-agenda-create-temporary-agenda-file (&optional restriction-lock buf-or-name pos)
;;   "Create a single temporary outshine agenda file.

;; Concatenate all `outshine-agenda-files', after converting them to
;; Org-mode, into a single Org file in the
;; `outshine-temporary-directory'. Return that file's
;; buffer-file-name.

;; When uncommenting this section, `outshine-temporary-directory' needs to be uncommented as well
;; If this section is removed, please remove `outshine-temporary-directory' as well

;; When RESTRICTION-LOCK is given, act conditional on its value:

;;  - file :: (symbol) restrict to buffer

;;  - t :: (any) restrict to subtree

;; Use current-buffer and point position, unless BUF-OR-NAME and/or
;; POS are non-nil."
;;   (let* ((temporary-file-directory outshine-temporary-directory)
;;       (curr-agenda-file (make-temp-file "outshine-" nil ".org"))
;;       (buf (if (and buf-or-name (buffer-file-name buf-or-name))
;;                buf-or-name
;;              (current-buffer)))
;;       (pos (if (and pos (integer-or-marker-p pos)
;;                     (<= pos (buffer-size buf)))
;;                pos
;;              (point))))
;;     (with-current-buffer (find-file-noselect curr-agenda-file)
;;       (cond
;;        ((eq restriction-lock 'file)
;;      (insert
;;       (with-current-buffer buf
;;         (outshine-get-outorg-edit-buffer-content))))
;;        (restriction-lock
;;      (insert
;;       (with-current-buffer buf
;;         (save-excursion
;;           (goto-char pos)
;;           (save-restriction
;;             (outshine-narrow-to-subtree)
;;             (outshine-get-outorg-edit-buffer-content))))))
;;        (t (mapc
;;         (lambda (--file)
;;           (insert
;;            (outshine-get-outorg-edit-buffer-content --file))
;;           (forward-line 2))
;;         outshine-agenda-files)))
;;       (save-buffer)
;;       (kill-buffer))
;;     curr-agenda-file))

;; ;; rather obsolete - better use agenda restriction lock
;; (defun outshine-agenda-set-org-agenda-files (&rest file-lst)
;;   "Set `org-agenda-files' to FILE-LST.
;; Store old value in `outshine-agenda-old-org-agenda-files'."
;;   (setq outshine-agenda-old-org-agenda-files org-agenda-files)
;;   (setq org-agenda-files file-lst))

;; ;; rather obsolete - better use agenda restriction lock
;; (defun outshine-agenda-restore-org-agenda-files ()
;;   "Restore `org-agenda-files'.
;; The old value is stored in
;; `outshine-agenda-old-org-agenda-files'."
;;   (setq org-agenda-files outshine-agenda-old-org-agenda-files)
;;   (setq outshine-agenda-old-org-agenda-files nil))

;;;;;; Commands
;;;;;; Additional outline commands
;;;;;; Commands from `outline-magic'

(defun outshine-next-line ()
  "Forward line, but move over invisible line ends.
Essentially a much simplified version of `next-line'."
  (interactive)
  (beginning-of-line 2)
  (while (and (not (eobp))
              (get-char-property (1- (point)) 'invisible))
    (beginning-of-line 2)))

(defun outshine-cycle (&optional arg)
  "Visibility cycling for `outshine-mode'.

The behavior of this command is determined by the first matching
condition among the following:

 1. When point is at the beginning of the buffer, or when called
    with a `\\[universal-argument]' universal argument, rotate the entire buffer
    through 3 states:

   - OVERVIEW: Show only top-level headlines.
   - CONTENTS: Show all headlines of all levels, but no body text.
   - SHOW ALL: Show everything.

 2. When point is at the beginning of a headline, rotate the
    subtree starting at this line through 2 or 3 different states:

   - FOLDED:   Only the main headline is shown.
   - CHILDREN: The main headline and its direct children are shown.
               From this state, you can move to one of the children
               and zoom in further.
               * If the heading has no direct children, this state
               is skipped entirely.
   - SUBTREE:  Show the entire subtree, including body text.

 3. Otherwise, execute `indent-relative', like TAB normally does.

The behavior of this function is modified by the following
variables: `outshine-cycle-emulate-tab` and
`outshine-org-style-global-cycling-at-bob-p`, which see."
  (interactive "P")
  (setq deactivate-mark t)
  (cond
   ;; Beginning of buffer or called with C-u: Global cycling
   ((or (equal arg '(4))
        (and (bobp)
             (or
              ;; outline-magic style behaviour - always global cycle at bob
              (not outshine-org-style-global-cycling-at-bob-p)
              ;; org-mode style behaviour - only cycle if not on a heading
              (not (outline-on-heading-p)))))
    (outshine-cycle-buffer))

   ;; At a heading: rotate between three different views
   ((save-excursion (beginning-of-line 1) (looking-at outline-regexp))
    (outline-back-to-heading)
    (let* ((goal-column 0)
           ;; First, some boundaries
           (eol (save-excursion (outshine-next-line) (point)))
           (eoh (save-excursion (outline-end-of-heading) (point)))
           (eos (save-excursion (outline-end-of-subtree) (point)))
           (has-children ;; nil if no other heading between heading and end of subtree
            (save-excursion (end-of-line)
                            (re-search-forward outline-regexp eos 'noerror))))
      ;; Find out what to do next and set `this-command'
      (cond
       ((= eos eoh)
        ;; Nothing is hidden behind this heading
        (outshine--cycle-message "EMPTY ENTRY"))
       ((>= eol eos)
        ;; Entire subtree is hidden in one line: open it
        (if has-children
            (progn
              (outline-show-entry)
              (outline-show-children)
              (outshine--cycle-message "CHILDREN")
              (setq this-command 'outshine-cycle-children))
          (outline-show-subtree)
          (outshine--cycle-message "SUBTREE (NO CHILDREN)")))
       ((eq last-command 'outshine-cycle-children)
        ;; We just showed the children, now show everything.
        (outline-show-subtree)
        (outshine--cycle-message "SUBTREE"))
       (t
        ;; Default action: hide the subtree.
        (outline-hide-subtree)
        (outshine--cycle-message "FOLDED")))))

   ;; Not at a headline: TAB emulation
   ((outshine-cycle-emulate-tab)
    (indent-relative))

   (t (outline-back-to-heading))))

(defun outshine-cycle-buffer (&optional arg)
  "Rotate the visibility state of the buffer through 3 states:
  - OVERVIEW: Show only top-level headlines.
  - CONTENTS: Show all headlines of all levels, but no body text.
  - SHOW ALL: Show everything.

With a numeric prefix ARG, show all headlines up to that level."
  (interactive "P")
  (save-excursion
    (cond
     ((integerp arg)
      (outline-show-all)
      (outline-hide-sublevels arg))
     ((eq last-command 'outshine-cycle-overview)
      ;; We just created the overview - now do table of contents
      ;; This can be slow in very large buffers, so indicate action
      (outshine--cycle-message "CONTENTS...")
      ;; Visit all headings and show their offspring
      (goto-char (point-max))
      (while (not (bobp))
        (condition-case nil
            (progn
              (outline-previous-visible-heading 1)
              (outline-show-branches))
          (error (goto-char (point-min)))))
      (outshine--cycle-message "CONTENTS...done")
      (setq this-command 'outshine-cycle-toc
            outshine-current-buffer-visibility-state 'contents))
     ((eq last-command 'outshine-cycle-toc)
      ;; We just showed the table of contents - now show everything
      (outline-show-all)
      (outshine--cycle-message "SHOW ALL")
      (setq this-command 'outshine-cycle-showall
            outshine-current-buffer-visibility-state 'all))
     (t
      ;; Default action: go to overview
      (let ((toplevel
             (cond
              (current-prefix-arg
               (prefix-numeric-value current-prefix-arg))
              ((save-excursion
                 (beginning-of-line)
                 (looking-at outline-regexp))
               (max 1 (save-excursion (beginning-of-line) (funcall outline-level))))
              (t 1))))
        (outline-hide-sublevels toplevel))
      (outshine--cycle-message "OVERVIEW")
      (setq this-command 'outshine-cycle-overview
            outshine-current-buffer-visibility-state 'overview)))))

(defun outshine--cycle-message (msg)
  "Display MSG, but avoid logging it in the *Messages* buffer."
  (unless outshine-cycle-silently
    (let ((message-log-max nil))
      (message msg))))

(defun outshine-toggle-silent-cycling (&optional arg)
  "Toggle silent cycling between visibility states.

  When silent cycling is off, visibility state-change messages are
  displayed in the minibuffer but not logged to the *Messages* buffer.
  With prefix argument ARG, cycle silently if ARG is positive,
  otherwise write state-change messages."
  (interactive "P")
  (setq outshine-cycle-silently
        (if (null arg)
            (not outshine-cycle-silently)
          (> (prefix-numeric-value arg) 0)))
  (message "Silent visibility cycling %s"
           (if outshine-cycle-silently "enabled" "disabled")))

;;;;;; Commands from `outline-mode-easy-bindings'

;; Copied from: http://emacswiki.org/emacs/OutlineMinorMode

(defun outshine-body-p ()
  (save-excursion
    (outline-back-to-heading)
    (outline-end-of-heading)
    (and (not (eobp))
         (progn (forward-char 1)
                (not (outline-on-heading-p))))))

(defun outshine-body-visible-p ()
  (save-excursion
    (outline-back-to-heading)
    (outline-end-of-heading)
    (not (outline-invisible-p))))

(defun outshine-subheadings-p ()
  (save-excursion
    (outline-back-to-heading)
    (let ((level (funcall outline-level)))
      (outline-next-heading)
      (and (not (eobp))
           (< level (funcall outline-level))))))

(defun outshine-subheadings-visible-p ()
  (interactive)
  (save-excursion
    (outline-next-heading)
    (not (outline-invisible-p))))

(defun outshine-hide-more ()
  (interactive)
  (when (outline-on-heading-p)
    (cond ((and (outshine-body-p)
                (outshine-body-visible-p))
           (outline-hide-entry)
           (outline-hide-leaves))
          (t
           (outline-hide-subtree)))))

(defun outshine-show-more ()
  (interactive)
  (when (outline-on-heading-p)
    (cond ((and (outshine-subheadings-p)
                (not (outshine-subheadings-visible-p)))
           (outline-show-children))
          ((and (not (outshine-subheadings-p))
                (not (outshine-body-visible-p)))
           (outline-show-subtree))
          ((and (outshine-body-p)
                (not (outshine-body-visible-p)))
           (outline-show-entry))
          (t
           (outline-show-subtree)))))

;;;;;; Hidden-line-cookies commands

(defun outshine-show-hidden-lines-cookies ()
  "Show hidden-lines cookies for all visible and folded headlines."
  (interactive)
  (if outshine-show-hidden-lines-cookies-p
      (outshine-write-hidden-lines-cookies)
    (if (not (y-or-n-p "Activate hidden-lines cookies "))
        (message "Unable to show hidden-lines cookies - deactivated.")
      (outshine-toggle-hidden-lines-cookies-activation)
      (outshine-write-hidden-lines-cookies)))
  (setq outshine-hidden-lines-cookies-on-p 1))

(defun outshine-hide-hidden-lines-cookies ()
  "Delete all hidden-lines cookies."
  (interactive)
  (let* ((base-buf (point-marker))
         (indirect-buf-name
          (generate-new-buffer-name
           (buffer-name (marker-buffer base-buf)))))
    (unless outshine-show-hidden-lines-cookies-p
      (setq outshine-show-hidden-lines-cookies-p 1))
    (clone-indirect-buffer indirect-buf-name nil 'NORECORD)
    (save-excursion
      (switch-to-buffer indirect-buf-name)
      (outline-show-all)
      (let ((indirect-buf (point-marker)))
        (outshine-write-hidden-lines-cookies)
        (switch-to-buffer (marker-buffer base-buf))
        (kill-buffer (marker-buffer indirect-buf))
        (set-marker indirect-buf nil))
      (set-marker base-buf nil)))
  (setq outshine-hidden-lines-cookies-on-p nil))

(defun outshine-toggle-hidden-lines-cookies-activation ()
  "Toggles activation of hidden-lines cookies."
  (interactive)
  (if outshine-show-hidden-lines-cookies-p
      (progn
        (setq outshine-show-hidden-lines-cookies-p nil)
        (setq outshine-hidden-lines-cookies-on-p nil)
        (message "hidden-lines cookies are deactivated now"))
    (setq outshine-show-hidden-lines-cookies-p 1)
    (message "hidden-lines cookies are activated now")))

(defun outshine-toggle-hidden-lines-cookies ()
  "Toggles status of hidden-lines cookies between shown and hidden."
  (interactive)
  (if outshine-hidden-lines-cookies-on-p
      (outshine-hide-hidden-lines-cookies)
    (outshine-show-hidden-lines-cookies)))

;;;;;; Hide comment-subtrees

(defun outshine-insert-comment-subtree (&optional arg)
  "Insert new subtree that is tagged as comment."
  (interactive "P")
  (outshine-insert-heading)
  (save-excursion
    (insert (concat "  :" outshine-comment-tag ":"))))

;; Cycle comment subtrees anyway
(defun outshine-force-cycle-comment ()
  "Cycle subtree even if it comment."
  (interactive)
  (setq this-command 'outshine-cycle)
  (let ((outshine-open-comment-trees t))
    (call-interactively 'outshine-cycle)))

;;;;;; Speed commands utilities

(defun outshine-speed-move-safe (cmd)
  "Execute CMD, but make sure that the cursor always ends up in a headline.
If not, return to the original position and throw an error."
  (interactive)
  (let ((pos (point)))
    (call-interactively cmd)
    (unless (and (bolp) (outline-on-heading-p))
      (goto-char pos)
      (error "Boundary reached while executing %s" cmd))))

;;;;;; Other Commands

(defun outshine-eval-lisp-subtree ()
  "Mark subtree at point and call `eval-region' on it."
  (interactive)
  (save-excursion
    (outline-mark-subtree)
    (call-interactively 'eval-region)))

(defun outshine-comment-subtree-content ()
  "Mark subtree at point and call `comment-dwim' on its content."
  (interactive)
  (save-excursion
    (outline-mark-subtree)
    (forward-line)
    (call-interactively 'comment-dwim)))

(defun outshine-narrow-to-subtree ()
  "Narrow buffer to subtree at point."
  (interactive)
  (if (outline-on-heading-p)
      (progn
        (outline-mark-subtree)
        (and
         (use-region-p)
         (narrow-to-region (region-beginning) (region-end)))
        (deactivate-mark))
    (message "Not at headline, cannot narrow to subtree")))

(defun outshine-navi ()
  "Open or reuse *Navi* buffer for fast navigation.

Switch to associated read-only *Navi* buffer for fast and
convenient buffer navigation without changing visibility state of
original buffer. Type 'o' (M-x navi-goto-occurrence-other-window)
to switch from the new position in the *Navi* buffer to the same
position in the original buffer.

This function is the outshine replacement for `org-goto'."
  (interactive)
  (if (require 'navi-mode nil t)
      (navi-search-and-switch)
    (message "Install navi-mode.el for this command to work")))

;;;;;; Overridden outline commands

;; overriding 'outline-insert-heading'
;; copied and adapted form outline.el, taking into account modes
;; with 'comment-end' defined (as non-empty string).
(defun outshine-insert-heading ()
  "Insert a new heading at same depth at point.
This function takes `comment-end' into account."
  (interactive)
  (let* ((head-with-prop
          (save-excursion
            (condition-case nil
                (outline-back-to-heading)
              (error (outline-next-heading)))
            (if (eobp)
                (or (caar outline-heading-alist) "")
              (match-string 0))))
         (head (substring-no-properties head-with-prop))
         (com-end-p))
    (unless (or (string-match "[ \t]\\'" head)
                (not (string-match (concat "\\`\\(?:" outline-regexp "\\)")
                                   (concat head " "))))
      (setq head (concat head " ")))
    (unless (or (not comment-end) (string-equal "" comment-end))
      (setq head (concat head " " outshine-normalized-comment-end))
      (setq com-end-p t))
    (unless (bolp) (end-of-line) (newline))
    (insert head)
    (unless (eolp)
      (save-excursion (newline-and-indent)))
    (and com-end-p
         (re-search-backward outshine-normalized-comment-end)
         (forward-char -1))
    (run-hooks 'outline-insert-heading-hook)))

;;;;;; iMenu and idoMenu Support

(defun outshine-imenu-with-navi-regexp
    (kbd-key &optional PREFER-IMENU-P LAST-PARENTH-EXPR-P)
  "Enhanced iMenu/idoMenu support depending on `navi-mode'.

KBD-KEY is a single character keyboard-key defined as a
user-command for a keyword-search in `navi-mode'. A list of all
registered major-mode languages and their single-key commands can
be found in the customizable variable `navi-key-mappings'. The
regexps that define the keyword-searches associated with these
keyboard-keys can be found in the customizable variable
`navi-keywords'.

Note that all printable ASCII characters are predefined as
single-key commands in navi-mode, i.e. you can define
key-mappings and keywords for languages not yet registered in
navi-mode or add your own key-mappings and keywords for languages
already registered simply by customizing the two variables
mentioned above - as long as there are free keys available for
the language at hand. You need to respect navi-mode's own core
keybindings when doing so, of course.

Please share your own language definitions with the author so
that they can be included in navi-mode, resulting in a growing
number of supported languages over time.

If PREFER-IMENU-P is non-nil, this command calls `imenu' even if
`idomenu' is available.

By default, the whole string matched by the keyword-regexp plus the text
before the next space character is shown as result. If LAST-PARENTH-EXPR-P is
non-nil, only the last parenthetical expression in the match-data is shown,
i.e. the text following the regexp match until the next space character."
  ;; (interactive "cKeyboard key: ")
  (interactive
   (cond
    ((equal current-prefix-arg nil)
     (list (read-char "Key: ")))
    ((equal current-prefix-arg '(4))
     (list (read-char "Key: ")
           nil 'LAST-PARENTH-EXPR-P))
    ((equal current-prefix-arg '(16))
     (list (read-char "Key: ")
           'PREFER-IMENU-P 'LAST-PARENTH-EXPR-P))
    (t (list (read-char "Key: ")
             'PREFER-IMENU-P))))
  (if (require 'navi-mode nil 'NOERROR)
      (let* ((lang (car (split-string
                         (symbol-name major-mode)
                         "-mode" 'OMIT-NULLS)))
             (key (navi-map-keyboard-to-key
                   lang (char-to-string kbd-key)))
             (base-rgx (navi-get-regexp lang key))
             ;; (rgx (concat base-rgx "\\([^[:space:]]+[[:space:]]?$\\)"))
             (rgx (concat base-rgx "\\([^[:space:]]+[[:space:]]\\)"))
             (rgx-depth (regexp-opt-depth rgx))
             (outshine-imenu-generic-expression
              `((nil ,rgx ,(if LAST-PARENTH-EXPR-P rgx-depth 0))))
             (imenu-generic-expression
              outshine-imenu-generic-expression)
             (imenu-prev-index-position-function nil)
             (imenu-extract-index-name-function nil)
             (imenu-auto-rescan t)
             (imenu-auto-rescan-maxout 360000))
        ;; prefer idomenu
        (if (and (require 'idomenu nil 'NOERROR)
                 (not PREFER-IMENU-P))
            (funcall 'idomenu)
          ;; else call imenu
          (require 'imenu)
          (funcall 'imenu
                   (imenu-choose-buffer-index
                    (concat (car
                             (split-string
                              (symbol-name key) ":" 'OMIT-NULLS))
                            ": ")))))
    (message "Unable to load library `navi-mode.el'"))
  (setq imenu-generic-expression
        (or outshine-imenu-default-generic-expression
            outshine-imenu-preliminary-generic-expression)))

(defun outshine-imenu (&optional PREFER-IMENU-P)
  "Convenience function for calling imenu/idomenu from outshine."
  (interactive "P")
  (or outshine-imenu-default-generic-expression
      (setq outshine-imenu-default-generic-expression
            outshine-imenu-preliminary-generic-expression))
  (let* ((imenu-generic-expression
          outshine-imenu-default-generic-expression)
         (imenu-prev-index-position-function nil)
         (imenu-extract-index-name-function nil)
         (imenu-auto-rescan t)
         (imenu-auto-rescan-maxout 360000))
    ;; prefer idomenu
    (if (and (require 'idomenu nil 'NOERROR)
             (not PREFER-IMENU-P))
        (funcall 'idomenu)
      ;; else call imenu
      (funcall 'imenu
               (imenu-choose-buffer-index
                "Headline: ")))))

;;;;;; Special Case Latex-mode

(defun outshine-latex-insert-header (&optional buf-or-name pt-or-marker)
  "Insert outshine-header for section at point in latex-buffer.
Use current-buffer, unless BUF-OR-NAME is given. Move to
PT-OR-MARKER first if given."
  (interactive
   (when current-prefix-arg
     (list (read-buffer "Latex-buffer: "))))
  (catch 'exit-let
    (let* ((buf (cond
                 ((and buf-or-name
                       (buffer-live-p (get-buffer buf-or-name))
                       (with-current-buffer buf-or-name
                         (eq major-mode 'latex-mode)))
                  buf-or-name)
                 ((eq major-mode 'latex-mode) (current-buffer))
                 (t (throw 'exit-let nil))))
           (doc-class (outshine-get-latex-documentclass
                       buf 'NO-CHECK-P))
           (section-alist (cdr (assoc doc-class
                                      outshine-latex-classes))))
      (with-current-buffer buf
        (save-excursion
          (save-restriction
            (widen)
            (when pt-or-marker
              (goto-char pt-or-marker))
            (when (looking-at
                   (concat "^[[:space:]]*"
                           "\\("
                           "\\\\part{\\|"
                           "\\\\chapter{\\|"
                           "\\\\section{\\|"
                           "\\\\subsection{\\|"
                           "\\\\subsubsection{\\|"
                           "\\\\paragraph{\\|"
                           "\\\\subparagraph{"
                           "\\)"))
              (save-excursion
                (beginning-of-line)
                (let ((rgxps (mapcar 'cdr section-alist)))
                  (while rgxps
                    (let ((rgxp (pop rgxps)))
                      (when (looking-at rgxp)
                        (let ((title (match-string 1)))
                          (insert
                           (concat
                            "\n"
                            (outshine-calc-outline-string-at-level
                             (car
                              (rassoc rgxp section-alist)))
                            title
                            "\n"))
                          (setq rgxps nil))))))))))))))

(defun outshine-latex-insert-headers-in-buffer (&optional buf-or-name no-preamble-p)
  "Insert outshine-headers for all sections in latex-mode buffer.
Use current-buffer, unless BUF-OR-NAME is given. Add a 1st-level
preamble header unless NO-PREAMBLE-P is non-nil."
  (interactive
   (when current-prefix-arg
     (list (read-buffer "Latex-buffer: ")
           (y-or-n-p "Skip preamble "))))
  (catch 'exit-let
    (let* ((buf (cond
                 ((and buf-or-name
                       (buffer-live-p (get-buffer buf-or-name))
                       (with-current-buffer buf-or-name
                         (eq major-mode 'latex-mode)))
                  buf-or-name)
                 ((eq major-mode 'latex-mode) (current-buffer))
                 (t (throw 'exit-let nil))))
           (doc-class (outshine-get-latex-documentclass
                       buf 'NO-CHECK-P))
           (section-alist (cdr (assoc doc-class
                                      outshine-latex-classes))))
      (with-current-buffer buf
        (save-excursion
          (save-restriction
            (widen)
            (goto-char (point-min))
            (unless no-preamble-p
              (insert
               (concat
                (outshine-calc-outline-string-at-level 1)
                "Preamble\n")))
            (while (re-search-forward
                    (concat
                     "\\("
                     "\\\\part{\\|"
                     "\\\\chapter{\\|"
                     "\\\\section{\\|"
                     "\\\\subsection{\\|"
                     "\\\\subsubsection{\\|"
                     "\\\\paragraph{\\|"
                     "\\\\subparagraph{"
                     "\\)") nil t)
              (save-excursion
                (beginning-of-line)
                (let ((rgxps (mapcar 'cdr section-alist)))
                  (while rgxps
                    (let ((rgxp (pop rgxps)))
                      (when (looking-at rgxp)
                        (let ((title (match-string 1)))
                          (insert
                           (concat
                            "\n"
                            (outshine-calc-outline-string-at-level
                             (car
                              (rassoc rgxp section-alist)))
                            title
                            "\n"))
                          (setq rgxps nil))))))))))))))

(defun outshine-TeX-command-region-on-subtree (&optional arg)
  "Mark subtree and run `TeX-command-region'.
With one prefix ARG, try to move up one level before marking the
subtree, with two prefix ARGs, try to move up two levels before
marking subtree (and subsequently run the tex command)."
  (interactive "p")
  (save-excursion
    (cl-case arg
      (4 (ignore-errors
           (outline-up-heading 1 t)))
      (16 (ignore-errors
            (outline-up-heading 2 t)))
      (t nil))
    (message "%s" (point))
    (outline-mark-subtree)
    (call-interactively 'TeX-command-region))
  (deactivate-mark))

;;; Menus and Keybindings

;; FIXME
;; From: Stefan Monnier <monnier@iro.umontreal.ca>
;; Subject: Re: Commands with more than one keybinding in menus
;; Newsgroups: gmane.emacs.help
;; To: help-gnu-emacs@gnu.org
;; Date: Wed, 14 Aug 2013 12:23:12 -0400 (4 minutes, 20 seconds ago)
;; Organization: A noiseless patient Spider

;; > The macro was offered by a user of outshine, I only fiddled around with
;; > it until it worked without errors. It serves its purpose, because
;; > without it a minor-mode, unconditionally defining 'M-[S-]<arrow-key>'
;; > bindings, runs a high risk of breaking major-mode or user settings - I
;; > would not want to do without it.

;; There are a few ways to have your cake and eat it too:
;; - Move the conditional test into the command, so the menu entries are
;;   bound to the same command as the keys.  If you want the menu-entries
;;   to skip the test, then you can do that by checking the event(s) that
;;   triggered the command.
;; - You can use ":keys STRING" in the menu.  This will show "STRING" as
;;   the shortcut without checking if it indeed runs the same command.
;; - You can use dynamic key-bindings, i.e. instead of binding your key to
;;   (lambda () (interactive) (if foo (CMD))), bind it to
;;   (menu-item "" CMD :filter (lambda (cmd) (if foo cmd))).

;;;; Menus

;;;;; Define Menu

(easy-menu-define outshine-menu outshine-mode-map "Outshine menu"
  '("Outshine"
    ["Cycle Subtree" outshine-cycle
     :active (outline-on-heading-p) :keys "<tab>"]
    ["Cycle Buffer" outshine-cycle-buffer t :keys "<backtab>"]
    ["Show More" outshine-show-more
     :active (outline-on-heading-p) :keys "M-<right>"]
    ["Hide More" outshine-hide-more
     :active (outline-on-heading-p) :keys "M-<left>"]
    ["Show All" outline-show-all t :keys "M-# M-a>"]
    "--"
    ["Insert Heading" outshine-insert-heading t :keys "M-<return>"]
    ["Promote Heading" outline-promote
     :active (outline-on-heading-p) :keys "M-S-<left>"]
    ["Demote Heading" outline-demote
     :active (outline-on-heading-p) :keys "M-S-<right>"]
    ["Move Heading Up" outline-move-subtree-up
     :active (outline-on-heading-p) :keys "M-S-<up>"]
    ["Move Heading Down" outline-move-subtree-down
     :active (outline-on-heading-p) :keys "M-S-<down>"]
    "--"
    ["Previous Visible Heading" outline-previous-visible-heading
     t :keys "M-<up>"]
    ["Next Visible Heading" outline-next-visible-heading
     t :keys "M-<down>"]
    ["Up Heading" outline-up-heading t]
    "--"
    ["Mark Subtree" outline-mark-subtree t]
    ["Edit As Org" outorg-edit-as-org t]))

;; add "Outshine" menu item

;; (easy-menu-add outshine-menu outshine-mode-map)
;; get rid of "Outline" menu item
(define-key outshine-mode-map [menu-bar outline] 'undefined)

;;;; Keybindings

;;;;; Principal Keybindings

;; Adapted from `org-mode' and `outline-mode-easy-bindings'.

;;;;;; Visibility Cycling

(outshine-define-key outshine-mode-map
  (kbd "TAB") 'outshine-cycle
  (or (outline-on-heading-p)
      (and (bobp) outshine-org-style-global-cycling-at-bob-p)))

(outshine-define-key outshine-mode-map
  (kbd "<backtab>") 'outshine-cycle-buffer
  (or (outline-on-heading-p) (bobp)))

;; Works on the console too.
(define-key outshine-mode-map (kbd "M-TAB") 'outshine-cycle-buffer)

(outshine-define-key outshine-mode-map
  (kbd "M-<left>") 'outshine-hide-more
  (outline-on-heading-p))

(outshine-define-key outshine-mode-map
  (kbd "M-<right>") 'outshine-show-more
  (outline-on-heading-p))

;;;;;; Headline Insertion

(outshine-define-key outshine-mode-map
  (kbd "M-RET") 'outshine-insert-heading
  (outline-on-heading-p))

;;;;;; Structure Editing

(outshine-define-key outshine-mode-map
  (kbd "M-S-<left>") 'outline-promote
  (outline-on-heading-p))
(outshine-define-key outshine-mode-map
  (kbd "M-S-<right>") 'outline-demote
  (outline-on-heading-p))
(outshine-define-key outshine-mode-map
  (kbd "M-S-<up>") 'outline-move-subtree-up
  (outline-on-heading-p))
(outshine-define-key outshine-mode-map
  (kbd "M-S-<down>") 'outline-move-subtree-down
  (outline-on-heading-p))

;;;;;; Motion

(define-key outshine-mode-map
  [M-up] 'outline-previous-visible-heading)
(define-key outshine-mode-map
  [M-down] 'outline-next-visible-heading)

;;;;;; Speed commands

(defun outshine-run-speed-command-p ()
  (and
   outshine-use-speed-commands
   (outline-on-heading-p)
   (>= (point) (match-beginning 0))
   (<= (point) (match-end 0))
   (if (functionp outshine-use-speed-commands) (funcall outshine-use-speed-commands) t)))

;;;;;;; Outline Navigation

(outshine-define-key outshine-mode-map (kbd "n") (lambda () (interactive) (outshine-speed-move-safe 'outline-next-visible-heading))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "p") (lambda () (interactive) (outshine-speed-move-safe 'outline-previous-visible-heading))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "f") (lambda () (interactive) (outshine-speed-move-safe 'outline-forward-same-level))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "u") (lambda () (interactive) (outshine-speed-move-safe 'outline-up-heading))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "b") (lambda () (interactive) (outshine-speed-move-safe 'outline-backward-same-level))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "F") 'outshine-next-block
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "B") 'outshine-previous-block
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "j") 'outshine-navi
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "J") 'outshine-imenu
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "g") 'outshine-imenu
  (outshine-run-speed-command-p))

;;;;;;; Outline Visibility

(outshine-define-key outshine-mode-map (kbd "c") 'outshine-cycle
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "C") 'outshine-cycle-buffer
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd  "r") 'outshine-narrow-to-subtree
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "w") 'widen
  (outshine-run-speed-command-p))

;;;;;;; Structure editing

(outshine-define-key outshine-mode-map (kbd "U") 'outline-move-subtree-up
  (outshine-run-speed-command-p))

;; [X] FIXME error with oldschool elisp headers. FIXME' is this still relevant?
(outshine-define-key outshine-mode-map (kbd "D") 'outline-move-subtree-down
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "+") 'outline-demote
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "-") 'outline-promote
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "i") 'outshine-insert-heading
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "^") 'outshine-sort-entries
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "m") 'outline-mark-subtree
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "#") 'outshine-toggle-comment
  (outshine-run-speed-command-p))

;;;;;;; Clock Commands
;; FIXME need improvements!

(outshine-define-key outshine-mode-map (kbd "I") 'outshine-clock-in
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "O") 'outshine-clock-out
  (outshine-run-speed-command-p))

;;;;;;; Date & Time Commands

(outshine-define-key outshine-mode-map (kbd ".") 'outshine-time-stamp
  (outshine-run-speed-command-p))
;; [X]
(outshine-define-key outshine-mode-map (kbd "!") 'outshine-time-stamp-inactive
  (outshine-run-speed-command-p))
;; [X] TODO add up/down(day)
(outshine-define-key outshine-mode-map (kbd "d") 'outshine-deadline
  (outshine-run-speed-command-p))
;; [X]
(outshine-define-key outshine-mode-map (kbd "s") 'outshine-schedule
  (outshine-run-speed-command-p))

;;;;;;; Exporting

(outshine-define-key outshine-mode-map (kbd "x") 'outshine-export-dispatch
  (outshine-run-speed-command-p))

;;;;;;; Meta Data Editing

(outshine-define-key outshine-mode-map (kbd "t") 'outshine-todo
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd ",") 'outshine-priority
  (outshine-run-speed-command-p))
;; [X]
(outshine-define-key outshine-mode-map (kbd "0")
  (lambda (nil) (interactive)
    '(outshine-use-outorg
      (lambda () (interactive) (org-priority ?\ ))))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "1") (lambda (nil) (interactive)
                                 '(outshine-use-outorg
                                   (lambda () (interactive) (org-priority ?A))))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "2") (lambda (nil) (interactive)
                                 '(outshine-use-outorg
                                   (lambda () (interactive) (org-priority ?B))))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "3") (lambda (nil) (interactive)
                                 '(outshine-use-outorg
                                   (lambda () (interactive) (org-priority ?C))))
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd ":") 'outshine-set-tags-command
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "y") 'outshine-set-property
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "Y") 'outshine-set-property-and-value
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "e") 'outshine-set-effort
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "E") 'outshine-inc-effort
  (outshine-run-speed-command-p))

;;;;;;; Agenda Views etc

(outshine-define-key outshine-mode-map (kbd "v") 'outshine-agenda
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "<") '(outshine-agenda-set-restriction-lock)
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd ">") '(outshine-agenda-remove-restriction-lock)
  (outshine-run-speed-command-p))

;;;;;;; Misc

(outshine-define-key outshine-mode-map (kbd "o") 'outshine-open-at-point
  (outshine-run-speed-command-p))

(outshine-define-key outshine-mode-map (kbd "?") 'outshine-speed-command-help
  (outshine-run-speed-command-p))

;;; Footer

(provide 'outshine)

;; Local Variables:
;; coding: utf-8
;; ispell-local-dictionary: "en_US"
;; indent-tabs-mode: nil
;; End:

;;; outshine.el ends here
