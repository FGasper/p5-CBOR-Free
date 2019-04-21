package CBOR::Free;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

CBOR::Free - Fast CBOR for everyone

=head1 SYNOPSIS

    $cbor = CBOR::Free::encode( $scalar_or_ar_or_hr );

    # There’s no decoder yet … sorry.

=head1 DESCRIPTION

This library implements CBOR via XS under a license that permits
commercial usage.

=head1 STATUS

This distribution is an experimental effort.

Note that this distribution’s interface can still change. If you decide
to use CBOR::Free in your project, please always check the changelog before
upgrading.

=head1 AUTHOR

L<Gasper Software Consulting|http://gaspersoftware.com> (FELIPE)

=head1 LICENSE

This code is licensed under the same license as Perl itself.

=head1 SEE ALSO

L<CBOR::XS> exists but is GPL-licensed.

=cut

#----------------------------------------------------------------------

use XSLoader ();

our ($VERSION);

BEGIN {
    $VERSION = '0.01';
    XSLoader::load();
}

1;
