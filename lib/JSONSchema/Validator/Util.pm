package JSONSchema::Validator::Util;

# ABSTRACT: Useful functions

use strict;
use warnings;

use B ();
use Carp 'croak';
use File::Basename ();
use File::Fetch ();
use Scalar::Util qw( blessed looks_like_number );
use URI 1.00 ();

our @ISA = 'Exporter';
our @EXPORT_OK = qw(
    json_encode json_decode serialize unbool
    round is_type detect_type
    data_section load_schema
);

use constant CONTENT_TYPE_JSON => 'JSON';
use constant CONTENT_TYPE_YAML => 'YAML';

use constant TYPE_MAP => {
    'array' => \&is_array,
    'boolean' => \&is_bool,
    'integer' => \&is_integer,
    'number' => \&is_number,
    'object' => \&is_object,
    'null' => \&is_null, # for OAS30 null is not defined
    'string' => \&is_string,

    # it is for some buggy code
    '_ref' => \&is_ref
};

# such order is required
use constant TYPE_LIST => ['array', 'object', 'null', '_ref', 'integer', 'number', 'boolean', 'string'];

BEGIN {
    # YAML
    if (eval { require YAML::XS; YAML::XS->VERSION(0.67); 1; }) {
        *yaml_load = sub { local $YAML::XS::Boolean = 'JSON::PP'; YAML::XS::Load(@_) };
    }
    elsif (eval { require YAML::PP; 1; }) {
        my $pp = YAML::PP->new(boolean => 'JSON::PP');
        *yaml_load = sub { $pp->load_string(@_) };
    } else {
        *yaml_load = sub { croak 'No YAML package installed' };
    }

    # JSON
    my $json_class;
    if (eval { require Cpanel::JSON::XS; 1; }) {
        $json_class = 'Cpanel::JSON::XS';
    } elsif (eval { require JSON::XS; JSON::XS->VERSION(3.0); 1; }) {
        $json_class = 'JSON::XS';
    } else {
        require JSON::PP;
        $json_class = 'JSON::PP';
    }
    my $json = $json_class->new->canonical(1)->utf8;
    *json_encode = sub { $json->encode(@_); };
    *json_decode = sub { $json->decode(@_); };
}

sub unbool {
    my $x = shift;
    return "$x" if ref $x eq 'JSON::PP::Boolean';
    return $x if ref $x;
    return '1' if $x && $x eq '1';
    return '0' if !defined $x || $x eq '0' || $x eq '';
    return $x;
}

sub serialize { json_encode(shift) }

sub round {
    my $value = shift;
    return int($value + ($value >= 0 ? 0.5 : -0.5));
}

sub load_schema {
    my ($resource, $scheme_handlers) = @_;

    my ($content_ref, $content_type) = eval { get_content($resource, $scheme_handlers) };

    if ($@) {
        croak(sprintf('Failed to load resource %s: %s', $resource, $@));
    }

    my $schema = eval { decode_content($content_ref, $content_type) };

    if ($@) {
        croak(sprintf('Failed to load resource %s as %s: %s', $resource, $content_type, $@)) if $content_type;
        croak(sprintf('Unsupported type of resource %s', $resource));
    }

    return $schema;
}

