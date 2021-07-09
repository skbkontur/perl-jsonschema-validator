package JSONSchema::Validator::Constraints::Draft4;

use strict;
use warnings;
use Scalar::Util 'weaken';
use URI;
use Carp 'croak';

use JSONSchema::Validator::JSONPointer;
use JSONSchema::Validator::Util qw(serialize unbool round is_type detect_type);
use JSONSchema::Validator::Format qw(
    validate_date_time validate_date validate_time
    validate_email validate_hostname
    validate_idn_email
    validate_ipv4 validate_ipv6
    validate_uuid
    validate_byte
    validate_int32 validate_int64
    validate_float validate_double
    validate_regex
    validate_json_pointer validate_relative_json_pointer
    validate_uri validate_uri_reference
    validate_iri validate_iri_reference
    validate_uri_template
);

use constant FORMAT_VALIDATIONS => {
    'date-time' => ['string', \&validate_date_time],
    'date' => ['string', \&validate_date],
    'time' => ['string', \&validate_time],
    'email' => ['string', \&validate_email],
    'idn-email' => ['string', \&validate_idn_email],
    'hostname' => ['string', \&validate_hostname],
    'ipv4' => ['string', \&validate_ipv4],
    'ipv6' => ['string', \&validate_ipv6],
    'uuid' => ['string', \&validate_uuid],
    'byte' => ['string', \&validate_byte],
    'int32' => ['integer', \&validate_int32],
    'int64' => ['integer', \&validate_int64],
    'float' => ['number', \&validate_float],
    'double' => ['number', \&validate_double],
    'regex' => ['string', \&validate_regex],
    'json-pointer' => ['string', \&validate_json_pointer],
    'relative-json-pointer' => ['string', \&validate_relative_json_pointer],
    'uri' => ['string', \&validate_uri],
    'uri-reference' => ['string', \&validate_uri_reference],
    'iri' => ['string', \&validate_iri],
    'iri-reference' => ['string', \&validate_iri_reference],
    'uri-template' => ['string', \&validate_uri_template]
};
use constant EPSILON => 1e-7;

sub new {
    my ($class, %params) = @_;
    
    my $validator = $params{validator} or croak 'validator is required';
    my $strict = $params{strict} // 1;

    weaken($validator);

    my $self = {
        validator => $validator,
        errors => [],
        strict => $strict
    };

    bless $self, $class;

    return $self;
}

sub validator { shift->{validator} }
sub strict { shift->{strict} }

sub type {
    my ($self, $instance, $types, %params) = @_;
    my @types = ref $types ? @$types : ($types);

    return 1 if grep { is_type($instance, $_, $self->strict) } @types;

    $self->validator->append_error($params{data}{errors}, "type mismatch of instance $params{path}");
    return 0;
}

sub minimum {
    my ($self, $instance, $minimum, %params) = @_;
    return 1 unless is_type($instance, 'number', $self->strict);
    return 1 if $instance >= $minimum;
    $self->validator->append_error($params{data}{errors}, "instance $params{path} is less than minimum of $minimum");
    return 0;
}

sub maximum {
    my ($self, $instance, $maximum, %params) = @_;
    return 1 unless is_type($instance, 'number', $self->strict);
    return 1 if $instance <= $maximum;
    $self->validator->append_error($params{data}{errors}, "instance $params{path} is greater than maximum of $maximum");
    return 0;
}

sub exclusiveMaximum {
    my ($self, $instance, $exclusiveMaximum, %params) = @_;
    return 1 unless is_type($instance, 'number', $self->strict);
    my $maximum = $params{schema}{maximum};

    my $res = $self->maximum($instance, $maximum, %params);
    return 0 unless $res;
    return 1 unless $exclusiveMaximum;
    return 1 if $instance != $maximum;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} is equal to $maximum");
    return 0;
}

