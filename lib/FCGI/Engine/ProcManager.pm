package FCGI::Engine::ProcManager;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Params::Validate;
use MooseX::AttributeHelpers;
use MooseX::Types::Path::Class;

use constant DEBUG => 1;

use POSIX qw(SA_RESTART SIGTERM SIGHUP);

our $VERSION   = '0.01'; 
our $AUTHORITY = 'cpan:STEVAN';

enum 'FCGI::Engine::ProcManager::Role' => qw[manager server];

has 'role' => (
    is      => 'rw',
    isa     => 'FCGI::Engine::ProcManager::Role',
    default => sub { 'manager' }
);
  
has 'start_delay' => (
    is      => 'rw',
    isa     => 'Int',
    default => sub { 0 }    
);

has 'die_timeout' => (
    is      => 'rw',
    isa     => 'Int',
    default => sub { 60 }    
);  
  
has 'n_processes' => (
    is       => 'rw',
    isa      => 'Int',
    default  => sub { 0 }
); 

has 'pid_fname' => (
    is       => 'rw',
    isa      => 'Path::Class::File',
    coerce   => 1,
);
        
has 'no_signals' => (
    is      => 'rw',
    isa     => 'Bool',
    default => sub { 0 }
);

has 'sigaction_no_sa_restart' => (is => 'rw', isa => 'POSIX::SigAction');
has 'sigaction_sa_restart'    => (is => 'rw', isa => 'POSIX::SigAction');

has 'signals_received' => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { +{} }
);

has 'manager_pid' => (
    is  => 'rw',
    isa => 'Int',
);

has 'server_pids' => (
    metaclass => 'Collection::Bag',
    is        => 'rw',
    clearer   => 'forget_all_pids',      
    provides  => {
        'add'    => 'add_pid',
        'keys'   => 'get_all_pids',
        'delete' => 'remove_pid',
        'empty'  => 'has_pids',
        'count'  => 'pid_count',
    }
);

## methods ...

sub BUILD {
    my $self = shift;
    unless ($self->no_signals()) {
        $self->sigaction_no_sa_restart(
            POSIX::SigAction->new(
                'FCGI::Engine::ProcManager::sig_sub'
            )
        );
        $self->sigaction_sa_restart(
            POSIX::SigAction->new(
                'FCGI::Engine::ProcManager::sig_sub',
                undef,
                POSIX::SA_RESTART
            )
        );
    }
}

# this is the signal handler ...
{
    my $SIG_CODEREF;

    sub sig_sub { $SIG_CODEREF->(@_) if ref $SIG_CODEREF }
    
    sub clear_signal_handler { undef $SIG_CODEREF }

    sub setup_signal_handler {
        my $self = shift;
        $SIG_CODEREF = $self->role eq 'manager'
            ? sub { $self->manager_sig_handler(@_) } 
            : sub { $self->server_sig_handler(@_)  };    
    }
}

## main loop ...

sub manage {
    my $self = shift;

    # skip to handling now if we won't be managing any processes.
    $self->n_processes() or return;

    # call the (possibly overloaded) management initialization hook.
    $self->role("manager");
    $self->manager_init();
    $self->notify("initialized");

    my $manager_pid = $$;

    MANAGING_LOOP: while (1) {
        
        # FIXME
        # we should tell the process that it is being 
        # run under some kind of daemon, which will mean 
        # that getppid will usually then return 1
        # - SL
        #getppid() == 1 and
        #  return $self->die("calling process has died");
        
        $self->n_processes() > 0 or
            return $self->die();
        
        # while we have fewer servers than we want.
        PIDS: while ($self->pid_count < $self->n_processes()) {
            
            if (my $pid = fork()) {
                # the manager remembers the server.
                $self->add_pid($pid);
                $self->notify("server (pid $pid) started");
            
             } 
             elsif (! defined $pid) {
                 return $self->abort("fork: $!");
            
             } 
             else {
                 $self->manager_pid($manager_pid);
                 # the server exits the managing loop.
                 last MANAGING_LOOP;
             }
            
             for (my $s = $self->start_delay(); $s; $s = sleep $s) {};
        }
        
        # this should block until the next server dies.
        $self->wait();
        
    }# while 1

    SERVER:

    # forget any children we had been collecting.
    $self->forget_all_pids;

    # call the (possibly overloaded) handling init hook
    $self->role("server");
    $self->server_init();
    $self->notify("initialized");

    # server returns 
    return 1;
}

