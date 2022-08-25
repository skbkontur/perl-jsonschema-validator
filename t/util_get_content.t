#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use URI ();
use URI::file ();

use JSONSchema::Validator::Util ();

use lib qw( t/lib );

use Helper qw( test_dir );


my $p = test_dir('/data/json_schema/draft4/basic.json');

ok ${(JSONSchema::Validator::Util::get_content($p))[0]};
ok ${(JSONSchema::Validator::Util::get_content('file://' . $p))[0]};
ok ${(JSONSchema::Validator::Util::get_content(URI::file->new($p)))[0]};
ok ${(JSONSchema::Validator::Util::get_content(URI->new($p, 'file')))[0]};

#my $u = 'http://httpbin.org';
#
#ok ${(JSONSchema::Validator::Util::get_content($u))[0]};
#ok ${(JSONSchema::Validator::Util::get_content(URI->new($u)))[0]};


done_testing;
