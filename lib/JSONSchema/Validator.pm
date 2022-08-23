package JSONSchema::Validator;

# ABSTRACT: Validator for JSON Schema Draft4/Draft6/Draft7 and OpenAPI Specification 3.0

use strict;
use warnings;
use URI::file;
use Carp 'croak';
use Cwd;

use JSONSchema::Validator::Draft4;
use JSONSchema::Validator::Draft6;
use JSONSchema::Validator::Draft7;
use JSONSchema::Validator::OAS30;
use JSONSchema::Validator::Util qw( load_schema );

our $VERSION = '0.010';

my $SPECIFICATIONS = {
    JSONSchema::Validator::OAS30::ID => JSONSchema::Validator::OAS30::SPECIFICATION,
    JSONSchema::Validator::Draft4::ID => JSONSchema::Validator::Draft4::SPECIFICATION,
    JSONSchema::Validator::Draft6::ID => JSONSchema::Validator::Draft6::SPECIFICATION,
    JSONSchema::Validator::Draft7::ID => JSONSchema::Validator::Draft7::SPECIFICATION
};

our $JSON_SCHEMA_VALIDATORS = ['JSONSchema::Validator::Draft4', 'JSONSchema::Validator::Draft6', 'JSONSchema::Validator::Draft7'];
our $OAS_VALIDATORS = ['JSONSchema::Validator::OAS30'];

=method new

Creates one of the following validators: JSONSchema::Validator::Draft4, JSONSchema::Validator::Draft6, JSONSchema::Validator::Draft7, JSONSchema::Validator::OAS30.

    my $validator = JSONSchema::Validator->new(resource => 'file:///some/path/to/oas30.yml');
    my $validator = JSONSchema::Validator->new(resource => 'http://example.com/draft4/schema.json');
    my $validator = JSONSchema::Validator->new(schema => {'$schema' => 'path/to/schema', ...});
    my $validator = JSONSchema::Validator->new(schema => {...}, specification => 'Draft4');

if parameter C<specification> is not specified then type of validator will be determined by C<$schema> key
for JSON Schema Draft4/Draft6/Draft7 and by C<openapi> key for OpenAPI Specification 3.0 in C<schema> parameter.

Parameters:

=over 1 

=item resources

To get schema by uri

=item schema

To get explicitly specified schema

=item specification

To specify specification of schema

=item validate_schema

Do not validate specified schema

=item base_uri

To specify base uri of schema.
This parameter used to build absolute path by relative reference in schema.
By default C<base_uri> is equal to the resource path if the resource parameter is specified otherwise the C<$id> key in the schema.

=back

Additional parameters need to be looked at in a specific validator class.
Currently there are validators: JSONSchema::Validator::Draft4, JSONSchema::Validator::Draft6, JSONSchema::Validator::Draft7, JSONSchema::Validator::OAS30.

=cut

