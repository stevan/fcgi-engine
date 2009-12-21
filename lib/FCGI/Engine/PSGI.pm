package FCGI::Engine::PSGI;
use Moose;

use Plack::Util;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

extends 'FCGI::Engine::Core';

has 'app' => (
    is        => 'rw',
    isa       => 'CodeRef',
    predicate => 'has_app',
);

augment 'initialize' => sub {
    my ( $self, %addtional_options ) = @_;

    unless ( $self->has_app ) {
        (exists $addtional_options{ 'app' })
            || confess "You must supply an 'app' key in the params to 'run'";

        $self->app( $addtional_options{ 'app' } );
    }
};

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

FCGI::Engine::PSGI - A Moosey solution to this problem

=head1 SYNOPSIS

  use FCGI::Engine::PSGI;

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item B<>

=back

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
