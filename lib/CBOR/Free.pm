package CBOR::Free;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

CBOR::Free - Fast CBOR for everyone

=head1 SYNOPSIS

    $cbor = CBOR::Free::encode( $scalar_or_ar_or_hr );

    $thing = CBOR::Free::decode( $cbor )

    my $tagged = CBOR::Free::tag( 1, '2019-01-02T00:01:02Z' );

=head1 DESCRIPTION

This library implements L<CBOR|https://tools.ietf.org/html/rfc7049>
via XS under a license that permits commercial usage with no “strings
attached”.

=head1 STATUS

This distribution is an experimental effort.

Note that this distribution’s interface can still change. If you decide
to use CBOR::Free in your project, please always check the changelog before
upgrading.

=head1 FUNCTIONS

=head1 TODO

=over

=item * Make it faster. On some platforms (e.g., Linux) it appears to be
faster than L<JSON::XS> but not quite as fast as L<CBOR::XS>; on others
(e.g., macOS), it’s slower than both.

=back

=head1 AUTHOR

L<Gasper Software Consulting|http://gaspersoftware.com> (FELIPE)

=head1 LICENSE

This code is licensed under the same license as Perl itself.

=head1 SEE ALSO

L<CBOR::XS> is an older, GPL-licensed CBOR module. It implements
some behaviors around CBOR tagging that you might find useful.

=cut

#----------------------------------------------------------------------

use XSLoader ();

use Types::Serialiser;

use CBOR::Free::X;
use CBOR::Free::Tagged;

our ($VERSION);

BEGIN {
    $VERSION = '0.01';
    XSLoader::load();
}

*true = *Types::Serialiser::true;
*false = *Types::Serialiser::false;

sub tag {
    return CBOR::Free::Tagged->new(@_);
}

sub _die_recursion {
    die CBOR::Free::X->create('Recursion', _MAX_RECURSION());
}

sub _die_unrecognized {
    my ($alien) = @_;

    die CBOR::Free::X->create('Unrecognized', $alien);
}

sub _die_incomplete {
    my ($lack) = @_;

    die CBOR::Free::X->create('Incomplete', $lack);
}

1;
