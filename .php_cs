<?php // PHP CS Fixer v2+.
return PhpCsFixer\Config::create()
    ->setRules([
        // Symfony rules.

        '@Symfony'                           => true,
        'no_unused_imports'                  => false,
        'standardize_not_equals'             => false,
        'blank_line_before_statement'        => false,
        'blank_line_after_opening_tag'       => false,
        'single_blank_line_before_namespace' => false,
        'no_extra_consecutive_blank_lines'   => false,
        'phpdoc_annotation_without_dot'      => false,
        'hash_to_slash_comment'              => false,
        'no_empty_comment'                   => false,
        'yoda_style'                         => false,
        'braces'                             => [
            'allow_single_line_closure' => true,
        ],

        // Other/misc rules.

        'binary_operator_spaces' => [
            'align_equals'       => true,
            'align_double_arrow' => true,
        ],
        'no_blank_lines_before_namespace'           => true,
        'no_multiline_whitespace_before_semicolons' => true,

        'phpdoc_order'                        => true,
        'phpdoc_add_missing_param_annotation' => true,
        'phpdoc_no_alias_tag'                 => ['var' => 'type'],

        // 'psr4' => true, // Class names.
        // 'declare_strict_types' => true,
        // 'array_syntax' => ['syntax' => 'short'],
        // Disabling these to avoid altering older PHP code.
     ]);
