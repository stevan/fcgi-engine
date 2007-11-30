package FCGI::Engine::Manager::Server;
use Moose;

use MooseX::Daemonize::PidFile;
use FCGI::Engine::Types;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

has 'name' => (
    is      => 'ro', 
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        ((shift)->scriptname . '.server')
    }
);

has 'socket' => (
    is       => 'ro',
    isa      => 'FCGI::Engine::Listener',
    coerce   => 1,
    required => 1,
);

has $_ => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
) for qw[
    scriptname
    pidfile
];

has 'nproc' => (
    is       => 'ro',
    isa      => 'Int',
    default  => sub { 1 }
);

has 'additional_args' => (
    is         => 'ro',
    isa        => 'ArrayRef',
    auto_deref => 1,
    predicate  => 'has_additional_args'
);

## ... internal attributes

has 'pid_obj' => (
    is        => 'ro',
    isa       => 'MooseX::Daemonize::PidFile',
    lazy      => 1,
    default   => sub {
        MooseX::Daemonize::PidFile->new(file => (shift)->pidfile)
    }
);

## methods ...

sub construct_command_line {
    my $self = shift;
    return ("perl",
         ($self->has_additional_args
             ? $self->additional_args
             : ()),
         $self->scriptname, 
         "--nproc",
         $self->nproc,
         "--pidfile",
         $self->pidfile, 
         "--listen",
         $self->socket, 
         "--daemon");
}

# NOTE: 
# perhaps the server status information 
# should also go in here, so that we can 
# keep it all in one place.
# - SL

1;

__END__

=pod

=head1 NAME

FCGI::Engine::Manager::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006, 2007 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut




