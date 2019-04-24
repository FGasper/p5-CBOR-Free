# NAME

CBOR::Free - Fast CBOR for everyone

# SYNOPSIS

    $cbor = CBOR::Free::encode( $scalar_or_ar_or_hr );

    $thing = CBOR::Free::decode( $cbor )

    my $tagged = CBOR::Free::tag( 1, '2019-01-02T00:01:02Z' );

# DESCRIPTION

This library implements [CBOR](https://tools.ietf.org/html/rfc7049)
via XS under a license that permits commercial usage with no “strings
attached”.

# STATUS

This distribution is an experimental effort.

Note that this distribution’s interface can still change. If you decide
to use CBOR::Free in your project, please always check the changelog before
upgrading.

# FUNCTIONS

## $cbor = encode( $DATA )

Encodes a data structure or non-reference scalar to CBOR.
The encoder recognizes and encodes integers, floats, binary and UTF-8
strings, array and hash references, [CBOR::Free::Tagged](https://metacpan.org/pod/CBOR::Free::Tagged) instances,
[Types::Serialiser](https://metacpan.org/pod/Types::Serialiser) booleans, and undef (encoded as null).

The encoder currently does not handle any other blessed references.

An error is thrown on excess recursion.

## $data = decode( $CBOR )

Decodes a data structure from CBOR. Errors are thrown to indicate
invalid CBOR. A warning is thrown if $CBOR is longer than is needed
for $data.

Note that invalid UTF-8 in a string marked as UTF-8 is considered
an error.

## $obj = tag( $NUMBER, $DATA )

Tags an item for encoding so that its CBOR encoding will preserve the
tag number. (Include $obj, not $DATA, in the data structure that
`encode()` receives.)

# ERROR HANDLING

Most errors are represented via instances of subclasses of
[CBOR::Free::X](https://metacpan.org/pod/CBOR::Free::X).

# TODO

- Make it faster. On some platforms (e.g., Linux) it appears to be
faster than [JSON::XS](https://metacpan.org/pod/JSON::XS) but not quite as fast as [CBOR::XS](https://metacpan.org/pod/CBOR::XS); on others
(e.g., macOS), it’s slower than both.

# AUTHOR

[Gasper Software Consulting](http://gaspersoftware.com) (FELIPE)

# LICENSE

This code is licensed under the same license as Perl itself.

# SEE ALSO

[CBOR::XS](https://metacpan.org/pod/CBOR::XS) is an older, GPL-licensed CBOR module. It implements
some behaviors around CBOR tagging that you might find useful.
