package JSONSchema::Validator::Draft4;

use strict;
use warnings;
use URI;
use Carp 'croak';

use JSONSchema::Validator::Error 'error';
use JSONSchema::Validator::JSONPointer 'json_pointer';
use JSONSchema::Validator::Constraints::Draft4;
use JSONSchema::Validator::URIResolver;

use constant ID => 'id';

sub new {
    my ($class, %params) = @_;

    my $schema = $params{schema} or croak 'schema is required';
    my $strict = $params{strict} // 1;
    my $using_id_with_ref = $params{using_id_with_ref} // 1;

    my $scheme_handlers = $params{scheme_handlers};
    my $user_agent_get = $params{user_agent_get};

    my $self = {
        schema => $schema,
        errors => [],
        scopes => [],
        using_id_with_ref => $using_id_with_ref
    };

    bless $self, $class;

    my $base_uri = $params{base_uri} // $schema->{$self->ID} // '';
    $self->{base_uri} = $base_uri;

    my $constraints = JSONSchema::Validator::Constraints::Draft4->new(validator => $self, strict => $strict);
    $self->{constraints} = $constraints;

    my $resolver = JSONSchema::Validator::URIResolver->new(
        validator => $self,
        base_uri => $base_uri,
        schema => $schema,
        scheme_handlers => $scheme_handlers,
        user_agent_get => $user_agent_get
    );
    $self->{resolver} = $resolver;

    push @{$self->scopes}, $base_uri;

    return $self;
}

sub schema { shift->{schema} }
sub constraints { shift->{constraints} }
sub resolver { shift->{resolver} }
sub scopes { shift->{scopes} }
sub scope { shift->{scopes}[-1] }
sub base_uri { shift->{base_uri} }
sub using_id_with_ref { shift->{using_id_with_ref} }

sub validate_schema {
    my ($self, $instance, %params) = @_;

    my $schema = $params{schema} || $self->schema;
    my $instance_path = $params{instance_path} // '/';
    my $schema_path = $params{schema_path} // '/';
    my $scope = $params{scope};

    croak 'No schema specified' unless $schema;

    push @{$self->scopes}, $scope if $scope;

    my $errors = [];
    my $result = $self->_validate_schema($instance, $schema, $instance_path, $schema_path, {errors => $errors});

    pop @{$self->scopes} if $scope;

    return $result, $errors;
}

sub _validate_schema {
    my ($self, $instance, $schema, $instance_path, $schema_path, $data, %params) = @_;

    my $apply_scope = $params{apply_scope} // 1;

    my $id = $schema->{$self->ID};
    if ($id && $apply_scope && $self->using_id_with_ref) {
        my $uri = $id;
        $uri = URI->new($id)->abs($self->scope)->as_string if $self->scope;
        push @{$self->scopes}, $uri;
    }

    my @schema_keys = $self->_schema_keys($schema, $instance_path, $data);

    my $result = 1;
    for my $k (@schema_keys) {
        my $v = $schema->{$k};

        my $method = $k eq '$ref' ? 'ref' : $k;
        next unless my $constraint = $self->constraints->can($method);

        my $spath = json_pointer->append($schema_path, $k);

        my $r = eval {
            $self->constraints->$constraint($instance, $v, $schema, $instance_path, $spath, $data);
        };
        push @{$data->{errors}}, error(
                message => "exception: $@",
                instance_path => $instance_path,
                schema_path => $spath
            ) if $@;
        $result = 0 unless $r;
    }

    pop @{$self->scopes} if $id && $apply_scope && $self->using_id_with_ref;
    return $result;
}

sub _schema_keys {
    my ($self, $schema, $instance_path, $data) = @_;
    # if ref exists other preperties MUST be ignored
    return '$ref' if $schema->{'$ref'};
    return keys %$schema;
}

1;
