
package FCGI::Engine;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;

use POSIX ();
use FCGI::ProcManager;
use FCGI;
use CGI;
use File::Pid;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

with 'MooseX::Getopt';

has 'listen' => (
    metaclass   => 'Getopt',
    is          => 'ro',
    isa         => 'Path::Class::File',
    coerce      => 1,
    cmd_aliases => [qw[ listen l ]],
    predicate   => 'is_listening',
);

has 'nproc' => (
    metaclass   => 'Getopt',
    is          => 'ro',
    isa         => 'Int',
    default     => sub { 1 },
    cmd_aliases => [qw[ nproc n ]],
);

has 'pidfile' => (
    metaclass   => 'Getopt',
    is          => 'ro',
    isa         => 'Path::Class::File',
    coerce      => 1,
    cmd_aliases => [qw[ pidfile p ]],
    predicate   => 'has_pidfile',
);

has 'detach' => (
    metaclass   => 'Getopt',
    is          => 'ro',
    isa         => 'Bool',
    cmd_aliases => [qw[ daemon d ]],
    predicate   => 'should_detach',
);

subtype 'FCGI::ProcManager'
    => as 'Str'
    => where { $_->isa('FCGI::ProcManager') };

has 'manager' => (
    metaclass   => 'Getopt',
    is          => 'ro',
    isa         => 'FCGI::ProcManager',
    default     => sub { 'FCGI::ProcManager' },
    cmd_aliases => [qw[ manager M ]],
);

# options to specify in your script

has '_handler_class' => (
    reader   => 'handler_class',
    init_arg => 'handler_class',
    isa      => 'Str',
    required => 1,
);

has '_handler_method' => (
    reader   => 'handler_method',
    init_arg => 'handler_method',
    isa      => 'Str',
    default  => sub { 'handler' },
);

has '_pre_fork_init' => (
    reader    => 'pre_fork_init',
    init_arg  => 'pre_fork_init',
    isa       => 'CodeRef',
    predicate => 'has_pre_fork_init',
);

has '_pid_obj' => (
    reader    => 'pid_obj',
    isa       => 'File::Pid',
    lazy      => 1,
    default   => sub {
        my $self = shift;
        ($self->has_pidfile)
            || confess "There is no pidfile specified, so why are you asking for a pid object??";
        (-f $self->pidfile)
            || confess "The pidfile does not exist yet, you must call ->run first";
        File::Pid->new({ file => $self->pidfile })
    }
);

## methods ...

sub BUILD {
    my $self = shift;

    ($self->has_pidfile)
        || confess "You must specify a pidfile if you are listening"
            if $self->is_listening;
}

sub run {
    my $self = shift;

    $self->pre_fork_init->() if $self->has_pre_fork_init;

    my $handler_class = $self->handler_class;
    Class::MOP::load_class($handler_class);

    ($self->handler_class->can($self->handler_method))
        || confess "The handler class ("
                 . $self->handler_class
                 . ") does not support the handler method ("
                 . $self->handler_method
                 . ")";

    my $socket = 0;

    if ($self->is_listening) {
        my $old_umask = umask;
        umask(0);
        $socket = FCGI::OpenSocket($self->listen, 100);
        umask($old_umask);
    }

    my $request = FCGI::Request(
        \*STDIN,
        \*STDOUT,
        \*STDERR,
        \%ENV,
        $socket,
        &FCGI::FAIL_ACCEPT_ON_INTR
    );

    my $proc_manager;

    if ($self->is_listening) {

        $self->daemon_fork() if $self->detach;

        # make sure any subclasses are loaded ...
        Class::MOP::load_class($self->manager);

        $proc_manager = $self->manager->new({
            n_processes => $self->nproc,
            pid_fname   => $self->pidfile,
        });

        $self->daemon_detach() if $self->detach;

        $proc_manager->pm_manage();
    }

    while($request->Accept() >= 0) {
        $proc_manager && $proc_manager->pm_pre_dispatch();

        # Cargo-culted from Catalyst::Engine::FastCGI ...
        if ( $ENV{SERVER_SOFTWARE} && $ENV{SERVER_SOFTWARE} =~ /lighttpd/ ) {
            $ENV{PATH_INFO} ||= delete $ENV{SCRIPT_NAME};
        }

        CGI::_reset_globals();
        $handler_class->handler(CGI->new);

        $proc_manager && $proc_manager->pm_post_dispatch();
    }
}

sub daemon_fork {
    fork && exit;
}

sub daemon_detach {
    my $self = shift;
    open STDIN,  "+</dev/null" or die $!;
    open STDOUT, ">&STDIN"     or die $!;
    open STDERR, ">&STDIN"     or die $!;
    POSIX::setsid();
}

1;

__END__

=pod

=head1 NAME

FCGI::Engine

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




