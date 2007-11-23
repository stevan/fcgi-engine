package FCGI::Engine::ProcManager;
use Moose;
use Moose::Util::TypeConstraints;
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

our $SIG_CODEREF;
        
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
    metaclass => 'Collection::Hash',
    is        => 'rw',
    isa       => 'HashRef',
    clearer   => 'forget_all_pids',     
    default   => sub { +{} },  
    provides  => {
        'set'    => 'add_pid',
        'keys'   => 'get_all_pids',
        'delete' => 'remove_pid',
        'empty'  => 'has_pids',
        'count'  => 'pid_count',
    }
);

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


sub manage {
    my ($self,%values) = @_;
    foreach my $key (keys %values) {
        $self->$key($values{$key});
    }

    # skip to handling now if we won't be managing any processes.
    $self->n_processes() or return;

    # call the (possibly overloaded) management initialization hook.
    $self->role("manager");
    $self->manager_init();
    $self->notify("initialized");

    my $manager_pid = $$;

    MANAGING_LOOP: while (1) {
        
        # if the calling process goes away, perform cleanup.
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

    HANDLING:

    # forget any children we had been collecting.
    $self->forget_all_pids;

    # call the (possibly overloaded) handling init hook
    $self->role("server");
    $self->handling_init();
    $self->notify("initialized");

    # server returns 
    return 1;
}

sub manager_init {
    my ($self) = @_;
    
    # begin to handle signals.
    # We do NOT want SA_RESTART in the process manager.
    # -- we want start the shutdown sequence immediately upon SIGTERM.
    unless ($self->no_signals()) {
        POSIX::sigaction(POSIX::SIGTERM, $self->sigaction_no_sa_restart) 
            or $self->warn("sigaction: SIGTERM: $!");
        POSIX::sigaction(POSIX::SIGHUP,  $self->sigaction_no_sa_restart) 
            or $self->warn("sigaction: SIGHUP: $!");
        $SIG_CODEREF = sub { $self->sig_manager(@_) };
    }
    
    # change the name of this process as it appears in ps(1) output.
    $self->change_process_name("perl-fcgi-pm");
    
    $self->write_pid_file();
}

sub die : method {
    my ($self, $msg, $n) = @_;
    
    # stop handling signals.
    undef $SIG_CODEREF;
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
    $self->exit("dying: ".$msg,$n);
}

sub wait : method {
    my ($self) = @_;
    
    # wait for the next server to die.
    next if (my $pid = CORE::wait()) < 0;
    
    # notify when one of our servers have died.
    $self->remove_pid($pid) 
        and $self->notify("server (pid $pid) exited with status $?");
    
    return $pid;
}

sub write_pid_file {
    my ($self,$fname) = @_;
    $fname ||= $self->pid_fname() or return;
    if (!open PIDFILE, ">", "$fname") {
        $self->warn("open: $fname: $!");
        return;
    }
    print PIDFILE "$$\n";
    close PIDFILE;
}

sub remove_pid_file {
    my ($self,$fname) = @_;
    $fname ||= $self->pid_fname() or return;
    my $ret = unlink($fname) or $self->warn("unlink: $fname: $!");
    return $ret;
}

sub sig_sub {
    $SIG_CODEREF->(@_) if ref $SIG_CODEREF;
}


sub sig_manager {
    my ($self,$name) = @_;
    if ($name eq "TERM") {
        $self->notify("received signal $name");
        $self->die("safe exit from signal $name");
    } 
    elsif ($name eq "HUP") {
        # send a TERM to each of the servers, and pretend like nothing happened..
        if (my @pids = $self->get_all_pids) {
            $self->notify("sending TERM to PIDs, @pids");
            kill TERM => @pids;
        }
    } 
    else {
        $self->notify("ignoring signal $name");
    }
}

sub handling_init {
    my ($self) = @_;
    
    # begin to handle signals.
    # We'll want accept(2) to return -1(EINTR) on caught signal..
    unless ($self->no_signals()) {
        POSIX::sigaction(POSIX::SIGTERM, $self->{sigaction_no_sa_restart}) 
            or $self->warn("sigaction: SIGTERM: $!");
        POSIX::sigaction(POSIX::SIGHUP,  $self->{sigaction_no_sa_restart}) 
            or $self->warn("sigaction: SIGHUP: $!");
        $SIG_CODEREF = sub { $self->sig_handler(@_) };
    }
    
    # change the name of this process as it appears in ps(1) output.
    $self->change_process_name("perl-fcgi");
}


sub pre_dispatch {
    my ($self) = @_;
    
    # Now, we want the request to continue unhindered..
    unless ($self->no_signals()) {
        POSIX::sigaction(POSIX::SIGTERM, $self->sigaction_sa_restart) 
            or $self->warn("sigaction: SIGTERM: $!");
        POSIX::sigaction(POSIX::SIGHUP,  $self->sigaction_sa_restart) 
            or $self->warn("sigaction: SIGHUP: $!");
    }
}

sub post_dispatch {
    my ($self) = @_;
    if ($self->received_signal("TERM")) {
        $self->exit("safe exit after SIGTERM");
    }
    if ($self->received_signal("HUP")) {
        $self->exit("safe exit after SIGHUP");
    }
    if ($self->manager_pid and getppid() != $self->manager_pid) {
        $self->exit("safe exit: manager has died");
    }
    # We'll want accept(2) to return -1(EINTR) on caught signal..
    unless ($self->no_signals()) {
        POSIX::sigaction(POSIX::SIGTERM, $self->sigaction_no_sa_restart) 
            or $self->warn("sigaction: SIGTERM: $!");
        POSIX::sigaction(POSIX::SIGHUP,  $self->sigaction_no_sa_restart) 
            or $self->warn("sigaction: SIGHUP: $!");
    }
}


sub sig_handler {
    my ($self, $name) = @_;
    $self->received_signal($name, 1);
}

sub change_process_name {
    my ($self, $name) = @_;
    $0 = $name;
}

sub received_signal {
    my ($self,$sig,$received) = @_;
    $sig or return $self->signals_received;
    $received and $self->signals_received->{$sig}++;
    return $self->signals_received->{$sig};
}

sub warn : method {
    my ($self,$msg) = @_;
    $self->notify($msg);
}

sub notify {
    my ($self,$msg) = @_;
    $msg =~ s/\s*$/\n/;
    print STDERR "FastCGI: ".$self->role()." (pid $$): ".$msg;
}


sub exit : method {
    my ($self,$msg,$n) = @_;
    $n ||= 0;
    
    # if we still have children at this point, something went wrong.
    # SIGKILL them now.
    kill KILL => $self->get_all_pids 
        if $self->has_pids;
    
    $self->warn($msg);
    $@ = $msg;
    CORE::exit $n;
}

sub abort {
    my ($self,$msg,$n) = @_;
    $n ||= 1;
    $self->exit($msg,1);
}

1;

__END__

=pod


=head1 NAME

 FCGI::Engine::ProcManager - functions for managing FastCGI applications.

=head1 SYNOPSIS

{
 # In Object-oriented style.
 use CGI::Fast;
 use FCGI::Engine::ProcManager;
 my $proc_manager = FCGI::Engine::ProcManager->new({
	n_processes => 10 
 });
 $proc_manager->manage();
 while (my $cgi = CGI::Fast->new()) {
   $proc_manager->pre_dispatch();
   # ... handle the request here ...
   $proc_manager->post_dispatch();
 }

 # This style is also supported:
 use CGI::Fast;
 use FCGI::Engine::ProcManager qw(manage pre_dispatch 
			  post_dispatch);
 manage( n_processes => 10 );
 while (my $cgi = CGI::Fast->new()) {
   pre_dispatch();
   #...
   post_dispatch();
 }

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
 C<handling_init> - called just before a server is returns from C<manage>

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

=head2 new

 class or instance
 (ProcManager) new([hash parameters])

Constructs a new process manager.  Takes an option has of initial parameter
values, and assigns these to the constructed object HASH, overriding any
default values.  The default parameter values currently are:

 role         => manager
 start_delay  => 0
 die_timeout  => 60

=head1 Manager methods

=head2 manage

 instance or export
 (int) manage([hash parameters])

DESCRIPTION:

When this is called by a FastCGI script to manage application servers.  It
defines a sequence of instructions for a process to enter this method and
begin forking off and managing those handlers, and it defines a sequence of
instructions to intialize those handlers.

If n_processes < 1, the managing section is subverted, and only the
handling sequence is executed.

Either returns the return value of die() and/or abort() (which will
not ever return in general), or returns 1 to the calling script to begin
handling requests.

=head2 manager_init

 instance
 () manager_init()

DESCRIPTION:

Overrideable method which initializes a process manager.  In order to
handle signals, manage the PID file, and change the process name properly,
any method which overrides this should call SUPER::manager_init().

=head2 die

 instance or export
 () die(string msg[, int exit_status])

DESCRIPTION:

This method is called when a process manager receives a notification to
shut itself down.  die() attempts to shutdown the process manager
gently, sending a SIGTERM to each managed process, waiting die_timeout()
seconds to reap each process, and then exit gracefully once all children
are reaped, or to abort if all children are not reaped.

=head2 wait

 instance or export
 (int pid) wait()

DESCRIPTION:

This calls wait() which suspends execution until a child has exited.
If the process ID returned by wait corresponds to a managed process,
notify() is called with the exit status of that process.
wait() returns with the return value of wait().

=head2 write_pid_file

 instance or export
 () write_pid_file([string filename])

DESCRIPTION:

Writes current process ID to optionally specified file.  If no filename is
specified, it uses the value of the C<pid_fname> parameter.

=head2 remove_pid_file

 instance or export
 () remove_pid_file()

DESCRIPTION:

Removes optionally specified file.  If no filename is specified, it uses
the value of the C<pid_fname> parameter.

=head2 sig_sub

 instance
 () sig_sub(string name)

DESCRIPTION:

The name of this method is passed to POSIX::sigaction(), and handles signals
for the process manager.  If $SIG_CODEREF is set, then the input arguments
to this are passed to a call to that.

=head2 sig_manager

 instance
 () sig_manager(string name)

DESCRIPTION:

Handles signals of the process manager.  Takes as input the name of signal
being handled.

=head1 Handler methods

=head2 handling_init

 instance or export
 () handling_init()

DESCRIPTION:

=head2 pre_dispatch

 instance or export
 () pre_dispatch()

DESCRIPTION:

=head2 post_dispatch

 instance or export
 () post_dispatch()

DESCRIPTION:

=head2 sig_handler

 instance or export
 () sig_handler()

DESCRIPTION:

=head1 Common methods and routines

=head2 self_or_default

 private global
 (ProcManager, @args) self_or_default([ ProcManager, ] @args);

DESCRIPTION:

This is a helper subroutine to acquire or otherwise create a singleton
default object if one is not passed in, e.g., a method call.

=head2 change_process_name

 instance or export
 () change_process_name()

DESCRIPTION:

=head2 received_signal

 instance or export
 () pm_received signal()

DESCRIPTION:

=head1 parameters

=head2 pm_parameter

 instance or export
 () pm_parameter()

DESCRIPTION:

=head2 n_processes

=head2 no_signals

=head2 pid_fname

=head2 die_timeout

=head2 role

=head2 start_delay

DESCRIPTION:

=head1 notification and death

=head2 warn

 instance or export
 () warn()

DESCRIPTION:

=head2 notify

 instance or export
 () notify()

DESCRIPTION:

=head2 exit

 instance or export
 () exit(string msg[, int exit_status])

DESCRIPTION:

=head2 abort

 instance or export
 () abort(string msg[, int exit_status])

DESCRIPTION:

=head1 BUGS

No known bugs, but this does not mean no bugs exist.

=head1 SEE ALSO

L<FCGI>.

=head1 COPYRIGHT

=cut