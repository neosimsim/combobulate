;;; combobulate-python.el --- python-specific features for combobulate  -*- lexical-binding: t; -*-

;; Copyright (C) 2021-23  Mickey Petersen

;; Author: Mickey Petersen <mickey at masteringemacs.org>
;; Package-Requires: ((emacs "29"))
;; Version: 0.1
;; Homepage: https://www.github.com/mickeynp/combobulate
;; Keywords: convenience, tools, languages

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'python)
(require 'combobulate-settings)
(require 'combobulate-navigation)
(require 'combobulate-interface)
(require 'combobulate-rules)

(declare-function combobulate--mark-node "combobulate-manipulation")
(declare-function combobulate-indent-region "combobulate-manipulation")

(defvar combobulate-python-indent--direction nil)

(defgroup combobulate-python nil
  "Configuration switches for Python."
  :group 'combobulate
  :prefix "combobulate-python-")

(defcustom combobulate-python-smart-indent t
  "Smarter indentation handling.

Greatly improves indentation handling when you indent
regions. Combobulate will automatically indent the region and
preserve the existing indentation. You can then cycle through
indentation levels to pick the right one.

If `combobulate-python-indent-blocks-dwim' is non-nil, then
Combobulate will automatically pick the code block immediately
ahead of point. You can use this to cycle through the indentation
of blocks of code: functions, for statements, etc.

This works by remapping `indent-for-tab-command' to
`combobulate-python-indent-for-tab-command'."
  :type 'boolean
  :group 'combobulate-python)

(defcustom combobulate-python-indent-mark-region nil
  "Mark the region when indenting and leave it enabled after.

When non-nil, Combobulate will mark the region when indenting
with `combobulate-python-indent-for-tab-command'.

When nil, the mark is instead deactivated after indenting."
  :type 'boolean
  :group 'combobulate-python)

(defcustom combobulate-python-indent-blocks-dwim t
  "Indent a whole block if point is on it instead of the line.

With point at the beginning of a block -- such as a for statement
-- Combobulate will instead indent the block instead of just the
line when you press
\\[combobulate-python-indent-for-tab-command]."
  :type 'boolean)

(defun combobulate-python--get-definition (node)
  (string-join
   (combobulate-query-node-text
    (pcase (combobulate-node-type node)
      ("function_definition"
       '((_) name: (_) @name parameters: (_) @args))
      ("class_definition"
       '((_) name: (_) @name superclasses: (_) @args)))
    node
    t)
   ""))

(defun combobulate-python-pretty-print-node-name (node default-name)
  "Pretty printer for Python nodes"
  (combobulate-string-truncate
   (replace-regexp-in-string
    (rx (| (>= 2 " ") "\n")) ""
    (pcase (combobulate-node-type node)
      ("function_definition" (concat "def " (combobulate-python--get-definition node)))
      ("class_definition" (concat "class " (combobulate-python--get-definition node)))
      (_ default-name)))
   40))



(defun combobulate-python-calculate-indent (pos)
  (let ((calculated-indentation (save-excursion
                                  (goto-char pos)
                                  (combobulate-filter-nodes
                                   (combobulate-get-parents
                                    (combobulate-node-at-point))
                                   :keep-types
                                   '("block"
                                     ;; required because, for some inexplicable reason, the
                                     ;; python grammar does not consider a match-case statement
                                     ;; to consist of a case clause and a block clause unlike
                                     ;; literally everything else.
                                     "case_clause")))))
    (if (null calculated-indentation)
        (current-indentation)
      (* python-indent-offset (length calculated-indentation)))))

(defun combobulate-python-proffer-indent-action (_index current-node _proxy-nodes refactor-id)
  "Proffer action function that highlights the node and indents it."
  (combobulate-refactor (:id refactor-id)
    (mark-node-highlighted current-node)
    (combobulate-indent-region
     ;; we want to mark from the beginning of line
     (save-excursion
       (goto-char (combobulate-node-start current-node))
       (skip-chars-backward combobulate-skip-prefix-regexp (line-beginning-position))
       (point))
     (combobulate-node-end current-node)
     ;; no baseline target
     0
     (combobulate-proxy-node-extra current-node))
    (combobulate-move-to-node current-node)))

(defun combobulate-proffer-indentation (node)
  "Intelligently indent the region or NODE at point."
  (interactive)
  (let* ((indentation (save-excursion
                        (combobulate--goto-node node)
                        (python-indent-calculate-levels)))
         (indent-nodes (mapcar
                        (lambda (level)
                          (save-excursion
                            (let ((proxy-node
                                   ;; A region may, potentially, signify a valid
                                   ;; node range, but it is unlikely. When a user
                                   ;; wants to indent a region they want to --
                                   ;; presumably -- indent code that may not be
                                   ;; syntactically sound. For that we'll create a
                                   ;; special proxy node that will be used to
                                   ;; indent the region.
                                   (if (use-region-p)
                                       (combobulate-make-proxy-from-region (region-beginning) (region-end))
                                     ;; if we're not dealing with a region, we
                                     ;; make a proxy node for the closest node.
                                     (combobulate-make-proxy node))))
                              (setf (combobulate-proxy-node-extra proxy-node)
                                    (- (current-indentation) level))
                              proxy-node)))
                        (python-indent-calculate-levels)))
         (current-position (1+ (or (seq-position indentation (current-indentation)) 0)))
         (number-of-levels (length (python-indent-calculate-levels)))
         (at-last-level (= number-of-levels current-position)))
    (combobulate-proffer-choices
     (if at-last-level (reverse indent-nodes) indent-nodes)
     #'combobulate-python-proffer-indent-action
     :start-index (if at-last-level 1 (mod current-position number-of-levels))
     :flash-node t
     ;; do not filter unique nodes. all our nodes are conceptually
     ;; identical except for the `extra' field.
     :unique-only nil)))

(defun combobulate-python-envelope-deindent-level ()
  "Determine the next-closest indentation level to deindent to."
  (car-safe (last (seq-take-while (lambda (num) (< num (current-column)))
                                  (python-indent-calculate-levels)))))


(defun combobulate-python-indent-for-tab-command (&optional arg)
  "Proxy command for `indent-for-tab-command' and `combobulate-proffer-indentation'."
  (interactive "P")
  (with-navigation-nodes
      (:nodes (append
               ;; rules that trigger indentation
               (combobulate-production-rules-get "_simple_statement")
               (combobulate-production-rules-get "_compound_statement"))
              ;; do not skip prefix if we have a region active. the
              ;; reason for that is that skipping forward with a
              ;; marked region can bork the indentation mechanism as
              ;; we can only effectively indent with whole lines.
              :skip-prefix (not (use-region-p))
              :skip-newline nil)
    (let ((node (combobulate--get-nearest-navigable-node)))
      (cond
       ((use-region-p)
        ;; ensure point is at the beginning of the region
        (when (> (point) (mark))
          (exchange-point-and-mark))
        (combobulate-proffer-indentation node)
        ;; toggle the region on and off so it doesn't get deactivated
        (setq deactivate-mark nil)
        (activate-mark))
       ;; we need to handle blank lines as tabbing on a blank line should
       ;; default to the regular python indentation mechanism.
       ((save-excursion
          (beginning-of-line)
          (looking-at-p "[[:space:]]*$"))
        (indent-for-tab-command arg))
       ;; if we're at the beginning of a node, we want to indent it.
       ((and combobulate-python-indent-blocks-dwim (combobulate-point-at-beginning-of-node-p node))
        (combobulate-proffer-indentation node))
       ;; for everything else, use the regular indentation mechanism.
       (t (indent-for-tab-command arg))))))

(defun combobulate-python-setup (_)
  (setq combobulate-navigation-context-nodes '("identifier"))

  ;; do not indent envelopes.
  (setq combobulate-envelope-indent-region-function nil)
  (when combobulate-python-smart-indent
    ;; Override `indent-for-tab-command'
    (local-set-key [remap indent-for-tab-command] #'combobulate-python-indent-for-tab-command))
  ;; install a handful of useful highlighting rules.
  (setq combobulate-highlight-queries-default
        '(;; highlight breakpoint function calls
          (((call (identifier) @hl.fiery (:match "^breakpoint$" @hl.fiery))))
          ;; catch trailing commas that inadvertently turn expressions into tuples
          ((expression_list (_)+ "," @hl.gold :anchor))))
  (setq indent-region-function #'combobulate-python-indent-region)
  (setq combobulate-manipulation-indent-after-edit nil)
  (setq combobulate-pretty-print-node-name-function #'combobulate-python-pretty-print-node-name)
  (setq combobulate-manipulation-splicing-procedures
        `((:activation-nodes
           ((:node
             ,(append (combobulate-production-rules-get "_simple_statement")
                      (combobulate-production-rules-get "_compound_statement")
                      (combobulate-production-rules-get "if_statement")
                      (combobulate-production-rules-get "try_statement")
                      '("case_clause"))
             :find-base-rule-parent t
             :position at-or-in))
           :match-siblings (:keep-parent nil))))

  (let ((statement-nodes
         (append (combobulate-production-rules-get "_compound_statement")
                 (combobulate-production-rules-get "_simple_statement")
                 '("expression_statement" "block"))))
    (setq combobulate-manipulation-envelopes
          `((:description
             "( ... )"
             :key "("
             :extra-key "M-("
             :mark-node t
             :nodes ,(append (combobulate-production-rules-get "primary_expression")
                             (combobulate-production-rules-get "expression"))
             :name "wrap-parentheses"
             :template (@ "(" r ")"))
            (:description
             "Decorate class or function"
             :key "@"
             :mark-node nil
             :nodes ("function_definition" "class_definition")
             :name "decorate"
             :template ((p @decorator "Decorator name"
                           (lambda (text)
                             (if (string-prefix-p "@" text)
                                 text
                               (concat "@" text))))
                        n>))
            (:description
             "if ...:"
             :key "bi"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-if"
             :template
             ("if " @ ":" n>
              r>))
            (:description
             "if ...: ... else: ..."
             :key "bI"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-if-else"
             :template
             ("if " @ ":" n>
              (choice* :name "consequence" :missing ("pass") :rest (r>))
              < "else:" n>
              (choice* :name "alternative" :missing ("pass") :rest (r>))))
            (:description
             "try ... except ...: ..."
             :key "bte"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-try-except"
             :template
             ("try:" n>
              (choice* :missing (@@ "pass") :rest (@@ r>))
              <
              "except " (p Exception "Exception") ":" n>
              (choice* :missing (@@ "pass" n>) :rest (@@ r> n))))
            (:description
             "try ... finally: ..."
             :key "btf"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-try-finally"
             :template
             (@ "try:" n>
                (choice* :missing ("pass") :rest (r>))
                <
                "finally:" n>
                (choice* :missing ("pass") :rest (r>))))
            (:description
             "def ...():"
             :key "bd"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-def"
             :template
             ("def " (p name "Name") "(" @ ")" ":" n>
              r>))
            (:description
             "for ...:"
             :key "bf"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-for"
             :template
             ("for " @ ":" n>
              r>))
            (:description
             "with ...:"
             :key "bW"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-with"
             :template
             ("with " @ ":" n>
              r>))
            (:description
             "while ...:"
             :key "bw"
             :mark-node t
             :nodes ,statement-nodes
             :name "nest-while"
             :template
             ("while " @ ":" n>
              r>)))))

  (add-to-list 'python-indent-trigger-commands 'combobulate-python-indent-for-tab-command)
  (setq combobulate-manipulation-edit-procedures
        '(;; edit comments in blocks
          (:activation-nodes
           ((:node "comment" :find-parent ("block") :position at-or-in))
           :match-query (block (comment)+ @match))
          ;; edit pairs in dictionaries
          (:activation-nodes
           ((:node "pair" :find-parent "dictionary" :position at-or-in)
            (:node "dictionary" :position at-or-in))
           :match-query (dictionary (pair)+ @match)
           :remove-types ("comment"))
          ;; edit parameters in functions
          (:activation-nodes
           ((:node "function_definition" :position at-or-in))
           :match-query (function_definition (parameters (_)+ @match))
           :remove-types ("comment"))
          ;; edit elements in containers and blocks
          (:activation-nodes
           ((:node ("block" "tuple_pattern" "set" "list" "tuple") :position at-or-in))
           :match-query ((_) (_)+ @match)
           ;; :match-children t
           :remove-types ("comment"))
          ;; edit arguments in calls
          (:activation-nodes
           ((:node "argument_list" :position at-or-in))
           :match-query ((argument_list) (_)+ @match)
           :remove-types ("comment"))
          ;; edit imports
          (:activation-nodes
           ((:node "import_from_statement" :position at-or-in :find-parent "module"))
           :match-query (import_from_statement name: (dotted_name)+ @match))))

  (setq combobulate-manipulation-indent-method 'first)
  (setq combobulate-calculate-indent-function #'combobulate-python-calculate-indent)
  (setq combobulate-envelope-deindent-function #'combobulate-python-envelope-deindent-level)
  (setq combobulate-navigation-defun-nodes '("class_definition" "function_definition" "decorated_definition" "lambda"))
  (setq combobulate-navigation-sexp-nodes '("function_definition"  "class_definition" "lambda"
                                            "for_in_clause" "string" "decorated_definition"))
  (setq combobulate-navigation-sibling-procedures
        `((:activation-nodes
           ((:node
             ("string_content" "interpolation")
             :position at-or-in
             :find-immediate-parent ("string")))
           :remove-types ("string_start" "string_end")
           :match-children t)
          (:activation-nodes
           ((:node
             ;; pattern is a special supertype. It is not a node in the CST.
             ,(combobulate-production-rules-get "pattern")
             :position at-or-in
             ;; Note that we do not find all the parents of pattern
             ;; but only a couple. The main reason is that otherwise
             ;; they'd become potential next/prev siblings in a block
             ;; and that's generally not what people expect when
             ;; they're navigating siblings in a block. By limiting
             ;; ourselves to explicit tuples/lists, the user would
             ;; have to enter these nodes explicitly to navigate them.
             :find-immediate-parent ("tuple_pattern" "list_pattern"))
            (:node
             ,(combobulate-production-rules-get "import_from_statement")
             :position at-or-in
             :find-immediate-parent ("import_from_statement"))
            (:node
             ,(combobulate-production-rules-get "dictionary")
             :position at-or-in
             :find-immediate-parent ("dictionary"))
            (:node
             ,(append
               (combobulate-production-rules-get "primary_expression")
               (combobulate-production-rules-get "expression"))
             :position at-or-in
             :find-immediate-parent ("set" "tuple" "list"))
            (:node
             ,(append
               (combobulate-production-rules-get "parameter")
               (combobulate-production-rules-get "argument_list")
               (combobulate-production-rules-get "expression")
               (combobulate-production-rules-get "expression_list")
               (combobulate-production-rules-get "primary_expression"))
             :position at-or-in
             :find-immediate-parent ("parameters" "argument_list" "expression_list")))
           :match-children t)
          (:activation-nodes
           ((:node
             ,(append (combobulate-production-rules-get "_simple_statement")
                      (combobulate-production-rules-get "_compound_statement")
                      (combobulate-production-rules-get "module")
                      '("module" "comment" "case_clause"))
             :position at-or-in
             :find-immediate-parent ("case_clause" "match_statement" "module" "block")))
           :remove-types nil
           :match-children t)))

  (setq combobulate-navigation-parent-child-nodes
        (append
         (combobulate-production-rules-get "_simple_statement")
         (combobulate-production-rules-get "_compound_statement")
         (combobulate-production-rules-get "parameter")
         (combobulate-production-rules-get "argument_list")
         '("module" "dictionary" "except_clause" "for_in_clause" "finally_clause" "elif_clause"
           "pair"
           "list" "call" "tuple" "string" "case_clause" "set")))
  (setq combobulate-navigation-logical-nodes
        (append
         (combobulate-production-rules-get "primary_expression")
         (combobulate-production-rules-get "expression")
         combobulate-navigation-default-nodes))
  (setq combobulate-navigation-default-nodes
        (seq-uniq (flatten-tree combobulate-rules-python))))

(provide 'combobulate-python)
;;; combobulate-python.el ends here
