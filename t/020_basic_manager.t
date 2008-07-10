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
    eval "use YAML;";
    if ($@) {
       local $@;
       eval "use YAML::Syck";
       $got_YAML = 0 if $@;
    }
    plan skip_all => "Some kind of YAML parser is required for this test" unless $got_YAML;    
    plan tests => 5;
    use_ok('FCGI::Engine::Manager');
}

my $CWD                = Cwd::cwd;
$ENV{MX_DAEMON_STDOUT} = catfile($CWD, 'Out.txt');
$ENV{MX_DAEMON_STDERR} = catfile($CWD, 'Err.txt');

my $m = FCGI::Engine::Manager->new(
    conf => catfile($FindBin::Bin, 'confs', 'test_conf.yml')
);
isa_ok($m, 'FCGI::Engine::Manager');
does_ok($m, 'MooseX::Getopt');

lives_ok {
    $m->start;
} '... started okay';

#diag join "\n" => map { chomp; s/\s+$//; $_ } grep { /fcgi|overseer|minion/ } `ps auxwww`;

lives_ok {
    $m->stop;
} '... started okay';

unlink $ENV{MX_DAEMON_STDOUT};
unlink $ENV{MX_DAEMON_STDERR};

