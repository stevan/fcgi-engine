package FCGI::Engine::Manager::Server;
use Moose;
use MooseX::Types::Path::Class;

has 'name' => (
    is      => 'ro', 
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        ((shift)->scriptname . '.server')
    }
);

has [qw[
        scriptname
        pidfile
        socket
    ]] => (
        is       => 'ro',
        isa      => 'Path::Class::File',
        coerce   => 1,
        required => 1,
);

has 'nproc' => (
    is       => 'ro',
    isa      => 'Int',
    default  => sub { 1 }
);

1;

__END__

=pod

=head1 NAME

FCGI::Engine::Manager::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

