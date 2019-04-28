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

This distribution is an experimental effort. Its interface is still
subject to change. If you decide to use CBOR::Free in your project,
please always check the changelog before upgrading.

=head1 FUNCTIONS

=head2 $cbor = encode( $DATA, %OPTS )

Encodes a data structure or non-reference scalar to CBOR.
The encoder recognizes and encodes integers, floats, binary and UTF-8
strings, array and hash references, L<CBOR::Free::Tagged> instances,
L<Types::Serialiser> booleans, and undef (encoded as null).

The encoder currently does not handle any other blessed references.

%OPTS may be:

=over

=item * C<canonical> - A boolean that makes the function output
CBOR in L<canonical form|https://tools.ietf.org/html/rfc7049#section-3.9>.

=back

Notes on mapping Perl to CBOR:

=over

=item The internal state of a defined Perl scalar (e.g., whether it’s an
integer, float, binary string, or UTF-8 string) determines its CBOR
encoding.

=item L<Types::Serialiser> booleans are encoded as CBOR booleans.
Perl undef is encoded as CBOR null. (NB: No Perl value encodes as CBOR
undefined.)

=item Instances of L<CBOR::Free::Tagged> are encoded as tagged values.

=back

An error is thrown on excess recursion or an unrecognized object.

=head2 $data = decode( $CBOR )

Decodes a data structure from CBOR. Errors are thrown to indicate
invalid CBOR. A warning is thrown if $CBOR is longer than is needed
for $data.

Notes on mapping CBOR to Perl:

=over

=item * CBOR UTF-8 strings become Perl UTF-8 strings. CBOR binary strings
become Perl binary strings. (This may become configurable later.)

Note that invalid UTF-8 in a CBOR UTF-8 string is considered
invalid input and will thus prompt a thrown exception.

=item * CBOR booleans become the corresponding L<Types::Serialiser> values.
Both CBOR null and undefined become Perl undef.

=item * Tags are IGNORED for now. (This may become configurable later.)

=back

=head2 $obj = tag( $NUMBER, $DATA )

Tags an item for encoding so that its CBOR encoding will preserve the
tag number. (Include $obj, not $DATA, in the data structure that
C<encode()> receives.)

=head1 BOOLEANS

C<CBOR::Free::true()>, C<CBOR::Free::false()>,
C<$CBOR::Free::true>, and C<$CBOR::Free::false> are defined as
convenience aliases for the equivalent L<Types::Serialiser> values.

=head1 FRACTIONAL (FLOATING-POINT) NUMBERS

Floating-point numbers are encoded in CBOR as IEEE 754 half-, single-,
or double-precision. If your Perl is compiled to use “long double”
floating-point numbers, you may see rounding errors when converting
to/from CBOR. If that’s a problem for you, append an empty string to
your floating-point numbers, which will cause CBOR to encode
them as strings.

=head1 INTEGER LIMITS

CBOR handles up to 64-bit unsigned and signed integers. Most Perls
nowadays can handle this just fine, but if yours can’t then you’ll
get an exception whenever trying to parse an integer that can’t be
represented with 32 bits. This means:

=over

=item * Anything greater than 0xffff_ffff (4,294,967,295)

=item * Anything less than -0x8000_0000 (2,147,483,648)

=back

Note that even 64-bit Perls can’t parse negatives that are less than
-0x8000_0000_0000_0000 (-9,223,372,036,854,775,808); these also prompt an
exception since Perl can’t handle them.

=head1 ERROR HANDLING

Most errors are represented via instances of subclasses of
L<CBOR::Free::X>.

=head1 AUTHOR

L<Gasper Software Consulting|http://gaspersoftware.com> (FELIPE)

=head1 LICENSE

This code is licensed under the same license as Perl itself.

=head1 SEE ALSO

L<CBOR::XS> is an older CBOR module on CPAN. It implements
some behaviors around CBOR tagging that you might find useful.
Its maintainer has L<abandoned support for Perl versions from 5.22
onward|http://blog.schmorp.de/2015-06-06-stableperl-faq.html>, though,
and its GPL license limits its usefulness in
commercial L<perlcc|https://metacpan.org/pod/distribution/B-C/script/perlcc.PL>
applications.

=cut

#----------------------------------------------------------------------

use XSLoader ();

use Types::Serialiser;

use CBOR::Free::X;
use CBOR::Free::Tagged;

our ($VERSION);

BEGIN {
    $VERSION = '0.03_01';
    XSLoader::load();
}

our ($true, $false);
*true = *Types::Serialiser::true;
*false = *Types::Serialiser::false;

sub encode {
    my %opts = @_[ 1 .. $#_ ];

    return $opts{'canonical'} ? _c_encode_canonical($_[0]) : _c_encode($_[0]);
}

sub tag {
    return CBOR::Free::Tagged->new(@_);
}

#----------------------------------------------------------------------

sub _die_recursion {
    die CBOR::Free::X->create( 'Recursion', _MAX_RECURSION());
}

sub _die {
    my ($subclass, @args) = @_;

    die CBOR::Free::X->create($subclass, @args);
}

sub _warn_decode_leftover {
    my ($count) = @_;

    warn "CBOR buffer contained $count excess bytes";
}

1;
