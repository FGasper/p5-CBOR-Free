package CBOR::Free;

use strict;
use warnings;

use XSLoader ();

our ($VERSION);

BEGIN {
    $VERSION = '0.01';
    XSLoader::load();
}

1;