sub get_content {
    my ($resource, $scheme_handlers) = @_;

    my $uri = blessed($resource) && $resource->isa('URI') ? $resource : URI->new($resource);

    if ($uri->has_recognized_scheme) {
        if (my $scheme = $uri->scheme) {
            $scheme_handlers //= {};
            if (exists $scheme_handlers->{$scheme}) {
                return $scheme_handlers->{$scheme}->($uri);
            }
            elsif ($scheme eq 'http' || $scheme eq 'https') {
                return fetch_file($uri->canonical->as_string);
            }
            elsif ($scheme eq 'file') {
                return read_file($uri->file);
            }
            croak(sprintf('Unsupported scheme "%s" of URI %s', $scheme // '', $uri->as_string));
        }
    }

    # May it is path of local file without scheme?
    return read_file("$resource");
}

sub decode_content {
    my ($content_ref, $content_type) = @_;

    if ($content_type) {
        return yaml_load($$content_ref) if $content_type eq CONTENT_TYPE_YAML;
        return json_decode($$content_ref) if $content_type eq CONTENT_TYPE_JSON;
    }

    my $schema;

    # Try to guess.
    $schema = eval { json_decode($$content_ref) };
    $schema = yaml_load($$content_ref) if $@;

    return $schema;
}

sub detect_content_type_from_path {
    my ($path) = @_;

    my (undef, undef, $suffix) = File::Basename::fileparse($path, qr/\.[^.]+/);

    $suffix = lc($suffix);

    return CONTENT_TYPE_JSON if $suffix eq '.json';
    return CONTENT_TYPE_YAML if $suffix eq '.yaml';
    return CONTENT_TYPE_YAML if $suffix eq '.yml';
    return;
}

sub detect_content_type_from_content {
    my ($content_ref) = @_;

    return unless defined $content_ref && defined $$content_ref;

    return CONTENT_TYPE_JSON if $$content_ref =~ /^\s+[\{\[]/;
    return CONTENT_TYPE_YAML if $$content_ref =~ /^---[\n\r ]/;
    return CONTENT_TYPE_YAML if $$content_ref =~ /^%YAML [0-9]\.[0-9]+\b/;
    return;
}

sub fetch_file {
    my ($uri) = @_;

    my $file = File::Fetch->new(uri => $uri) or croak(File::Fetch->error);

    # Try to patch File::Fetch < 0.50 to support HTTPS scheme.
    if ($file->scheme eq 'https' && !exists $File::Fetch::METHODS->{https}) {
        require version;
        if (version->parse(File::Fetch->VERSION) < version->parse('0.50')) {
            $File::Fetch::METHODS->{https} = [
                eval { require LWP::Protocol::https } ? 'lwp' : (),
                qw( wget curl ),
            ];
        }
    }

    $file->fetch(to => \my $content) or croak($file->error // "Can't fetch file from $uri");

    my $content_type = detect_content_type_from_path($file->output_file)
                    || detect_content_type_from_content(\$content);

    return (\$content, $content_type);
}

sub read_file {
    my ($path) = @_;

    croak "File $path does not exists" unless -e $path;
    croak "File $path does not have read permission" unless -r _;

    my $size = -s _;

    open(my $fh, '<', $path) or croak "Open file $path error: $!";
    read($fh, (my $content), $size);
    close($fh);

    my $content_type = detect_content_type_from_path($path)
                    || detect_content_type_from_content(\$content);

    return (\$content, $content_type);
}

# params: $value, $type, $is_strict
sub is_type {
    return 0 unless exists TYPE_MAP->{$_[1]};
    return TYPE_MAP->{$_[1]}->($_[0], $_[2]);
}

# params: $value, $is_strict
sub detect_type {
    for my $type (@{TYPE_LIST()}) {
        return $type if TYPE_MAP->{$type}->(@_);
    }
    # it must be unreachable code
    croak 'Unknown type detected';
}

# params: $value, $is_strict
sub is_array {
    return ref $_[0] eq 'ARRAY';
}

# params: $value, $is_strict
sub is_bool {
    my $type = ref $_[0];
    return 1 if $type eq 'JSON::PP::Boolean' or
                $type eq 'JSON::XS::Boolean' or
                $type eq 'Cpanel::JSON::XS::Boolean';
    return 0 if $_[1]; # is strict
    my $is_number = looks_like_number($_[0]) && ($_[0] == 1 || $_[0] == 0);
    my $is_string = defined $_[0] && $_[0] eq '';
    my $is_undef = !defined $_[0];
    return 1 if $is_number || $is_string || $is_undef;
    return 0;
}

# params: $value, $is_strict
sub is_integer {
    return 1 if B::svref_2object(\$_[0])->FLAGS & B::SVf_IOK();
    return 0 if $_[1]; # is strict
    return 0 if ref $_[0];
    return 1 if looks_like_number($_[0]) && int($_[0]) == $_[0];
    return 0;
}

# params: $value, $is_strict
sub is_number {
    return 1 if B::svref_2object(\$_[0])->FLAGS & (B::SVf_IOK() | B::SVf_NOK());
    return 0 if $_[1]; # is strict
    return 0 if ref $_[0];
    return 1 if looks_like_number($_[0]);
    return 0;
}

# params: $value, $is_strict
sub is_ref {
    my $ref = ref $_[0];
    return 0 unless $ref;
    return 0 if $ref eq 'JSON::PP::Boolean' ||
                $ref eq 'HASH' ||
                $ref eq 'ARRAY';
    return 1;
}

# params: $value, $is_strict
sub is_object {
    return ref $_[0] eq 'HASH';
}

# params: $value, $is_strict
sub is_null {
    return !(defined $_[0]);
}

# params: $value, $is_strict
sub is_string {
    return !(ref $_[0]) && !is_number(@_) && defined $_[0] if $_[1]; # is strict
    return !(ref $_[0]) && defined $_[0];
}

sub data_section {
    my $class = shift;
    my $handle = do { no strict 'refs'; \*{"${class}::DATA"} };
    return unless fileno $handle;
    seek $handle, 0, 0;
    local $/ = undef;
    my $data = <$handle>;
    $data =~ s/^.*\n__DATA__\r?\n//s;
    $data =~ s/\r?\n__END__\r?\n.*$//s;
    return $data;
}

1;
