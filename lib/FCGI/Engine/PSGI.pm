package FCGI::Engine::PSGI;
use Moose;

use Plack::Util;

our $VERSION   = '0.13';
our $AUTHORITY = 'cpan:STEVAN';

extends 'FCGI::Engine::Core';

has 'app' => (
    is       => 'ro',
    isa      => 'CodeRef',
    required => 1,
);

augment 'prepare_environment' => sub {
    my ($self, $env) = @_;
    return +{
        %$env,
        'psgi.version'      => [1,0],
        'psgi.url_scheme'   => ($env->{HTTPS}||'off') =~ /^(?:on|1)$/i ? 'https' : 'http',
        'psgi.input'        => *STDIN,
        'psgi.errors'       => *STDERR, # FCGI.pm redirects STDERR in Accept() loop, so just print STDERR
                                        # print to the correct error handle based on keep_stderr
        'psgi.multithread'  => Plack::Util::FALSE,
        'psgi.multiprocess' => Plack::Util::TRUE,
        'psgi.run_once'     => Plack::Util::FALSE,
    };
};

sub handle_request {
    my ( $self, $env ) = @_;

    my $res = Plack::Util::run_app( $self->app, $env );
    print "Status: $res->[0]\n";
    my $headers = $res->[1];
    while (my ($k, $v) = splice @$headers, 0, 2) {
        print "$k: $v\n";
    }
    print "\n";

    my $body = $res->[2];
    my $cb = sub { print STDOUT $_[0] };

    Plack::Util::foreach($body, $cb);
}

__PACKAGE__->meta->make_immutable;

no Moose; 1;

__END__

=pod

=head1 NAME

FCGI::Engine::PSGI - Run PSGI applications with FCGI::Engine

=head1 SYNOPSIS

  # in scripts/my_psgi_app_fcgi.pl
  use strict;
  use warnings;

  use FCGI::Engine::PSGI;

  FCGI::Engine::PSGI->new_with_options(
      app => sub {
          my $env = shift;
          [
              200,
              [ 'Content-type' => 'text/html' ],
              [ "Hello World" ]
          ]
      }
  )->run;

  # run as normal FCGI script
  perl scripts/my_psgi_app_fcgi.pl

  # run as standalone FCGI server
  perl scripts/my_psgi_app_fcgi.pl --nproc 10 --pidfile /tmp/my_app.pid \
                                   --listen /tmp/my_app.socket --daemon

  # see also FCGI::Engine::Manager for managing
  # multiple FastCGI backends under one script

=head1 DESCRIPTION

This is an extension of L<FCGI::Engine::Core> to support L<PSGI> applications.
You can refer to the L<FCGI::Engine> docs for most of what you need to know,
the only difference being that instead of a C<handler_class>, C<handler_method>
and C<handler_args> you simply have the C<app> attribute, which is expected
to be a L<PSGI> compliant application.

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2009 Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
