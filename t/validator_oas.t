#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';

use Helper qw/test_dir detect_warnings/;
use JSONSchema::Validator;
use JSONSchema::Validator::Util qw( load_schema );

for my $validator_class (@{$JSONSchema::Validator::OAS_VALIDATORS}) {
    my $version = lc($validator_class->SPECIFICATION);

    my $resource = 'file://' . test_dir("/data/validator_oas/${version}-schema.json");
    my $instance_file_ok = 'file://' . test_dir("/data/validator_oas/${version}-ok.json");
    my $instance_file_wrong = 'file://' . test_dir("/data/validator_oas/${version}-wrong.json");

    my $instance_ok = load_schema($instance_file_ok);
    my $instance_wrong = load_schema($instance_file_wrong);

    my $schema_file = 'file://' . test_dir("/data/validator_oas/${version}-schema.json");
    my $schema = load_schema($schema_file);

    my @validators = (
        JSONSchema::Validator->new(resource => $resource),
        JSONSchema::Validator->new(schema => $schema),
        JSONSchema::Validator->new(schema => $schema, specification => $version)
    );

    for my $validator (@validators) {
        my ($result, $errors, $warnings) = $validator->validate_request(%{$instance_ok->{request}});
        is $result, 1, "check validation request $instance_file_ok";
        ok @$errors == 0, "check validation request errors $instance_file_ok";
        ok @$warnings == 0, "check validation request warnings $instance_file_ok";

        ($result, $errors, $warnings) = $validator->validate_response(%{$instance_ok->{response}});
        is $result, 1, "check validation response $instance_file_ok";
        ok @$errors == 0, "check validation response errors $instance_file_ok";
        ok @$warnings == 0, "check validation response warnings $instance_file_ok";

        ($result, $errors, $warnings) = $validator->validate_request(%{$instance_wrong->{request}});
        is $result, 0, "check validation request $instance_file_wrong";
        ok @$errors > 0, "check validation request errors $instance_file_wrong";
        ok @$warnings == 0, "check validation request warnings $instance_file_wrong";

        ($result, $errors, $warnings) = $validator->validate_response(%{$instance_wrong->{response}});
        is $result, 0, "check validation response $instance_file_wrong";
        ok @$errors > 0, "check validation response errors $instance_file_wrong";
        ok @$warnings == 0, "check validation response warnings $instance_file_wrong";
    }

    # data/wrong-schema/$version.json
    $resource = 'file://' . test_dir("/data/validator_oas/wrong-schema/${version}.json");
    my $result = eval { my $validator = JSONSchema::Validator->new(resource => $resource) };
    is $result, undef, "check exception on wrong meta schema validation of $resource";
    like $@, qr/invalid schema/, "check exception message on wrong meta schema validation of $resource";
}

ok detect_warnings() == 0, 'no warnings';
done_testing;
