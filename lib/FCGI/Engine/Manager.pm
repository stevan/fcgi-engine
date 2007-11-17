
package FCGI::Engine::Manager;
use Moose;
use MooseX::Types::Path::Class;

$|++;

use FCGI::Engine::Manager::Server;

use Best [
    [ qw[YAML::Syck YAML] ], 
    [ qw[LoadFile] ]
];

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

with 'MooseX::Getopt';

has 'conf' => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
);

has '_servers' => (
    reader    => 'servers',
    isa       => 'ArrayRef[FCGI::Engine::Manager::Server]',
    lazy      => 1,
    default   => sub {
        my $self = shift;
        my $servers = LoadFile($self->conf->stringify)->{servers};
        return [ 
            map { 
                $_->{server_class} ||= "FCGI::Engine::Manager::Server";
                $_->{server_class}->new(%$_);
            } @$servers 
        ];
    },
);

sub run {
    my $self = shift;
    my $cmd  = ($self->extra_argv || [])->[0] || confess "No command specified";
    $self->$cmd;
}

sub log { shift; print @_, "\n" }

sub start {
    my $self = shift;
    
    $self->log("Starting up the FCGI servers ...");

    foreach my $server (@{$self->servers}) {
    
        my @cli = $server->construct_command_line();
        $self->log("Running @cli");
    
        unless (system(@cli) == 0) {
            $self->log("Could not execute command (@cli) exited with status $?");
            $self->log("... stoping FCGI servers");
            $self->stop;
            return;
        }
    
        my $count = 1;
        until (-e $server->pidfile) {
            $self->log("pidfile (" . $server->pidfile . ") does not exist yet ... (trying $count times)");
            sleep 2;
            $count++;
        }
        
        my $pid = $server->pid_obj;

        while (!$pid->running) {
            $self->log("pid (" . $pid->pid . ") with pid_file (" . $server->pidfile . ") is not running yet, sleeping ...");
            sleep 2;
        }

        $self->log("Pid " . $pid->pid . " is running");
    
    }

    $self->log("... FCGI servers have been started");
}

sub status {
    join "\n" => map { chomp; s/\s+$//; $_ } `ps auxwww | grep fcgi`;    
}

sub stop {
    my $self = shift;
        
    $self->log("Killing the FCGI servers ...");

    foreach my $server (@{$self->servers}) {
    
        if (-f $server->pidfile) {
            
            my $pid = $server->pid_obj;
            
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

FCGI::Engine::Manager

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