## initializers ...

sub manager_init {
    my $self = shift;
    
    unless ($self->no_signals()) {
        $self->setup_signal_actions(should_restart => 0);
        $self->setup_signal_handler;
    }
    
    $self->change_process_name("perl-fcgi-pm");
    
    $self->write_pid_file();
    
    inner();
}

sub server_init {
    my $self = shift;
    
    unless ($self->no_signals()) {
        $self->setup_signal_actions(should_restart => 0);
        $self->setup_signal_handler;
    }
    
    $self->change_process_name("perl-fcgi");
    
    inner();
}


## hooks ...

sub pre_dispatch {
    my $self = shift;
    
    $self->setup_signal_actions(should_restart => 1)
        unless $self->no_signals();        
    
    inner();
}

sub post_dispatch {
    my $self = shift;
    
    $self->exit("safe exit after SIGTERM")
        if $self->received_signal("TERM");

    $self->exit("safe exit after SIGHUP")
        if $self->received_signal("HUP");

    if ($self->manager_pid and getppid() != $self->manager_pid) {
        $self->exit("safe exit: manager has died");
    }
    
    $self->setup_signal_actions(should_restart => 0)
        unless $self->no_signals();
    
    inner();
}

## utils ...

## pid file ...

sub write_pid_file {
    my $self  = shift;
    my $fname = $self->pid_fname || return;
    
    if (!open PIDFILE, ">", "$fname") {
        $self->notify("open: $fname: $!");
        return;
    }
    
    print PIDFILE "$$\n";
    close PIDFILE;
}

sub remove_pid_file {
    my $self  = shift;
    my $fname = $self->pid_fname || return;
    my $ret   = unlink($fname)   || $self->notify("unlink: $fname: $!");
    return $ret;
}

# sig-handlers

sub manager_sig_handler {
    my ($self, $name) = @_;
    if ($name eq "TERM") {
        $self->notify("received signal $name");
        $self->die("safe exit from signal $name");
    } 
    elsif ($name eq "HUP") {
        # send a TERM to each of the servers, 
        # and pretend like nothing happened..
        if (my @pids = $self->get_all_pids) {
            $self->notify("sending TERM to PIDs, @pids");
            kill TERM => @pids;
        }
    } 
    else {
        $self->notify("ignoring signal $name");
    }
}

sub server_sig_handler {
    my ($self, $name) = @_;
    $self->received_signal($name, 1);
}

sub received_signal {
    my ($self, $sig, $received) = @_;
    return $self->signals_received unless $sig;
    $self->signals_received->{$sig}++ if $received;
    return $self->signals_received->{$sig};
}

sub change_process_name {
    my ($self, $name) = @_;
    $0 = $name;
}

sub wait : method {
    my $self = shift;
    
    # wait for the next server to die.
    next if (my $pid = CORE::wait()) < 0;
    
    # notify when one of our servers have died.
    $self->remove_pid($pid) 
        and $self->notify("server (pid $pid) exited with status $?");
    
    return $pid;
}

## signal handling stuff ...

sub setup_signal_actions {
    my ($self, $should_restart) = validatep(\@_, 
        should_restart => { isa => 'Bool' }
    );

    my $sig_action = $should_restart 
        ? $self->sigaction_sa_restart
        : $self->sigaction_no_sa_restart;
        
    POSIX::sigaction(POSIX::SIGTERM, $sig_action) 
        || $self->notify("sigaction: SIGTERM: $!");
    POSIX::sigaction(POSIX::SIGHUP,  $sig_action) 
        || $self->notify("sigaction: SIGHUP: $!");
}

## notification ...

sub notify {
    my ($self, $msg) = @_;
    $msg =~ s/\s*$/\n/;
    print STDERR "FastCGI: " . $self->role() . " (pid $$): " . $msg;
}

## error/exit handlers ...

sub die : method {
    my ($self, $msg, $n) = @_;
    
    # stop handling signals.
    $self->clear_signal_handler;
    $SIG{HUP}  = 'DEFAULT';
    $SIG{TERM} = 'DEFAULT';
    
    $self->remove_pid_file();
    
    # prepare to die no matter what.
    if (defined $self->die_timeout()) {
        $SIG{ALRM} = sub { $self->abort("wait timeout") };
        alarm $self->die_timeout();
    }
    
    # send a TERM to each of the servers.
    if (my @pids = $self->get_all_pids) {
        $self->notify("sending TERM to PIDs, @pids");
        kill TERM => @pids;
    }
    
    # wait for the servers to die.
    while ($self->has_pids) {
        $self->wait();
    }
    
    # die already.
    $self->exit("dying: $msg", $n);
}

