#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use_ok('CBOR::Free');

my @nums = (
    1.1,
    -4.1,
    ( map { 100 * rand() - 50 } 1 .. 10 ),
);

# Ensure that we have something that encodes to a double cleanly.
$_ = unpack( 'd', pack('d', $_) ) for @nums;

for my $i ( @nums ) {
    my $encoded = CBOR::Free::encode($i);

    _cmpbin( $encoded, pack('C d>', 0xfb, $i), "encode $i" );

    is(
        CBOR::Free::decode($encoded),
        $i,
        "… and it round-trips",
    );
}

sub _cmpbin {
    my ($got, $expect, $label) = @_;

    $_ = sprintf('%v.02x', $_) for ($got, $expect);

    return is( $got, $expect, $label );
}

#----------------------------------------------------------------------

done_testing;
