package JSONSchema::Validator::OAS30;

use strict;
use warnings;
use Carp 'croak';

use JSONSchema::Validator::JSONPointer;
use JSONSchema::Validator::Error 'error';
use JSONSchema::Validator::Constraints::OAS30;
use JSONSchema::Validator::URIResolver;
use JSONSchema::Validator::Util 'json_decode';

use parent 'JSONSchema::Validator::Draft4';

use constant ID => '';

sub new {
    my ($class, %params) = @_;

    $params{using_id_with_ref} = 0;
    my $self = $class->SUPER::new(%params);

    my $validate_deprecated = $params{validate_deprecated} // 1;
    $self->{validate_deprecated} = $validate_deprecated;

    my $constraints = JSONSchema::Validator::Constraints::OAS30->new(validator => $self, strict => $params{strict} // 0);
    $self->{constraints} = $constraints;

    return $self;
}

sub validate_deprecated { shift->{validate_deprecated} }

sub validate_schema {
    my ($self, $instance, %params) = @_;

    my $schema = $params{schema} || $self->schema;
    my $instance_path = $params{instance_path} // '/';
    my $schema_path = $params{schema_path} // '/';
    my $direction = $params{direction};
    my $scope = $params{scope};

    croak 'param "direction" is required' unless $direction;
    croak '"direction" must have one of values: request, response'
        if $direction ne 'request' && $direction ne 'response';

    croak 'No schema specified' unless $schema;

    push @{$self->scopes}, $scope if $scope;

    my ($errors, $warnings) = ([], []);
    my $result = $self->_validate_schema($instance, $schema, $instance_path, $schema_path, {
            errors => $errors,
            warnings => $warnings,
            direction => $direction
        }
    );

    pop @{$self->scopes} if $scope;

    return $result, $errors, $warnings;
}

sub _schema_keys {
    my ($self, $schema, $instance_path, $data) = @_;
    # if ref exists other preperties MUST be ignored
    return '$ref' if $schema->{'$ref'};

    return ('deprecated') if $schema->{deprecated} && !$self->validate_deprecated;

    if (grep { $_ eq 'discriminator' } keys %$schema) {
        my $status = $data->{discriminator}{$instance_path} // 0;
        return ('discriminator') unless $status;

        # status is 1
        return grep { $_ ne 'discriminator' } keys %$schema;
    }

    return keys %$schema;
}

sub validate_request {
    my ($self, %params) = @_;

    my $method = lc($params{method} or croak 'param "method" is required');
    my $openapi_path = $params{openapi_path} or croak 'param "openapi_path" is required';

    my $get_user_param = $self->_wrap_params($params{parameters});

    my $user_body = $params{parameters}{body} // []; # [exists, content-type, value]

    my $base_ptr = $self->json_pointer->xget('paths', $openapi_path);
    return 1, [], [] unless $base_ptr;

    my $schema_params = {query => {}, header => {}, path => {}, cookie => {}};

    # Common Parameter Object
    my $common_params_ptr = $base_ptr->xget('parameters');
    $self->_fill_parameters($schema_params, $common_params_ptr);

    # Operation Object
    my $operation_ptr = $base_ptr->xget($method);
    return 1, [], [] unless $operation_ptr;

    my ($result, $context) = (1, {errors => [], warnings => [], direction => 'request'});
    if ($operation_ptr->xget('deprecated')) {
        push @{$context->{warnings}}, error(message => "method $method of $openapi_path is deprecated");
        return $result, $context->{errors}, $context->{warnings} unless $self->validate_deprecated;
    }

    # Parameter Object
    my $params_ptr = $operation_ptr->xget('parameters');
    $self->_fill_parameters($schema_params, $params_ptr);

    # validate path, query, header, cookie
    my $r = $self->_validate_params($context, $schema_params, $get_user_param);
    $result = 0 unless $r;

    # validate body
    my $body_ptr = $operation_ptr->xget('requestBody');
    $r = $self->_validate_body($context, $user_body, $body_ptr);
    $result = 0 unless $r;

    return $result, $context->{errors}, $context->{warnings};
}

sub validate_response {
    my ($self, %params) = @_;

    my $method = lc($params{method} or croak 'param "method" is required');
    my $openapi_path = $params{openapi_path} or croak 'param "openapi_path" is required';
    my $http_status = $params{status} or croak 'param "status" is required';

    my $get_user_param = $self->_wrap_params($params{parameters});

    my $user_body = $params{parameters}{body} // []; # [exists, content-type, value]

    my $base_ptr = $self->json_pointer->xget('paths', $openapi_path, $method);
    return 1, [], [] unless $base_ptr;

    my ($result, $context) = (1, {errors => [], warnings => [], direction => 'response'});
    if ($base_ptr->xget('deprecated')) {
        push @{$context->{warnings}}, error(message => "method $method of $openapi_path is deprecated");
        return $result, $context->{errors}, $context->{warnings} unless $self->validate_deprecated;
    }

    my $responses_ptr = $base_ptr->xget('responses');
    return $result, $context->{errors}, $context->{warnings} unless $responses_ptr;

    my $status_ptr = $responses_ptr->xget($http_status);
    $status_ptr = $responses_ptr->xget('default') unless $status_ptr;

    unless ($status_ptr) {
        push @{$context->{errors}}, error(message => "unspecified response with status code $http_status");
        return 0, $context->{errors}, $context->{warnings};
    }

    my $schema_params = {header => {}};
    $self->_fill_parameters($schema_params, $status_ptr->xget('headers'));

    # validate headers
    my $r = $self->_validate_params($context, $schema_params, $get_user_param);
    $result = 0 unless $r;

    # validate body
    my ($exists, $content_type, $data) = @$user_body;
    return $result, $context->{errors}, $context->{warnings} unless $exists;

    ($r, my $errors, my $warnings) = $self->_validate_content($context, $status_ptr, $content_type, $data);
    unless ($r) {
        push @{$context->{errors}}, error(message => 'response body error', context => $errors);
        $result = 0;
    }
    push @{$context->{warnings}}, error(message => 'response body warning', context => $warnings) if @$warnings;

    return $result, $context->{errors}, $context->{warnings};
}

sub _validate_body {
    my ($self, $ctx, $user_body, $body_ptr) = @_;

    # body in specification is omit
    return 1 unless $body_ptr;

    # skip validation if user not specify body
    return 1 unless $user_body && @$user_body;

    my ($exists, $content_type, $data) = @$user_body;

    unless ($exists) {
        my $required = $body_ptr->xget('required');
        if ($required) {
            push @{$ctx->{errors}}, error(message => q{body is required});
            return 0;
        }
        return 1;
    }

    my ($result, $errors, $warnings) = $self->_validate_content($ctx, $body_ptr, $content_type, $data);
    push @{$ctx->{errors}}, error(message => 'request body error', context => $errors) if @$errors;
    push @{$ctx->{warnings}}, error(message => 'request body warning', context => $warnings) if @$warnings;
    return $result;
}

sub _validate_params {
    my ($self, $ctx, $schema_params, $get_user_param) = @_;
    my $result = 1;
    for my $type (keys %$schema_params) {
        next unless %{$schema_params->{$type}};
        # skip validation if user not specify getter for such params type
        next unless $get_user_param->{$type};
        my $r = $self->_validate_type_params($ctx, $type, $schema_params->{$type}, $get_user_param->{$type});
        $result = 0 unless $r;
    }
    return $result;
}

sub _validate_type_params {
    my ($self, $ctx, $type, $params, $get_user_param) = @_;

    my $result = 1;
    for my $param (keys %$params) {
        my $data_ptr = $params->{$param};

        my ($exists, $value) = $get_user_param->($param);
        ($exists, $value) = $get_user_param->(lc $param) if !$exists && $type eq 'header';

        unless ($exists) {
            if ($data_ptr->xget('required')) {
                push @{$ctx->{errors}}, error(message => qq{$type param "$param" is required});
                $result = 0;
            }
            next;
        }

        if ($data_ptr->xget('deprecated')) {
            push @{$ctx->{warnings}}, error(message => qq{$type param "$param" is deprecated});
            next unless $self->validate_deprecated;
        }

        next unless $data_ptr->xget('schema') || $data_ptr->xget('content');

        $value = [$value] if ref $value ne 'ARRAY';

        for my $v (@$value) {
            my ($r, $errors, $warnings);

            if ($data_ptr->xget('schema')) {
                my $schema_ptr = $data_ptr->xget('schema');
                ($r, $errors, $warnings) = $self->validate_schema($v,
                    schema => $schema_ptr->value,
                    path => '/',
                    direction => $ctx->{direction},
                    scope => $schema_ptr->scope
                );
            } elsif ($data_ptr->xget('content')) {
                ($r, $errors, $warnings) = $self->_validate_content($ctx, $data_ptr, undef, $v);
            }

            unless ($r) {
                push @{$ctx->{errors}}, error(message => qq{$type param "$param" has error}, context => $errors);
                $result = 0;
            }
            push @{$ctx->{warnings}}, error(message => qq{$type param "$param" has warning}, context => $warnings) if @$warnings;
        }
    }

    return $result;
}

# ptr - JSONSchema::Validator::JSONPointer
# content_type - string|null
# data - string|HASH|ARRAY
sub _validate_content {
    my ($self, $ctx, $ptr, $content_type, $data) = @_;

    my $content_ptr = $ptr->xget('content');
    # content in body is required but in params is optional
    return 1, [] unless $content_ptr;

    my $ctype_ptr;
    if ($content_type) {
        $ctype_ptr = $content_ptr->xget($content_type);
        unless ($ctype_ptr) {
            return 0, [qq{content with content-type $content_type is omit in schema}];
        }
    } else {
        my $mtype_map = $content_ptr->value;
        my @keys = $content_ptr->keys(raw => 1);
        return 0, [qq{schema has more than one content_type}] if scalar(@keys) > 1;

        $content_type = $keys[0];
        $ctype_ptr = $content_ptr->xget($content_type);
    }

    unless (ref $data) {
        if ($content_type eq 'application/json') {
            $data = json_decode($data);
        }
        # need to support other content-type?
    }

    my $schema_ptr = $ctype_ptr->xget('schema');
    return $self->validate_schema($data,
        schema => $schema_ptr->value,
        path => '/',
        direction => $ctx->{direction},
        scope => $schema_ptr->scope
    );
}

sub _fill_parameters {
    my ($self, $hash, $ptr) = @_;
    return unless ref $ptr->value;

    if (ref $ptr->value eq 'ARRAY') {
        for my $p ($ptr->keys) {
            my $param_ptr = $ptr->get($p);
            my $param = $param_ptr->value;

            my ($name, $in) = @$param{qw/name in/};

            $hash->{$in}{$name} = $param_ptr;
        }
    } elsif (ref $ptr->value eq 'HASH') {
        # currently used for headers in response
        my $in = 'header';
        for my $name ($ptr->keys(raw => 1)) {
            my $param_ptr = $ptr->xget($name);
            $hash->{$in}{$name} = $param_ptr;
        }
    }
}

sub _wrap_params {
    my ($self, $parameters) = @_;

    my $get_user_param = {};
    for my $type (qw/path query header cookie/) {
        next unless $parameters->{$type};

        if (ref $parameters->{$type} eq 'CODE') {
            $get_user_param->{$type} = $parameters->{$type};
        } elsif (ref $parameters->{$type} eq 'HASH') {
            my $data = $parameters->{$type};
            $data = +{ map { lc $_ => $data->{$_} } keys %$data } if $type eq 'header';
            $get_user_param->{$type} = sub {
                my $param = shift;
                return (exists($data->{$param}), $data->{$param});
            }
        } else {
            croak qq{param "$type" must be hashref or coderef};
        }
    }

    return $get_user_param;
}

sub json_pointer {
    my $self = shift;
    return JSONSchema::Validator::JSONPointer->new(
        scope => $self->scope,
        value => $self->schema,
        validator => $self
    );
}

1;
