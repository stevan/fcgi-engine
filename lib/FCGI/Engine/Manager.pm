
package FCGI::Engine::Manager;
use Moose;

use FCGI::Engine::Types;
use FCGI::Engine::Manager::Server;

use Config::Any;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

with 'MooseX::Getopt';

has 'conf' => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
);

has '_config' => (
    is       => 'ro',
    isa      => 'FCGI::Engine::Manager::Config',
    lazy     => 1,
    default  => sub {
        my $self   = shift;
        my $file   = $self->conf->stringify;
        my $config = Config::Any->load_files({ 
            files   => [ $file ],
            use_ext => 1
        })->[0]->{$file};
        #use Data::Dumper; 
        #warn Dumper $config;
        return $config;
    }
);

has '_servers' => (
    reader    => 'servers',
    isa       => 'ArrayRef[FCGI::Engine::Manager::Server]',
    lazy      => 1,
    default   => sub {
        my $self = shift;
        return [ 
            map { 
                $_->{server_class} ||= "FCGI::Engine::Manager::Server";
                Class::MOP::load_class($_->{server_class});
                $_->{server_class}->new(%$_);
            } @{$self->_config} 
        ];
    },
);

sub log { shift; print @_, "\n" }

sub start {
    my $self = shift;
    
    local $| = 1;
    
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

        while (!$pid->is_running) {
            $self->log("pid (" . $pid->pid . ") with pid_file (" . $server->pidfile . ") is not running yet, sleeping ...");
            sleep 2;
        }

        $self->log("Pid " . $pid->pid . " is running");
    
    }

    $self->log("... FCGI servers have been started");
}

sub status {
    # FIXME:
    # there must be a better way to do this, 
    # and even if there isn't we should come
    # up with a better way to display them
    # (oh yeah and filter out things not related
    # to us as well)
    # - SL
    join "\n" => map { chomp; s/\s+$//; $_ } `ps auxwww | grep fcgi`;    
}

sub stop {
    my $self = shift;
    
    local $| = 1;    
        
    $self->log("Killing the FCGI servers ...");

    foreach my $server (@{$self->servers}) {
    
        if (-f $server->pidfile) {
            
            my $pid = $server->pid_obj;
            
            $self->log("Killing PID " . $pid->pid . " from $$ ");
            kill TERM => $pid->pid;
            
            while ($pid->is_running) {
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

FCGI::Engine::Manager - Manage multiple FCGI::Engine instances

=head1 SYNOPSIS

  my $m = FCGI::Engine::Manager->new(
      conf => 'conf/my_app_conf.yml'
  );
  
  $m->start  if $ARGV[0] eq 'start';
  $m->status if $ARGV[0] eq 'status';
  $m->stop   if $ARGV[0] eq 'stop';    

=head1 DESCRIPTION

This module handles multiple FCGI::Engine instances for you, it can 
start, stop and provide basic status info. It is configurable using 
L<Config::Any>, but only really the YAML format has been tested. 

This module is still in it's early stages, many things may change.

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007-2008 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut




