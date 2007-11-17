#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use File::Spec::Functions;

use Test::More no_plan => 1;
use Test::Exception;
use Test::Moose;

BEGIN {
    use_ok('FCGI::Engine::Manager');
}

my $m = FCGI::Engine::Manager->new(
    conf => catfile($FindBin::Bin, 'confs', 'test_conf.yml')
);
isa_ok($m, 'FCGI::Engine::Manager');
does_ok($m, 'MooseX::Getopt');

lives_ok {
    $m->start;
} '... started okay';

diag $m->status;

lives_ok {
    $m->stop;
} '... started okay';
