package JSONSchema::Validator::Constraints::Draft7;

# ABSTRACT: JSON Schema Draft7 specification constraints

use strict;
use warnings;

use JSONSchema::Validator::JSONPointer 'json_pointer';
use JSONSchema::Validator::Error 'error';
use JSONSchema::Validator::Util qw(is_type serialize unbool);

use parent 'JSONSchema::Validator::Constraints::Draft6';

sub if {
    my ($self, $instance, $if, $schema, $instance_path, $schema_path, $data) = @_;

    my $errors = $data->{errors};
    $data->{errors} = [];

    my $result = $self->validator->_validate_schema($instance, $if, $instance_path, $schema_path, $data);
    $data->{errors} = $errors;
    if ($result) {
        return 1 unless exists $schema->{then};
        my $then = $schema->{then};
        my $spath = json_pointer->append($schema_path, 'then');
        return $self->validator->_validate_schema($instance, $then, $instance_path, $spath, $data);
    }

    return 1 unless exists $schema->{else};
    my $else = $schema->{else};
    my $spath = json_pointer->append($schema_path, 'else');
    return $self->validator->_validate_schema($instance, $else, $instance_path, $spath, $data);
}

1;
