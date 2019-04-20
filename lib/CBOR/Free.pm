package CBOR::Free;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

CBOR::Free - Fast CBOR for everyone

=head1 DESCRIPTION

This library implements CBOR via XS under a license that permits
commercial usage.

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
