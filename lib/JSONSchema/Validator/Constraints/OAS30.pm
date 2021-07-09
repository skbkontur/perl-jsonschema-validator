package JSONSchema::Validator::Constraints::OAS30;

use strict;
use warnings;
use URI;
use Carp 'croak';

use parent 'JSONSchema::Validator::Constraints::Draft4';

use JSONSchema::Validator::Util qw(is_type serialize unbool round detect_type);

sub type {
    my ($self, $instance, $type, %params) = @_;

    if (is_type($instance, 'null', $self->strict)) {
        return $self->nullable( $instance,
                                $params{schema}{nullable} // 0,
                                schema => $params{schema},
                                path => $params{path},
                                data => $params{data});
    }

    my $result = 1;
    $result = 0 unless is_type($instance, $type, $self->strict);

    # # items must be present if type eq array
    # if ($result && $type eq 'array') {
    #     $result = 0 unless exists $params{schema}{items};
    # }

    return 1 if $result;

    $self->validator->append_error($params{data}{errors}, "type mismatch of instance $params{path}");
    return 0;
}

sub items {
    my ($self, $instance, $items, %params) = @_;
    return 1 unless is_type($instance, 'array', $self->strict);

    # items is object and NOT array

    my $result = 1;
    for my $i (0 .. $#{$instance}) {
        my $item = $instance->[$i];
        my $path = JSONSchema::Validator::JSONPointer->append($params{path}, $i);
        my $r = $self->validator->_validate_schema($item, schema => $items, path => $path, data => $params{data});
        $result = 0 unless $r;
    }
    return $result;
}

sub nullable {
    my ($self, $instance, $nullable, %params) = @_;
    # A true value adds "null" to the allowed type specified by the type keyword, only if type is explicitly defined within the same Schema Object.
    return 1 unless $params{schema}{type};
    return 1 if $nullable;
    unless (defined $instance) {
        $self->validator->append_error($params{data}{errors}, "instance $params{path} is nullable");
        return 0;
    }
    return 1;
}

sub readOnly {
    my ($self, $instance, $readOnly, %params) = @_;
    return 1 unless $readOnly;
    return 1 if $params{data}{direction} eq 'response';

    $self->validator->append_error($params{data}{errors}, "instance $params{path} is invalid in request because of readOnly property");
    return 0;
}

sub writeOnly {
    my ($self, $instance, $writeOnly, %params) = @_;
    return 1 unless $writeOnly;
    return 1 if $params{data}{direction} eq 'request';

    $self->validator->append_error($params{data}{errors}, "instance $params{path} is invalid in response because of writeOnly property");
    return 0;
}

sub required {
    my ($self, $instance, $required, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);

    my $result = 1;
    for my $prop (@$required) {
        next if exists $instance->{$prop};

        if ($params{schema}{properties} && $params{schema}{properties}{$prop}) {
            my $prop = $params{schema}{properties}{$prop};
            my $read_only = $prop->{readOnly} // 0;
            my $write_only = $prop->{writeOnly} // 0;
            my $direction = $params{data}{direction};

            next if $direction eq 'request' && $read_only;
            next if $direction eq 'response' && $write_only;
        }

        $self->validator->append_error($params{data}{errors}, "instance $params{path} does not have required property $prop");
        $result = 0;
    }
    return $result;
}

sub discriminator {
    my ($self, $instance, $discriminator, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);

    my $path = $params{path};
    my $status = $params{data}{discriminator}{$path} // 'no';

    my $property_name = $discriminator->{propertyName};
    my $mapping = $discriminator->{mapping} // {};

    my $type = $instance->{$property_name};
    my $ref = $mapping->{$type};

    $ref = $self->__detect_discriminator_ref($ref || $type);

    # status "processing" needs to prevent recursion
    $params{data}{discriminator}{$path} = 'processing';

    my $scope = $self->validator->scope;
    $ref = URI->new($ref);
    $ref = $ref->abs($scope) if $scope;

    my ($current_scope, $schema) = $self->validator->resolver->resolve($ref);

    croak "schema not resolved by ref $ref" unless $schema;

    push @{$self->validator->scopes}, $current_scope;

    my $result = eval {
        $self->validator->_validate_schema($instance, schema => $schema, path => $params{path}, data => $params{data}, apply_scope => 0);
    };

    if ($@) {
        $result = 0;
        $self->validator->append_error($params{data}{errors}, "exception: $@");
    }

    pop @{$self->validator->scopes};

    delete $params{data}{discriminator}{$path};

    return $result;
}

sub deprecated {
    my ($self, $instance, $deprecated, %params) = @_;
    return 1 unless $deprecated;
    $self->validator->append_error($params{data}{warnings}, "instance $params{path} is deprecated");
    return 1;
}

# Additional properties defined by the JSON Schema specification that are not mentioned in OAS30 are strictly unsupported.
sub dependencies { 1 }
sub additionalItems { 1 }
sub patternProperties { 1 }

sub __detect_discriminator_ref {
    my ($self, $ref) = @_;
    # heuristic
    return $ref if $ref =~ m|/|;
    return $ref if $ref =~ m/\.json$/;
    return '#/components/schemas/' . $ref;
}

1;
