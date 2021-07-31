package JSONSchema::Validator::Draft6;

# ABSTRACT: Validator for JSON Schema Draft6

use strict;
use warnings;

use JSONSchema::Validator::Constraints::Draft6;

use parent 'JSONSchema::Validator::Draft4';

use constant SPECIFICATION => 'Draft6';
use constant ID => 'http://json-schema.org/draft-06/schema#';
use constant ID_FIELD => '$id';

sub new {
    my ($class, %params) = @_;

    my $self = $class->create(%params);

    my $constraints = JSONSchema::Validator::Constraints::Draft6->new(validator => $self, strict => $params{strict} // 1);
    $self->{constraints} = $constraints;

    return $self;
}

1;

__END__

=head1 SYNOPSIS

    $validator = JSONSchema::Validator::Draft6->new(schema => {...});
    my ($result, $errors) = $validator->validate_schema($object_to_validate);

=head1 DESCRIPTION

JSON Schema Draft6 validator with minimum dependencies.

=head1 CLASS METHODS

=head2 new

Creates JSONSchema::Validator::Draft6 object.

    $validator = JSONSchema::Validator::Draft6->new(schema => {...});

=head3 Parameters

=head4 schema

Scheme according to which validation occurs.

=head4 strict

Use strong type checks. Default value is 1.

=head4 using_id_with_ref

Consider key C<$id> to identify subschema when resolving links.
For more details look at json schema docs about L<named anchors|https://json-schema.org/understanding-json-schema/structuring.html#id12> and L<bundling|https://json-schema.org/understanding-json-schema/structuring.html#id19>.

=head4 scheme_handlers

At the moment, the validator can load a resource using the http, https protocols. You can add other protocols yourself.

    sub loader {
        my $uri = shift;
        ...
    }
    $validator = JSONSchema::Validator::Draft6->new(schema => {...}, scheme_handlers => {ftp => \&loader});

=head1 METHODS

=head2 validate_schema

Validate object instance according to schema.

=cut
