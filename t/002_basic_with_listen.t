#!/usr/bin/perl

use strict;
use warnings;
use Socket;

use Test::More no_plan => 1;
use Test::Moose;

BEGIN {
    use_ok('FCGI::Engine');
}

{
    package Foo;
    sub handler { 
        "Foo::handler was called (but no one will ever see this)";
    }
}

my $SOCKET  = '/tmp/fcgi_engine_test_application.socket';
my $PIDFILE = '/tmp/fcgi_engine_test_application.pid';

@ARGV = (
    '--listen'  => $SOCKET,
    '--pidfile' => $PIDFILE,
    '--daemon'
);

my $e = FCGI::Engine->new_with_options(handler_class => 'Foo');
isa_ok($e, 'FCGI::Engine');
does_ok($e, 'MooseX::Getopt');

ok($e->is_listening, '... we are listening');
is($e->listen, $SOCKET, '... we have the right socket location');

is($e->nproc, 1, '... we have the default 1 proc');

ok($e->has_pidfile, '... we have a pidfile');
is($e->pidfile, $PIDFILE, '... we have the right pidfile');

ok($e->should_detach, '... we should daemonize');

is($e->manager, 'FCGI::Engine::ProcManager', '... we have the default manager (FCGI::ProcManager)');
ok(!$e->has_pre_fork_init, '... we dont have any pre-fork-init');

unless ( fork ) {
    $e->run;
    exit;
}
else {
    sleep(1);    # 1 seconds should be enough for everything to happen
    
    ok(-S $SOCKET, '... our socket was created');
    ok(-f $PIDFILE, '... our pidfile was created');

    my $pid = $e->pid_obj;
    isa_ok($pid, 'File::Pid');

    ok($pid->running, '... our daemon is running');

    kill TERM => $pid->pid;
    unlink $SOCKET;
}
