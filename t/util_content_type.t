#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use JSONSchema::Validator::Util ();


foreach (
    [ 'file.json' => JSONSchema::Validator::Util::CONTENT_TYPE_JSON ],
    [ 'file.yaml' => JSONSchema::Validator::Util::CONTENT_TYPE_YAML ],
    [ 'file.yml'  => JSONSchema::Validator::Util::CONTENT_TYPE_YAML ],
    [ 'file.txt'  => undef ],
) {
    if (defined $_->[1]) {
        is JSONSchema::Validator::Util::detect_content_type_from_path($_->[0]) => $_->[1];
    }
    else {
        ok !defined JSONSchema::Validator::Util::detect_content_type_from_path($_->[0]);
    }
}

foreach (
    [ qq|\n\r \t{"test": 1}| => JSONSchema::Validator::Util::CONTENT_TYPE_JSON ],
    [ qq|\n\r \t["test", 1]| => JSONSchema::Validator::Util::CONTENT_TYPE_JSON ],
    [ qq|---\r|              => JSONSchema::Validator::Util::CONTENT_TYPE_YAML ],
    [ qq|--- >\n|            => JSONSchema::Validator::Util::CONTENT_TYPE_YAML ],
    [ qq|%YAML 1.1\n|        => JSONSchema::Validator::Util::CONTENT_TYPE_YAML ],
    [ qq|%YAML 1.1 !tag\n|   => JSONSchema::Validator::Util::CONTENT_TYPE_YAML ],
    [ qq|\n\r\ntest\n|       => undef ],
) {
    if (defined $_->[1]) {
        is JSONSchema::Validator::Util::detect_content_type_from_content(\$_->[0]) => $_->[1];
    }
    else {
        ok !defined JSONSchema::Validator::Util::detect_content_type_from_content(\$_->[0]);
    }
}


done_testing;
