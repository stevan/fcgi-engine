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
}

use Plack::Handler::FCGI::Engine;
use Test::TCP;
use Plack::Test::Suite;
use t::lib::FCGIUtils;

my $lighty_port;
my $fcgi_port;

test_lighty_external(
   sub {
       ($lighty_port, $fcgi_port, my $needs_fix) = @_;
       Plack::Test::Suite->run_server_tests(run_server_cb($needs_fix), $fcgi_port, $lighty_port);
       done_testing();
    }
);

sub run_server_cb {
    my $needs_fix = shift;

    require Plack::Middleware::LighttpdScriptNameFix;
    return sub {
        my($port, $app) = @_;

        note "Applying LighttpdScriptNameFix" if $needs_fix;
        $app = Plack::Middleware::LighttpdScriptNameFix->wrap($app) if $needs_fix;

        $| = 0; # Test::Builder autoflushes this. reset!

        my $server = Plack::Handler::FCGI::Engine->new(
            host        => '127.0.0.1',
            port        => $port,
            manager     => '',
            keep_stderr => 1,
        );
        $server->run($app);
    };
}


