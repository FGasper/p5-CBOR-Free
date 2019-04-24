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

=head2 $cbor = encode( $DATA )

Encodes a data structure or non-reference scalar to CBOR.
The encoder recognizes and encodes integers, floats, binary and UTF-8
strings, array and hash references, L<CBOR::Free::Tagged> instances,
L<Types::Serialiser> booleans, and undef (encoded as null).

The encoder currently does not handle any other blessed references.

An error is thrown on excess recursion.

=head2 $data = decode( $CBOR )

Decodes a data structure from CBOR. Errors are thrown to indicate
invalid CBOR. A warning is thrown if $CBOR is longer than is needed
for $data.

Note that invalid UTF-8 in a string marked as UTF-8 is considered
an error.

=head2 $obj = tag( $NUMBER, $DATA )

Tags an item for encoding so that its CBOR encoding will preserve the
tag number. (Include $obj, not $DATA, in the data structure that
C<encode()> receives.)

=head1 ERROR HANDLING

Most errors are represented via instances of subclasses of
L<CBOR::Free::X>.

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
    die CBOR::Free::X->create( 'Recursion', _MAX_RECURSION());
}

sub _die {
    my ($subclass, @args) = @_;

    die CBOR::Free::X->create($subclass, @args);
}

# Without the initial 0 value, our XS code warns about
# “Use of uninitialized value in subroutine entry”.
# There surely is a better way to suppress this warning,
# but what’s here works. (TODO)
our $_LEFTOVER_COUNT = 0;

sub _warn_decode_leftover {
    warn "CBOR buffer contained $_LEFTOVER_COUNT excess bytes";
}

1;
