package JSONSchema::Validator::JSONPointer;

use strict;
use warnings;
use URI;
use Carp 'croak';

use Scalar::Util 'weaken';

use overload
    'bool' => sub { $_[0]->value },
    fallback => 1;

sub append {
    my ($class, $path, $value) = @_;
    return $path =~ m!/$!
        ? $path . $class->escape($value)
        : $path . '/' . $class->escape($value);
}

sub join {
    my ($class, @parts) = @_;
    return '/' . join('/', map { $class->escape($_) } @parts);
}

sub escape {
    my ($class, $value) = @_;
    $value =~ s!~!~0!g;
    $value =~ s!/!~1!g;
    return $value;
}

sub unescape {
    my ($class, $value) = @_;
    $value =~ s!~1!/!g;
    $value =~ s!~0!~!g;
    return $value;
}

sub new {
    my ($class, %params) = @_;

    my ($scope, $value, $validator, $using_id_with_ref) = @params{qw/scope value validator using_id_with_ref/};
    
    croak 'JSONPointer: scope is required' unless defined $scope;
    croak 'JSONPointer: validator is required' unless $validator;

    weaken($validator);

    my $self = {
        scope => $scope,
        value => $value,
        validator => $validator,
        using_id_with_ref => ($using_id_with_ref // 0)
    };

    bless $self, $class;

    return $self;
}

sub validator { shift->{validator} }
sub using_id_with_ref { shift->{using_id_with_ref} }
sub scope { shift->{scope} }
sub value { shift->{value} }

sub get {
    # orig_pointer is string which is already urldecoded and utf8-decoded 
    my ($self, $orig_pointer, %params) = @_;
    return $self unless $orig_pointer;

    my $throw_exception = $params{throw_exception} // 0;
    
    my $pointer = $orig_pointer;
    croak "Invalid JSON Pointer $pointer" unless $pointer =~ s!^/!!;

    my @parts = length $pointer
                    ? map { $self->unescape($_) } split(/\//, $pointer, -1)
                    : ('');

    my $current_scope = $self->scope;
    my $current_value = $self->value;

    while (ref $current_value eq 'HASH' && $current_value->{'$ref'}) {
        my $ref = URI->new($current_value->{'$ref'});
        $ref = $ref->abs($current_scope) if $current_scope;
        ($current_scope, $current_value) = $self->validator->resolver->resolve($ref);
    }

    if (ref $current_value eq 'HASH' && $self->using_id_with_ref) {
        my $id = $current_value->{$self->validator->ID};
        if ($id && !ref $id) {
            $current_scope = $current_scope
                ? URI->new($id)->abs($current_scope)->as_string
                : $id;
        }
    }

    for my $part (@parts) {
        if (ref $current_value eq 'HASH' && exists $current_value->{$part}) {
            $current_value = $current_value->{$part};
        } elsif (ref $current_value eq 'ARRAY' && $part =~ m/^\d+$/ && scalar(@$current_value) > $part) {
            $current_value = $current_value->[$part];
        } else {
            croak "Unresolvable JSON Pointer: $orig_pointer" if $throw_exception;
            $current_value = undef;
            last;
        }

        while (ref $current_value eq 'HASH' && $current_value->{'$ref'}) {
            my $ref = URI->new($current_value->{'$ref'});
            $ref = $ref->abs($current_scope) if $current_scope;
            ($current_scope, $current_value) = $self->validator->resolver->resolve($ref);
        }

        if (ref $current_value eq 'HASH' && $self->using_id_with_ref) {
            my $id = $current_value->{$self->validator->ID};
            if ($id && !ref $id) {
                $current_scope = $current_scope
                    ? URI->new($id)->abs($current_scope)->as_string
                    : $id;
            }
        }
    }

    return __PACKAGE__->new(
        value => $current_value,
        scope => $current_scope,
        validator => $self->validator,
        using_id_with_ref => $self->using_id_with_ref
    )
}

sub xget {
    my $self = shift;
    return $self->get($self->join(@_));
}

sub keys {
    my ($self, %params) = @_;
    my $raw = $params{raw} // 0;

    if (ref $self->value eq 'HASH') {
        return map { $raw ? $_ : $self->join($_) } keys %{$self->value};
    }

    if (ref $self->value eq 'ARRAY') {
        return map { $raw ? $_ : $self->join($_) } 0 .. $#{$self->value};
    }

    return;
}

1;
