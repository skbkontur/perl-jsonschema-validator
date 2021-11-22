package JSONSchema::Validator::Error;

# ABSTRACT: Error class

use strict;
use warnings;

use overload
    '""' => sub { $_[0]->to_string },
    fallback => 1;

our @ISA = 'Exporter';
our @EXPORT_OK = qw(error);

sub error {
    return __PACKAGE__->new(@_);
}

sub new {
    my ($class, %params) = @_;

    return bless {
        message => $params{message},
        context =>  $params{context} // [],
        # parent => $params{parent},
        instance_path => $params{instance_path},
        schema_path => $params{schema_path}
    }, $class;
}

sub context { shift->{context} }
sub message { shift->{message} }
sub instance_path { shift->{instance_path} }
sub schema_path { shift->{schema_path} }

sub to_string {
    my $self = shift;
    my $msg = $self->message;
    my $instance_path = $self->instance_path;
    my $schema_path = $self->schema_path;
    $msg .= " [instance path: ${instance_path}]" if $instance_path;
    $msg .= " [schema path: ${schema_path}]" if $schema_path;
    return $msg;
}

sub unwind_to_string_list {
    my $self = shift;
    return [$self->to_string] unless @{$self->context};

    my $res = [];
    my $msg = $self->message;

    for my $err (@{$self->context}) {
        for my $err_str (@{$err->unwind_to_string_list}) {
            push @$res, "$msg: $err_str";
        }
    }

    return $res;
}

sub TO_JSON {
    my $self = shift;
    my $res = {
        message => $self->message
    };

    $res->{instance_path} = $self->instance_path
        if $self->instance_path;
    $res->{schema_path} = $self->schema_path
        if $self->schema_path;

    if (@{$self->context}) {
        $res->{context} = [
            map { $_->TO_JSON }
            @{$self->context}
            ];
    }

    return $res;
}

1;