sub abort {
    my ($self, $msg, $n) = @_;
    $n ||= 1;
    $self->exit($msg, 1);
}

sub exit : method {
    my ($self, $msg, $n) = @_;
    $n ||= 0;
    
    # if we still have children at this point, 
    # something went wrong. SIGKILL them now.
    kill KILL => $self->get_all_pids 
        if $self->has_pids;
    
    $self->notify($msg);
    $@ = $msg;
    CORE::exit $n;
}

1;

__END__

=pod


=head1 NAME

 FCGI::Engine::ProcManager - module for managing FastCGI applications.

=head1 SYNOPSIS

=head1 DESCRIPTION

FCGI::Engine::ProcManager is used to serve as a FastCGI process manager.  By
re-implementing it in perl, developers can more finely tune performance in
their web applications, and can take advantage of copy-on-write semantics
prevalent in UNIX kernel process management.  The process manager should
be invoked before the caller''s request loop

The primary routine, C<manage>, enters a loop in which it maintains a
number of FastCGI servers (via fork(2)), and which reaps those servers
when they die (via wait(2)).

C<manage> provides too hooks:

 C<manager_init> - called just before the manager enters the manager loop.
 C<server_init> - called just before a server is returns from C<manage>

It is necessary for the caller, when implementing its request loop, to
insert a call to C<pre_dispatch> at the top of the loop, and then
7C<post_dispatch> at the end of the loop.

=head2 Signal Handling

FCGI::Engine::ProcManager attempts to do the right thing for proper shutdowns now.

When it receives a SIGHUP, it sends a SIGTERM to each of its children, and
then resumes its normal operations.   

When it receives a SIGTERM, it sends a SIGTERM to each of its children, sets
an alarm(3) "die timeout" handler, and waits for each of its children to
die.  If all children die before this timeout, process manager exits with
return status 0.  If all children do not die by the time the "die timeout"
occurs, the process manager sends a SIGKILL to each of the remaining
children, and exists with return status 1.

In order to get FastCGI servers to exit upon receiving a signal, it is
necessary to use its FAIL_ACCEPT_ON_INTR.  See FCGI.pm's description of
FAIL_ACCEPT_ON_INTR.  Unfortunately, if you want/need to use CGI::Fast, it
appears currently necessary to modify your installation of FCGI.pm, with
something like the following:

 -*- patch -*-
 --- FCGI.pm     2001/03/09 01:44:00     1.1.1.3
 +++ FCGI.pm     2001/03/09 01:47:32     1.2
 @@ -24,7 +24,7 @@
  *FAIL_ACCEPT_ON_INTR = sub() { 1 };
  
  sub Request(;***$$$) {
 -    my @defaults = (\*STDIN, \*STDOUT, \*STDERR, \%ENV, 0, 0);
 +    my @defaults = (\*STDIN, \*STDOUT, \*STDERR, \%ENV, 0, FAIL_ACCEPT_ON_INTR());
      splice @defaults,0,@_,@_;
      RequestX(@defaults);
  }   
 -*- end patch -*-

Otherwise, if you don't, there is a loop around accept(2) which prevents
os_unix.c OS_Accept() from returning the necessary error when FastCGI
servers blocking on accept(2) receive the SIGTERM or SIGHUP.

FCGI::Engine::ProcManager uses POSIX::sigaction() to override the default SA_RESTART
policy used for perl's %SIG behavior.  Specifically, the process manager
never uses SA_RESTART, while the child FastCGI servers turn off SA_RESTART
around the accept(2) loop, but re-enstate it otherwise.

The desired (and implemented) effect is to give a request as big a chance as
possible to succeed and to delay their exits until after their request,
while allowing the FastCGI servers waiting for new requests to die right
away. 

=head1 METHODS

=head SEE ALSO

=over 4

=item L<FCGI::ProcManager>

This module is a fork of the FCGI::ProcManager code, with lots of 
code cleanup as well as general Moosificaition.

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
