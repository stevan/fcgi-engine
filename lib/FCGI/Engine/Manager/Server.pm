package FCGI::Engine::Manager::Server;
use Moose;
use MooseX::Types::Path::Class;

use File::Pid;

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

has $_ => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
) for qw[
    scriptname
    pidfile
    socket
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
    isa       => 'File::Pid',
    lazy      => 1,
    default   => sub {
        my $self = shift;
        (-f $self->pidfile)
            || confess "The pidfile does not exist yet, you cannot create pid object";
        File::Pid->new({ file => $self->pidfile })
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