sub exclusiveMinimum {
    my ($self, $instance, $exclusiveMinimum, %params) = @_;
    return 1 unless is_type($instance, 'number', $self->strict);
    my $minimum = $params{schema}{minimum};

    my $res = $self->minimum($instance, $minimum, %params);
    return 0 unless $res;
    return 1 unless $exclusiveMinimum;
    return 1 if $instance != $minimum;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} is equal to $minimum");
    return 0;
}

sub minItems {
    my ($self, $instance, $min, %params) = @_;
    return 1 unless is_type($instance, 'array', $self->strict);
    return 1 if scalar(@$instance) >= $min;
    $self->validator->append_error($params{data}{errors}, "instance $params{path} is shorter than $min");
    return 0;
}

sub maxItems {
    my ($self, $instance, $max, %params) = @_;
    return 1 unless is_type($instance, 'array', $self->strict);
    return 1 if scalar(@$instance) <= $max;
    $self->validator->append_error($params{data}{errors}, "instance $params{path} is longer than $max");
    return 0;
}

sub minLength {
    my ($self, $instance, $min, %params) = @_;
    return 1 unless is_type($instance, 'string', $self->strict);
    return 1 if length $instance >= $min;
    $self->validator->append_error($params{data}{errors}, "instance $params{path} is shorter than $min");
    return 0;
}

sub maxLength {
    my ($self, $instance, $max, %params) = @_;
    return 1 unless is_type($instance, 'string', $self->strict);
    return 1 if length $instance <= $max;
    $self->validator->append_error($params{data}{errors}, "instance $params{path} is longer than $max");
    return 0;
}

sub dependencies {
    my ($self, $instance, $dependencies, %params) = @_;

    # ignore non-object
    return 1 unless is_type($instance, 'object', $self->strict);

    my $result = 1;

    for my $prop (keys %$dependencies) {
        my $dep = $dependencies->{$prop};
        next unless exists $instance->{$prop};

        if (is_type($dep, 'object', 1)) {
            my $r = $self->validator->_validate_schema($instance, schema => $dep, path => $params{path}, data => $params{data});
            $result = 0 unless $r;
        } elsif (is_type($dep, 'array', 1)) {
            for my $p (@$dep) {
                next if exists $instance->{$p};

                $self->validator->append_error($params{data}{errors}, "instance $params{path}/$p is ommited");
                $result = 0;
            }
        }
    }

    return $result;
}

sub additionalItems {
    my ($self, $instance, $additionalItems, %params) = @_;
    return 1 unless is_type($instance, 'array', $self->strict);
    return 1 if is_type($params{schema}{items} // {}, 'object', 1);

    my $len_items = scalar @{$params{schema}{items}};

    if (is_type($additionalItems, 'boolean', 1)) {
        return 1 if $additionalItems;
        if  (scalar @$instance > $len_items) {
            $self->validator->append_error($params{data}{errors}, "instance $params{path}/items has additional items");
            return 0;
        }

        return 1;
    }

    # additionalItems is object

    my $result = 1;
    my @items_last_part = @$instance[$len_items .. $#{$instance}];

    for my $index (0 .. $#items_last_part) {
        my $item = $items_last_part[$index];

        my $path = JSONSchema::Validator::JSONPointer->append($params{path}, $len_items + $index);
        my $r = $self->validator->_validate_schema($item, schema => $additionalItems, path => $path, data => $params{data});
        $result = 0 unless $r;
    }

    return $result;
}

sub additionalProperties {
    my ($self, $instance, $addProps, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);

    my $patterns = join '|', keys %{$params{schema}{patternProperties} // {}};

    my @extra_props;
    for my $p (keys %$instance) {
        next if $params{schema}{properties} && exists $params{schema}{properties}{$p};
        next if $patterns && $p =~ m/$patterns/u;
        push @extra_props, $p;
    }

    return 1 unless @extra_props;

    if (is_type($addProps, 'object', 1)) {
        my $result = 1;
        for my $p (@extra_props) {
            my $path = JSONSchema::Validator::JSONPointer->append($params{path}, $p);
            my $r = $self->validator->_validate_schema($instance->{$p}, schema => $addProps, path => $path, data => $params{data});
            $result = 0 unless $r;
        }
        return $result;
    }

    # addProps is boolean

    return 1 if $addProps;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} has additional properties: " . join(', ', @extra_props));
    return 0;
}

sub allOf {
    my ($self, $instance, $allOf, %params) = @_;

    my $result = 1;
    for my $subschema (@$allOf) {
        my $r = $self->validator->_validate_schema($instance, schema => $subschema, path => $params{path}, data => $params{data});
        $result = 0 unless $r;
    }

    return $result;
}

sub anyOf {
    my ($self, $instance, $anyOf, %params) = @_;

    my $result = 0;
    for my $subschema (@$anyOf) {
        $result = $self->validator->_validate_schema($instance, schema => $subschema, path => $params{path}, data => $params{data}, append_errors => 0);
        last if $result;
    }

    return 1 if $result;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} does not satisfy any schema");
    return 0;
}

sub oneOf {
    my ($self, $instance, $oneOf, %params) = @_;

    my $num = 0;
    for my $subschema (@$oneOf) {
        my $r = $self->validator->_validate_schema($instance, schema => $subschema, path => $params{path}, data => $params{data}, append_errors => 0);
        ++$num if $r;
    }

    return 1 if $num == 1;

    $num > 1
        ? $self->validator->append_error($params{data}{errors}, "instance $params{path} is valid under more than one schema")
        : $self->validator->append_error($params{data}{errors}, "instance $params{path} is not valid under any of given schemas");
    
    return 0;
}

sub enum {
    my ($self, $instance, $enum, %params) = @_;

    my $result = 0;
    for my $e (@$enum) {
        if (is_type($e, 'boolean', 1)) {
            $result = is_type($instance, 'boolean', $self->strict)
                        ? unbool($instance) eq unbool($e)
                        : 0
        } elsif (is_type($e, 'object', 1) || is_type($e, 'array', 1)) {
            $result =   is_type($instance, 'object', $self->strict) ||
                        is_type($instance, 'array', $self->strict)
                        ? serialize($instance) eq serialize($e)
                        : 0;
        } elsif (is_type($e, 'number', 1)) {
            $result =   is_type($instance, 'number', $self->strict)
                        ? $e == $instance
                        : 0;
        } elsif (defined $e && defined $instance) {
            $result = $e eq $instance;
        } elsif (!defined $e && !defined $instance) {
            $result = 1;
        } else {
            $result = 0;
        }
        last if $result;
    }
    
    return 1 if $result;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} is not of enums");
    return 0;
}

sub items {
    my ($self, $instance, $items, %params) = @_;
    return 1 unless is_type($instance, 'array', $self->strict);

    my $result = 1;
    if (is_type($items, 'array', 1)) {
        my $min = $#{$items} > $#{$instance} ? $#{$instance} : $#{$items};
        for my $i (0 .. $min) {
            my $item = $instance->[$i];
            my $subschema = $items->[$i];
            my $path = JSONSchema::Validator::JSONPointer->append($params{path}, $i);
            my $r = $self->validator->_validate_schema($item, schema => $subschema, path => $path, data => $params{data});
            $result = 0 unless $r;
        }
    } else {
        # items is object
        for my $i (0 .. $#{$instance}) {
            my $item = $instance->[$i];
            my $path = JSONSchema::Validator::JSONPointer->append($params{path}, $i);
            my $r = $self->validator->_validate_schema($item, schema => $items, path => $path, data => $params{data});
            $result = 0 unless $r;
        }
    }
    return $result;
}

sub format {
    my ($self, $instance, $format, %params) = @_;
    return 1 unless exists FORMAT_VALIDATIONS->{$format};

    my ($type, $checker) = @{FORMAT_VALIDATIONS->{$format}};
    return 1 unless is_type($instance, $type, $self->strict);

    my $result = $checker->($instance);
    return 1 if $result;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} is not $format");
    return 0;
}

sub maxProperties {
    my ($self, $instance, $maxProperties, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);
    return 1 if scalar(keys %$instance) <= $maxProperties;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} has more than $maxProperties properties");
    return 0;
}

sub minProperties {
    my ($self, $instance, $minProperties, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);
    return 1 if scalar(keys %$instance) >= $minProperties;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} has less than $minProperties properties");
    return 0;
}

sub multipleOf {
    my ($self, $instance, $multipleOf, %params) = @_;
    return 1 unless is_type($instance, 'number', $self->strict);

    my $result = 1;
    my $div = $instance / $multipleOf;
    $result = 0 if abs($div - round($div)) > EPSILON;

    return 1 if $result;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} is not multiple of $multipleOf");
    return 0;
}

sub not {
    my ($self, $instance, $not, %params) = @_;
    # not is schema
    my $result = $self->validator->_validate_schema($instance, schema => $not, path => $params{path}, data => $params{data}, append_errors => 0);
    return 1 unless $result;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} satisfies the schema defined in \"not\" keyword");
    return 0;
}

sub pattern {
    my ($self, $instance, $pattern, %params) = @_;
    return 1 unless is_type($instance, 'string', $self->strict);
    return 1 if $instance =~ m/$pattern/u;

    $self->validator->append_error($params{data}{errors}, "instance $params{path} does not match $pattern");
    return 0;
}

sub patternProperties {
    my ($self, $instance, $patternProperties, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);

    my $result = 1;
    for my $pattern (keys %$patternProperties) {
        my $subschema = $patternProperties->{$pattern};
        for my $k (keys %$instance) {
            my $v = $instance->{$k};
            if ($k =~ m/$pattern/u) {
                my $path = JSONSchema::Validator::JSONPointer->append($params{path}, $k);
                my $r = $self->validator->_validate_schema($v, schema => $subschema, path => $path, data => $params{data});
                $result = 0 unless $r;
            }
        }
    }
    return $result;
}

sub properties {
    my ($self, $instance, $properties, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);

    my $result = 1;
    for my $prop (keys %$properties) {
        next unless exists $instance->{$prop};

        my $subschema = $properties->{$prop};
        my $path = JSONSchema::Validator::JSONPointer->append($params{path}, $prop);
        my $r = $self->validator->_validate_schema($instance->{$prop}, schema => $subschema, path => $path, data => $params{data});
        $result = 0 unless $r;
    }
    return $result;
}

sub required {
    my ($self, $instance, $required, %params) = @_;
    return 1 unless is_type($instance, 'object', $self->strict);

    my $result = 1;
    for my $prop (@$required) {
        next if exists $instance->{$prop};
        $self->validator->append_error($params{data}{errors}, "instance $params{path} does not have required property $prop");
        $result = 0;
    }
    return $result;
}

# doesn't work for string that looks like number with the same number in array
sub uniqueItems {
    my ($self, $instance, $uniqueItems, %params) = @_;
    return 1 unless is_type($instance, 'array', $self->strict);
    # uniqueItems is boolean
    return 1 unless $uniqueItems;

    my %hash = map {
        my $type = detect_type($_, $self->strict);

        my $value;
        if ($type eq 'null') {
            $value = ''
        } elsif ($type eq 'object' || $type eq 'array') {
            $value = serialize($_);
        } elsif ($type eq 'boolean') {
            $value = "$_";
        } else {
            # integer/number/string
            $value = $_;
        }

        my $key = "${type}#${value}";
        $key => 1;
    } @$instance;
    return 1 if scalar(keys %hash) == scalar @$instance;
    $self->validator->append_error($params{data}{errors}, "instance $params{path} has non-unique elements");
    return 0;
}

sub ref {
    my ($self, $instance, $ref, %params) = @_;

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

    return $result;
}

1;