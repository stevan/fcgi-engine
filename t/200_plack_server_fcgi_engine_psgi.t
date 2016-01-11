#!/usr/bin/perl

use strict;
use warnings;
use FindBin;

use Test::More;

BEGIN {
    {
        local $@;
        eval "use Plack 0.9910; use FCGI::Client 0.06; use MooseX::NonMoose 0.07; use IO::String; use Plack::App::FCGIDispatcher;";
        plan skip_all => "Plack 0.9910, FCGI::Client 0.06, MooseX::NonMoose 0.07 and Plack::App::FCGIDispatcher are required for this test" if $@;
    }
}

use Plack::Handler::FCGI::Engine::PSGI;
use Test::TCP;
use Plack::Test::Suite;
use t::lib::FCGIUtils;

my $http_port;
my $fcgi_port;

test_fcgi_standalone(
   sub {
       ($http_port, $fcgi_port) = @_;
       Plack::Test::Suite->run_server_tests(\&run_server, $fcgi_port, $http_port);
       done_testing();
    }
);

sub run_server {
    my($port, $app) = @_;

    $| = 0; # Test::Builder autoflushes this. reset!

    my $server = Plack::Handler::FCGI::Engine::PSGI->new(
        listen      => "127.0.0.1:$port",
        pidfile     => '/tmp/101_plack_server_fcgi_engine_client.pid',
    );
    $server->run($app);
}

