#!/usr/bin/perl

use strict;
use warnings;
use FindBin;

use Test::More;

BEGIN {
    {
        local $@;
        eval "use Plack; use FCGI::Client;";
        plan skip_all => "Plack and FCGI::Client are required for this test" if $@;
    }
}

use Plack::Handler::FCGI::Engine;
use Test::TCP;
use Plack::Test::Suite;
use t::lib::FCGIUtils;

my $http_port;
my $fcgi_port;

test_fcgi_standalone(
   sub {
       ($http_port, $fcgi_port) = @_;
       Plack::Test::Suite->run_server_tests(\&run_one, $fcgi_port, $http_port);
       done_testing();
    }
);

sub run_one {
    my($port, $app) = @_;
    my $server = Plack::Handler::FCGI::Engine->new(
        host        => '127.0.0.1',
        port        => $port,
        pidfile     => '/tmp/101_plack_server_fcgi_engine_client.pid',
        keep_stderr => 1,
    );
    $server->run($app);
}


