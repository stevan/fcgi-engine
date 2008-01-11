use strict;
use warnings;
use inc::Module::Install;

die "This module is not for use on Windows, sorry."
    if  $^O eq 'Win32' or $^O eq 'cygwin';

name 'FCGI-Engine';
all_from 'lib/FCGI/Engine.pm';
license 'perl';

# prereqs
requires 'Moose'                    => 0.32;
requires 'MooseX::AttributeHelpers' => 0.06;
requires 'MooseX::Daemonize'        => 0.05;
requires 'MooseX::Getopt'           => 0.07;
requires 'MooseX::Types::Path::Class';
requires 'Declare::Constraints::Simple';
requires 'FCGI';
requires 'CGI::Simple';
requires 'POSIX';
requires 'Config::Any';

# things the tests need
build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'File::Spec';
build_requires 'FindBin';
build_requires 'Cwd';

tests('t/*.t');

WriteAll();

