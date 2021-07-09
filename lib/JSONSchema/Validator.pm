package JSONSchema::Validator;

# ABSTRACT: Validator for JSON Schema

use strict;
use warnings;
use URI::file;
use Carp 'croak';

use JSONSchema::Validator::Util qw(get_resource decode_content read_file);


our $VERSION = '0.001';


my $SCHEMA_OF_SPEC = {
    'OAS30' => 'Draft4',
    'Draft4' => 'Draft4'
};

my $SPECIFICATIONS = {
    'https://spec.openapis.org/oas/3.0/schema/2019-04-02' => 'OAS30',
    'http://json-schema.org/draft-04/schema#' => 'Draft4'
};

sub new {
    my ($class, %params) = @_;

    my $resource = delete $params{resource};
    my $validate_resource = delete($params{validate_resource}) // 1;
    my $schema = delete $params{schema};
    my $base_uri = delete($params{base_uri});

    $schema = resource_schema($resource, \%params) if !$schema && $resource;
    croak 'resource or schema must be specified' unless $schema;

    if ($validate_resource) {
        my ($result, $errors) = $class->validate_resource_schema($resource // '', $schema);
        croak "invalid schema: \n" . join "\n", @$errors unless $result;
    }

    my $specification = schema_specification($schema);

    my $validator_class = "JSONSchema::Validator::${specification}";
    croak "Unknown specification param $specification" unless eval "require $validator_class; 1";

    $base_uri //= $resource || $schema->{id} || $schema->{'$id'};

    return $validator_class->new(schema => $schema, base_uri => $base_uri, %params);
}

sub validate_paths {
    my ($class, $globs) = @_;
    my $results = {};
    for my $glob (@$globs) {
        my @resources = glob $glob;
        for my $resource (@resources) {
            my $uri = URI::file->new($resource)->as_string;
            my ($result, $errors) = $class->validate_resource($uri);
            $results->{$resource} = [$result, $errors];
        }
    }
    return $results;
}

sub validate_resource {
    my ($class, $resource, %params) = @_;
    my $schema_to_validate = resource_schema($resource, \%params);
    return $class->validate_resource_schema($resource, $schema_to_validate);
}

sub validate_resource_schema {
    my ($class, $resource, $schema_to_validate) = @_;
    my $specification = schema_specification($schema_to_validate);
    croak "unknown document type of $resource" unless $specification;

    my $schema = read_specification($specification);

    my $meta_schema = $schema->{'$schema'};
    croak "unknown schema of $resource" unless $meta_schema;

    my $validator_name = $SPECIFICATIONS->{$meta_schema};
    my $validator_class = "JSONSchema::Validator::${validator_name}";
    eval "require $validator_class; 1";

    my $validator = $validator_class->new(schema => $schema);
    my ($result, $errors) = $validator->validate_schema($schema_to_validate);
    return ($result, $errors);
}

sub read_specification {
    my $filename = shift;
    my $curret_filepath = __FILE__;
    my $schema_filepath = ($curret_filepath =~ s/.pm//r) . '/schemas/' . lc($filename) . '.json';
    my ($content, $mime_type) = read_file($schema_filepath);
    return decode_content($content, $mime_type, $schema_filepath);
}

sub resource_schema {
    my ($resource, $params) = @_;
    my ($response, $mime_type) = get_resource($params->{scheme_handlers}, $params->{user_agent_get}, $resource);
    my $schema = decode_content($response, $mime_type, $resource);
    return $schema;
}

sub schema_specification {
    my $schema = shift;

    my $id = $schema->{id} || $schema->{'$id'};
    my $specification = $SPECIFICATIONS->{$id} if $id;

    if (!$id && $schema->{openapi}) {
        my @vers = split /\./, $schema->{openapi};
        $specification = 'OAS' . $vers[0] . $vers[1];
    }

    return $specification;
}

1;
