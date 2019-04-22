# NAME

CBOR::Free - Fast CBOR for everyone

# SYNOPSIS

    $cbor = CBOR::Free::encode( $scalar_or_ar_or_hr );

    # There’s no decoder yet … sorry.

# DESCRIPTION

This library implements [CBOR](https://tools.ietf.org/html/rfc7049)
via XS under a license that permits commercial usage with no “strings
attached”.

# STATUS

This distribution is an experimental effort.

Note that this distribution’s interface can still change. If you decide
to use CBOR::Free in your project, please always check the changelog before
upgrading.

# TODO

- Build a decoder. :)
- Add 64-bit number support.
- Make it faster. On some platforms (e.g., Linux) it appears to be
faster than [JSON::XS](https://metacpan.org/pod/JSON::XS) but not quite as fast as [CBOR::XS](https://metacpan.org/pod/CBOR::XS); on others
(e.g., macOS), it’s slower than both.

# AUTHOR

[Gasper Software Consulting](http://gaspersoftware.com) (FELIPE)

# LICENSE

This code is licensed under the same license as Perl itself.

# SEE ALSO

[CBOR::XS](https://metacpan.org/pod/CBOR::XS) exists but is GPL-licensed.
