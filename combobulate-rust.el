(require 'combobulate-settings)
(require 'combobulate-navigation)
(require 'combobulate-manipulation)
(require 'combobulate-interface)
(require 'combobulate-rules)

(defun combobulate-rust-pretty-print-node-name (node default-name)
  "Pretty printer for Rust nodes"
  (pcase (combobulate-node-type node)
    ;; ("parameter" (treesit-node-text node 'no-properties))
    ("parameter" (string-join (combobulate-query-node-text '((_) @text) node t)))
    ("self_parameter" (string-join (combobulate-query-node-text '((_) @text) node t)))
    ("impl_item" (concat "impl " (string-join (combobulate-query-node-text '((_) trait: (_) @trait type: (_) @type) node t) " for ")))
    (_ default-name)))


(defun combobulate-rust-setup (_)
  (setq combobulate-navigation-context-nodes '("identifier" "type_identifier"))

  (setq combobulate-navigation-defun-procedures
        '((:activation-nodes ((:nodes ("function_item" "struct_item" "enum_item" "closure_expression" "macro_definition"))))))
  (setq combobulate-navigation-sexp-procedures
        '((:activation-nodes ((:nodes ("function_item" "struct_item" "enum_item" "closure_expression" "macro_definition"))))))
  (setq combobulate-navigation-parent-child-procedures
        '((:activation-nodes
           ((:nodes ((all)) :has-parent ((all))))
           :selector (:choose node
                              :match-children (:discard-rules ("block"))))))
  (setq combobulate-navigation-logical-procedures
        '((:activation-nodes ((:nodes (all))))))

  (setq combobulate-pretty-print-node-name-function #'combobulate-rust-pretty-print-node-name)

  (setq combobulate-navigation-sibling-procedures
        '((:activation-nodes
           ((:nodes
             ("parameter" "self_parameter")
             :has-parent ("parameters")))
           :selector (:match-children t))

          (:activation-nodes
           ((:nodes
             ("expression_statement" "let_declaration")
             :has-parent ("block")))
           :selector (:match-children t))

          (:activation-nodes
           ((:nodes
             ("match_arm")
             :has-parent ("match_block")))
           :selector (:match-children t))

          (:activation-nodes
           ((:nodes
             ("function_item" "struct_item" "impl_item" "mod_item")
             :has-parent ("source_file" "mod_item")))
           :selector (:match-children t))
          ))

  ;; (setq combobulate-calculate-indent-function nil)
  ;; (setq combobulate-default-procedures nil)
  ;; (setq combobulate-display-ignored-node-types nil)
  ;; (setq combobulate-envelope-deindent-function nil)
  ;; (setq combobulate-envelope-indent-region-function nil)
  ;; (setq combobulate-envelope-procedure-shorthand-alist nil)
  ;; (setq combobulate-highlight-queries-alist nil)
  ;; (setq combobulate-highlight-queries-default nil)
  ;; (setq combobulate-manipulation-edit-procedures nil)
  ;; (setq combobulate-manipulation-envelopes nil)
  ;; (setq combobulate-manipulation-indent-after-edit nil)
  ;; (setq combobulate-manipulation-node-cluster-queries nil)
  ;; (setq combobulate-manipulation-plausible-separators nil)
  ;; (setq combobulate-manipulation-trim-empty-lines nil)
  ;; (setq combobulate-manipulation-trim-whitespace nil)
  ;; (setq combobulate-navigation-default-nodes nil)

  ;; (setq combobulate-navigation-default-procedures nil)

  ;; (setq combobulate-navigation-drag-parent-nodes nil)
  ;; (setq combobulate-navigation-rules nil)
  ;; (setq combobulate-navigation-rules-all nil)
  ;; (setq combobulate-navigation-rules-inverted nil)
  ;; (setq combobulate-navigation-rules-overrides-inverted nil)
  ;; (setq combobulate-navigation-sexp-procedures nil)
  ;; (setq combobulate-navigation-sibling-procedures nil)
  ;; (setq combobulate-navigation-sibling-skip-prefix nil)
  ;; (setq combobulate-options-envelope-key-map nil)
  ;; (setq combobulate-pretty-print-function nil)
  ;; (setq combobulate-procedure-discard-rules nil)
  ;; (setq combobulate-query-builder-active-parser nil)
  ;; (setq combobulate-query-builder-field-names nil)
  ;; (setq combobulate-query-builder-font-lock-keywords nil)
  ;; (setq combobulate-query-builder-match-capture-faces-alist nil)
  ;; (setq combobulate-query-builder-rule-names nil)
  ;; (setq combobulate-query-builder-rules nil)
  ;; (setq combobulate-sgml-exempted-tags nil)
  ;; (setq combobulate-sgml-open-tag nil)
  ;; (setq combobulate-sgml-close-tag nil)
  ;; (setq combobulate-sgml-self-closing-tag nil)
  ;; (setq combobulate-sgml-whole-tag nil)
  )
