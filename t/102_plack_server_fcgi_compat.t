#!/usr/bin/perl

use strict;
use warnings;
use FindBin;

use Test::More;

BEGIN {
    {
        local $@;
        eval "use Plack;";
        plan skip_all => "Plack is required for this test" if $@;
    }
    use Plack::Server::FCGI::Engine;
}

use Test::TCP;
use Plack::Test::Suite;
use t::lib::FCGIUtils;

my $lighty_port;
my $fcgi_port;

test_lighty_external(
   sub {
       ($lighty_port, $fcgi_port) = @_;
       Plack::Test::Suite->run_server_tests(\&run_one, $fcgi_port, $lighty_port);
       done_testing();
    }
);

sub run_one {
    my($port, $app) = @_;
    my $server = Plack::Server::FCGI::Engine->new(
        host        => '127.0.0.1',
        port        => $port,
        manager     => '',
        keep_stderr => 1,
    );
    $server->run($app);
}


