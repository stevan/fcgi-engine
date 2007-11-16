#!/usr/bin/perl

use strict;
use warnings;

use FCGI::Engine;

{
    package Foo;
    sub handler { () }
}

FCGI::Engine->new_with_options(handler_class => 'Foo')->run;