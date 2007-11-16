
package FCGI::Engine::Manager;
use Moose;
use MooseX::AttributeHelpers;
use MooseX::Types::Path::Class;

use FCGI::Engine::Manager::Server;

use File::Pid;
use Best [
    [ qw[YAML::Syck YAML] ], 
    [ qw[LoadFile] ]
];

with 'MooseX::Getopt';

has 'conf' => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
);

has '_servers' => (
    metaclass => 'Collection::Array',
    reader    => 'servers',
    isa       => 'ArrayRef[FCGI::Engine::Manager::Server]',
    lazy      => 1,
    default   => sub {
        my $self = shift;
        my $servers = LoadFile($self->conf->stringify)->{servers};
        return [ map { FCGI::Engine::Manager::Server->new(%$_) } @$servers ]
    },
    provides  => {
        # ... 
    }
);

sub run {
    my $self = shift;
    my $cmd  = $self->extra_argv->[0] || confess "No command specified";
    $self->$cmd;
}

sub log { shift; print @_, "\n" }

sub _construct_cli {
    my ($self, $server) = @_;
    return (
        #"/usr/sbin/daemon", 
        #"sh", "-c", 
        ("/usr/bin/perl -I lib " 
         . $server->scriptname 
         . " --nproc "
         . $server->nproc 
         . " --pidfile "
         . $server->pidfile 
         . " --listen "
         . $server->socket 
         . " --daemon")
    );    
}

sub start {
    my $self = shift;
    
    $self->log("Starting up the FCGI servers ...");

    foreach my $server (@{$self->servers}) {
    
        my @cli = $self->_construct_cli($server);
        $self->log("Running @cli");
    
        # NOTE:
        # this should actually not die, but log 
        # the fact that $server didnt start and 
        # then call ->stop
        # - SL
        system(@cli) == 0
            or die "Could not execute command exited with status $?";
    
        my $count = 1;
        until (-e $server->pidfile) {
            $self->log("pidfile (" . $server->pidfile . ") does not exist yet ... (trying $count times)");
            sleep 2;
            $count++;
        }
        
        my $pid = File::Pid->new({ file => $server->pidfile });

        while (!$pid->running) {
            $self->log("pid (" . $pid->pid . ") with pid_file (" . $server->pidfile . ") is not running yet, sleeping ...");
            sleep 2;
        }

        $self->log("Pid " . $pid->pid . " is running");
    
    }

    $self->log("... FCGI servers have been started");
}

sub stop {
    my $self = shift;
        
    $self->log("Killing the FCGI servers ...");

    foreach my $server (@{$self->servers}) {
    
        if (-f $server->pidfile) {
            my $pid = File::Pid->new({ file => $server->pidfile });
            kill TERM => $pid->pid;
            while ($pid->running) {
                $self->log("pid (" . $server->pidfile . ") is still running, sleeping ...");
                sleep 1;
            }                       
        }
    
        if (-e $server->socket) {
            unlink($server->socket);
        }
    
    }    

    $self->log("... FCGI servers have been killed");
}

1;

__END__

=pod

=head1 NAME

FCGI::Engine

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