sub new {
    my ($class, %params) = @_;

    my $resource = delete $params{resource};
    my $validate_schema = delete($params{validate_schema}) // 1;
    my $schema = delete $params{schema};
    my $base_uri = delete $params{base_uri};
    my $specification = delete $params{specification};

    $schema = load_schema($resource, $params{scheme_handlers}) if !$schema && $resource;
    croak 'resource or schema must be specified' unless defined $schema;

    my $validator_class = find_validator($specification // schema_specification($schema));
    croak 'unknown specification' unless $validator_class;

    if ($validate_schema) {
        my ($result, $errors) = $class->validate_resource_schema($schema, $validator_class->SPECIFICATION);
        croak "invalid schema:\n" . join "\n", @$errors unless $result;
    }

    # schema may be boolean value according to json schema draft6
    if (ref $schema eq 'HASH') {
        $base_uri //= $resource || $schema->{'$id'} || $schema->{id};
    }

    return $validator_class->new(schema => $schema, base_uri => $base_uri, %params);
}

=method validate_paths

Validates all files specified by path globs.

    my $result = JSONSchema::Validator->validate_paths(['/some/path/to/openapi.*.yaml', '/some/path/to/jsonschema.*.json']);
    for my $file (keys %$result) {
        my ($res, $errors) = @{$result->{$file}};
    }

=cut

sub validate_paths {
    my ($class, $globs) = @_;
    my $results = {};
    for my $glob (@$globs) {
        my @resources = map { Cwd::abs_path($_) } glob $glob;
        for my $resource (@resources) {
            my $uri = URI::file->new($resource)->as_string;
            my ($result, $errors) = $class->validate_resource($uri);
            $results->{$resource} = [$result, $errors];
        }
    }
    return $results;
}

=method validate_resource

=cut

sub validate_resource {
    my ($class, $resource, %params) = @_;
    my $schema_to_validate = load_schema($resource, $params{scheme_handlers});

    my $validator_class = find_validator(schema_specification($schema_to_validate));
    croak "unknown specification of resource $resource" unless $validator_class;

    return $class->validate_resource_schema($schema_to_validate, $validator_class->SPECIFICATION);
}

=method validate_resource_schema

=cut

sub validate_resource_schema {
    my ($class, $schema_to_validate, $schema_specification) = @_;

    my $schema = read_specification($schema_specification);
    my $meta_schema = $schema->{'$schema'};

    my $meta_schema_specification = $SPECIFICATIONS->{$meta_schema} // $SPECIFICATIONS->{$meta_schema . '#'};
    croak "unknown meta schema: $meta_schema" unless $meta_schema_specification;

    my $validator_class = find_validator($meta_schema_specification);
    croak "can't find validator by meta schema: $meta_schema" unless $validator_class;

    my $validator = $validator_class->new(schema => $schema);
    my ($result, $errors) = $validator->validate_schema($schema_to_validate);
    return ($result, $errors);
}

sub read_specification {
    my $filename = shift;
    my $curret_filepath = __FILE__;
    my $schema_filepath = ($curret_filepath =~ s/\.pm$//r) . '/schemas/' . lc($filename) . '.json';
    return load_schema($schema_filepath);
}

sub find_validator {
    my $specification = shift;
    my ($validator_class) = grep { lc($_->SPECIFICATION) eq lc($specification // '') } @$JSON_SCHEMA_VALIDATORS, @$OAS_VALIDATORS;
    return $validator_class;
}

sub schema_specification {
    my $schema = shift;
    return if ref $schema ne 'HASH';

    my $meta_schema = $schema->{'$schema'};
    my $specification = $meta_schema ? $SPECIFICATIONS->{$meta_schema} // $SPECIFICATIONS->{$meta_schema . '#'} : undef;

    if (!$specification && $schema->{openapi}) {
        my @vers = split /\./, $schema->{openapi};
        $specification = 'OAS' . $vers[0] . $vers[1];
    }

    return $specification;
}

1;

__END__

=head1 SYNOPSIS

    # to get OpenAPI validator in YAML format
    $validator = JSONSchema::Validator->new(resource => 'file:///some/path/to/oas30.yml');
    my ($result, $errors, $warnings) = $validator->validate_request(
        method => 'GET',
        openapi_path => '/user/{id}/profile',
        parameters => {
            path => {
                id => 1234
            },
            query => {
                details => 'short'
            },
            header => {
                header => 'header value'
            },
            cookie => {
                name => 'value'
            },
            body => [$is_exists, $content_type, $data]
        }
    );
    my ($result, $errors, $warnings) = $validator->validate_response(
        method => 'GET',
        openapi_path => '/user/{id}/profile',
        status => '200',
        parameters => {
            header => {
                header => 'header value'
            },
            body => [$is_exists, $content_type, $data]
        }
    )

    # to get JSON Schema Draft4/Draft6/Draft7 validator in JSON format
    $validator = JSONSchema::Validator->new(resource => 'http://example.com/draft4/schema.json')
    my ($result, $errors) = $validator->validate_schema($object_to_validate)

=head1 DESCRIPTION

OpenAPI specification and JSON Schema Draft4/Draft6/Draft7 validators with minimum dependencies.

=head1 CAVEATS

=head2 YAML & booleans

When reading schema definitions from YAML, please note that the standard
behaviour of L<YAML::PP> and L<YAML::XS> is to read values which evaluate
to C<true> or C<false> in a perl context. These values have no recognizable
'boolean type'. This is insufficient for JSON schema validation.

To make the YAML readers and booleans work with C<JSONSchema::Validator>,
you need to use the C<JSON::PP> (included in Perl's standard library) module
as follows:

  # for YAML::PP
  use YAML::PP;

  my $reader = YAML::PP->new( boolean => 'JSON::PP' );
  # from here, you can freely use the reader to
  # read & write booleans as 'true' and 'false'


  # for YAML::XS
  use YAML::XS;

  my $reader = YAML::XS->new;

  # and whenever you read YAML with this reader, do:
  my $yaml = do {
    local $YAML::XS::Boolean = 'JSON::PP';
    $reader->Load($string); # or $reader->LoadFile('filename');
  };

This isn't a problem when you use the C<resource> argument to the
C<JSONSchema::Validator::new> constructor, but if you read your own
schema and use the C<schema> argument, this is something to be aware of.

=head2 allow_bignum => 1

The C<allow_bignum => 1> setting (available on L<JSON::XS> and
L<Cpanel::JSON::XS>) on deserializers is not supported.

When deserializing a request body with a JSON parser configured with
C<allow_bignum => 1>, floats - even ones which fit into the regular
float ranges - will be deserialized as C<Math::BigFloat>. Similarly,
integers outside of the internal integer range are deserialized as
C<Math::BigInt>. Numbers represented as C<Math::Big*> objects are not
recognized as actual numbers and will fail validation.

=cut
