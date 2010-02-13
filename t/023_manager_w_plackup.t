#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use Cwd;
use File::Spec::Functions;

use Test::More;
use Test::Exception;
use Test::Moose;

BEGIN {
    my $got_YAML = 1;
    eval "use YAML::XS;";
    $got_YAML = 0 if $@;
    plan skip_all => "Some kind of YAML parser is required for this test" unless $got_YAML;
    {
        local $@;
        eval "use Plack;";
        plan skip_all => "Plack is required for this test" if $@;
    }
    plan tests => 11;
    use_ok('FCGI::Engine::Manager');
}

my $CWD                = Cwd::cwd;
$ENV{MX_DAEMON_STDOUT} = catfile($CWD, 'Out.txt');
$ENV{MX_DAEMON_STDERR} = catfile($CWD, 'Err.txt');

my $m = FCGI::Engine::Manager->new(
    conf => catfile($FindBin::Bin, 'confs', 'test_plack_conf.yml')
);
isa_ok($m, 'FCGI::Engine::Manager');
does_ok($m, 'MooseX::Getopt');

lives_ok {
    $m->start('baz.server');
} '... started baz server okay';

is( $m->status, "baz.server is running\n", '... got the right status' );

#diag join "\n" => map { chomp; s/\s+$//; $_ } grep { /fcgi|overseer|minion/ } `ps auxwww`;

lives_ok {
    $m->stop();
} '... stopped all okay';

is( $m->status, "baz.server is not running\n", '... got the right status' );

## now reverse that ...

lives_ok {
    $m->start();
} '... started all okay';

is( $m->status, "baz.server is running\n", '... got the right status' );

lives_ok {
    $m->stop('baz.server');
} '... stopped baz server okay';

is( $m->status, "baz.server is not running\n", '... got the right status' );

#diag join "\n" => map { chomp; s/\s+$//; $_ } grep { /fcgi|overseer|minion/ } `ps auxwww`;

unlink $ENV{MX_DAEMON_STDOUT};
unlink $ENV{MX_DAEMON_STDERR};
