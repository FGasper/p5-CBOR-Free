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

Notes on mapping Perl to CBOR:

- The internal state of a defined Perl scalar (e.g., whether it’s an
integer, float, binary string, or UTF-8 string) determines its CBOR
encoding.
- [Types::Serialiser](https://metacpan.org/pod/Types::Serialiser) booleans are encoded as CBOR booleans.
Perl undef is encoded as CBOR null. (NB: No Perl value encodes as CBOR
undefined.)
- Instances of [CBOR::Free::Tagged](https://metacpan.org/pod/CBOR::Free::Tagged) are encoded as tagged values.

An error is thrown on excess recursion or an unrecognized object.

## $data = decode( $CBOR )

Decodes a data structure from CBOR. Errors are thrown to indicate
invalid CBOR. A warning is thrown if $CBOR is longer than is needed
for $data.

Notes on mapping CBOR to Perl:

- CBOR UTF-8 strings become Perl UTF-8 strings. CBOR binary strings
become Perl binary strings. (This may become configurable later.)

    Note that invalid UTF-8 in a CBOR UTF-8 string is considered
    invalid input and will thus prompt a thrown exception.

- CBOR booleans become the corresponding [Types::Serialiser](https://metacpan.org/pod/Types::Serialiser) values.
Both CBOR null and undefined become Perl undef.
- Tags are IGNORED for now. (This may become configurable later.)

## $obj = tag( $NUMBER, $DATA )

Tags an item for encoding so that its CBOR encoding will preserve the
tag number. (Include $obj, not $DATA, in the data structure that
`encode()` receives.)

# BOOLEANS

`CBOR::Free::true()`, `CBOR::Free::false()`,
`$CBOR::Free::true`, and `$CBOR::Free::false` are defined as
convenience aliases for the equivalent [Types::Serialiser](https://metacpan.org/pod/Types::Serialiser) values.

# ERROR HANDLING

Most errors are represented via instances of subclasses of
[CBOR::Free::X](https://metacpan.org/pod/CBOR::Free::X).

# TODO

- Add canonical encode().
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
