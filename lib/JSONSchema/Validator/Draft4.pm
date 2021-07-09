package JSONSchema::Validator::Draft4;

use strict;
use warnings;
use URI;
use Carp 'croak';

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
        append_errors => 1,
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
        user_agent_get => $user_agent_get,
        using_id_with_ref => $using_id_with_ref
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

sub append_error {
    my ($self, $errors, @messages) = @_;
    return $self unless $self->{append_errors};
    push @$errors, @messages;
    return $self;
}

sub validate_schema {
    my ($self, $instance, %params) = @_;

    my $schema = $params{schema} || $self->schema;
    my $path = $params{path} // '/';
    my $scope = $params{scope};

    croak 'No schema specified' unless $schema;

    push @{$self->scopes}, $scope if $scope;

    my $errors = [];
    my $result = $self->_validate_schema($instance, schema => $schema, path => $path, data => {errors => $errors});

    pop @{$self->scopes} if $scope;

    return $result, $errors;
}

sub _validate_schema {
    my ($self, $instance, %params) = @_;

    my ($schema, $path, $data) = @params{qw/schema path data/};

    my $apply_scope = $params{apply_scope} // 1;

    my $prev_append_errors = $self->{append_errors};
    $self->{append_errors} = $params{append_errors} // $prev_append_errors;

    my $id = $schema->{$self->ID};
    if ($id && $apply_scope && $self->using_id_with_ref) {
        my $uri = $id;
        $uri = URI->new($id)->abs($self->scope)->as_string if $self->scope;
        push @{$self->scopes}, $uri;
    }

    # if ref exists other preperties MUST be ignored
    my $ref = $schema->{'$ref'};
    my $_schema = $ref ? {'ref' => $ref} : $schema;

    my @schema_keys = $self->_schema_keys($_schema, $path, $data);

    my $result = 1;
    for my $k (@schema_keys) {
        my $v = $_schema->{$k};
        next unless my $constraint = $self->constraints->can($k);
        my $r = eval {
            $self->constraints->$constraint($instance, $v, schema => $schema, path => $path, data => $data);
        };
        if ($@) {
            $result = 0;
            $self->append_error($data->{errors}, "exception: $@");
        }
        $result = 0 unless $r;
    }

    pop @{$self->scopes} if $id && $apply_scope && $self->using_id_with_ref;

    $self->{append_errors} = $prev_append_errors;

    return $result;
}

sub _schema_keys {
    my ($self, $schema, $path, $data) = @_;
    return keys %$schema;
}

1;
