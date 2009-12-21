use strict;
use warnings;
use inc::Module::Install;

die "This module is not for use on Windows, sorry."
    if  $^O eq 'Win32' or $^O eq 'cygwin';

name 'FCGI-Engine';
all_from 'lib/FCGI/Engine.pm';
license 'perl';

# prereqs
requires 'Moose'                    => 0.90;
requires 'MooseX::Daemonize'        => 0.06;
requires 'MooseX::Getopt'           => 0.14;
requires 'MooseX::Types::Path::Class';
requires 'Declare::Constraints::Simple';
requires 'FCGI';
requires 'CGI::Simple';
requires 'POSIX';
requires 'Config::Any';

feature 'Plack Support',
  -default           => 0,
  'MooseX::NonMoose' => 0.07,
  'IO::String'       => 0,  # for the tests
  'Plack'            => 0;

# things the tests need
build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'Test::WWW::Mechanize';
build_requires 'File::Spec';
build_requires 'FindBin';
build_requires 'Cwd';

tests('t/*.t');

WriteAll();

