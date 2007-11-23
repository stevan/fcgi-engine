
package FCGI::Engine;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Path::Class;

use POSIX ();
use FCGI;
use CGI;
use File::Pid;

use FCGI::Engine::ProcManager;

use constant DEBUG => 1;

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

has 'manager' => (
    metaclass   => 'Getopt',
    is          => 'ro',
    isa         => 'Str',
    default     => sub { 'FCGI::Engine::ProcManager' },
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
        
        $proc_manager->manage();   
    }

    while($request->Accept() >= 0) {
        $proc_manager && $proc_manager->pre_dispatch();

        # Cargo-culted from Catalyst::Engine::FastCGI ...
        if ( $ENV{SERVER_SOFTWARE} && $ENV{SERVER_SOFTWARE} =~ /lighttpd/ ) {
            $ENV{PATH_INFO} ||= delete $ENV{SCRIPT_NAME};
        }

        CGI::_reset_globals();
        $handler_class->handler(CGI->new);

        $proc_manager && $proc_manager->post_dispatch();
    }
}

sub daemon_fork {
    fork && exit;
}

sub daemon_detach {
    my $self = shift;
    open STDIN,  "+</dev/null" or die $!;
    if (DEBUG) {
        open STDOUT, ">", "OUT.txt" or die $!;
        open STDERR, ">", "ERR.txt" or die $!;
    }
    else {
        open STDOUT, ">&STDIN" or die $!;
        open STDERR, ">&STDIN" or die $!;        
    }
    POSIX::setsid();
}

1;

__END__

=pod

=head1 NAME

FCGI::Engine - A flexible engine for running FCGI-based applications

=head1 SYNOPSIS

  # in scripts/my_web_app_fcgi.pl
  use strict;
  use warnings;
  
  use FCGI::Engine;
  
  FCGI::Engine->new_with_options(
      handler_class  => 'My::Web::Application',
      handler_method => 'run',
      pre_fork_init  => sub {
          require('my_web_app_startup.pl');
      }
  )->run;

  # run as normal FCGI script
  perl scripts/my_web_app_fcgi.pl

  # run as standalone FCGI server
  perl scripts/my_web_app_fcgi.pl --nproc 10 --pidfile /tmp/my_app.pid \
                                  --listen /tmp/my_app.socket --daemon

=head1 DESCRIPTION

This module helps manage FCGI based web applications by providing a 
wrapper which handles most of the low-level FCGI details for you. It
can run FCGI programs as simple scripts or as full standalone 
socket based servers who are managed by L<FCGI::ProcManager>.

The code is largely based (*cough* stolen *cough*) on the 
L<Catalyst::Engine::FastCGI> module, and provides a  command line 
interface which is compatible with that module. But of course it 
does not require L<Catalyst> or anything L<Catalyst> related. So 
you can use this module with your L<CGI::Application>-based web 
application or any other L<Random::Web::Framework>-based web app.

=head1 CAVEAT

This module is *NIX B<only>, it definitely does not work on Windows
and I have no intention of making it do so. Sorry.

=head1 PARAMETERS

=head2 Command Line

This module uses L<MooseX::Getopt> for command line parameter
handling and validation.

All parameters are currently optional, but some parameters
depend on one another.

=over 4

=item I<--listen -l>

This should be a file path where the unix domain socket file
should live. If this parameter is specified, then you B<must> 
also specify a location for the pidfile.

=item I<--nproc -n>

This should be an integer specifying the number of FCGI processes
that L<FCGI::ProcManager> should start up. The default is 1.

=item I<--pidfile -p>

This should be a file path where your pidfile should live. This 
parameter is only used if the I<listen> parameter is specified.

=item I<--daemon -d>

This is a boolean parameter and has no argument, it is either 
used or not. It determines if the script should daemonize itself.
This parameter only used if the I<listen> parameter is specified.

=item I<--manager -m>

This allows you to pass the name of a L<FCGI::ProcManager> subclass 
to use. The default is to use L<FCGI::ProcManager>, and any value
passed to this parameter B<must> be a subclass of L<FCGI::ProcManager>.

=back

=head2 Constructor

In addition to the command line parameters, there are a couple 
parameters that the constuctor expects. 

=over 4

=item I<handler_class>

This is expected to be a class name, which will be used inside 
the request loop to dispatch your web application.

=item I<handler_method>

This is the class method to be called on the I<handler_class>
to server as a dispatch entry point to your web application. It
will default to C<handler>.

=item I<pre_fork_init>

This is an optional CODE reference which will be executed prior
to the request loop, and in a multi-proc context, prior to any 
forking (so as to take advantage of OS COW features).

=back

=head1 METHODS

=head2 Command Line Related

=over 4

=item B<listen>

Returns the value passed on the command line with I<--listen>.
This will return a L<Path::Class::File> object.

=item B<is_listening>

A predicate used to determine if the I<--listen> parameter was 
specified.

=item B<nproc>

Returns the value passed on the command line with I<--nproc>.

=item B<pidfile>

Returns the value passed on the command line with I<--pidfile>.
This will return a L<Path::Class::File> object.

=item B<has_pidfile>

A predicate used to determine if the I<--pidfile> parameter was 
specified.

=item B<detach>

Returns the value passed on the command line with I<--daemon>.

=item B<should_detach>

A predicate used to determine if the I<--daemon> parameter was 
specified.

=item B<manager>

Returns the value passed on the command line with I<--manager>.

=back

=head2 Inspection

=over 4

=item B<has_pre_fork_init>

A predicate telling you if anything was passed to the 
I<pre_fork_init> constructor parameter.

=item B<pid_obj>

This will return a L<File::Pid> object to represent 
the pidfile passed with the I<--pidfile> option. This 
method will throw an exeception if you call it without
having specified the I<--pidfile> option, or if the 
pidfile has not yet been created.

=back

=head2 Important Stuff

=over 4

=item B<run>

Call this to start the show.

=back

=head2 Other Stuff

=over 4

=item B<BUILD>

This is the L<Moose> BUILD method, it checks some of 
our parameters to be sure all is sane.

=item B<daemon_fork>

=item B<daemon_detach>

These two methods were stolen verbatim from L<Catalyst::Engine::FastCGI>
if they are wrong, blame them (and send a patch to both of us).

=item B<meta>

This returns the L<Moose> metaclass assocaited with 
this class.

=back

=head SEE ALSO

=over 4

=item L<Catalyst::Engine::FastCGI>

I took all the guts of that module and squished them around a bit and 
stuffed them in here. 

=item L<MooseX::Getopt>

=item L<FCGI::ProcManager>

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


