#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use_ok('CBOR::Free');

for my $i ( 1.1, -4.1 ) {
    _cmpbin( CBOR::Free::encode($i), pack('C d>', 0xfb, $i), "encode $i" );
}

sub _cmpbin {
    my ($got, $expect, $label) = @_;

    $_ = sprintf('%v.02x', $_) for ($got, $expect);

    return is( $got, $expect, $label );
}

done_testing;
