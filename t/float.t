#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Config;

use_ok('CBOR::Free');

my @nums = (
    1.1,
    -4.1,
    ( map { 100 * rand() - 50 } 1 .. 10 ),
);

for my $i ( @nums ) {
    my $encoded = CBOR::Free::encode($i);

    _cmpbin( $encoded, pack('C d>', 0xfb, $i), "encode $i" );

  SKIP: {
        skip 'Long-double perls introduce rounding errors when decoding CBOR floats.', 1 if $Config{'uselongdouble'};

        is(
            CBOR::Free::decode($encoded),
            $i,
            "… and it round-trips",
        );
    }
}

sub _cmpbin {
    my ($got, $expect, $label) = @_;

    $_ = sprintf('%v.02x', $_) for ($got, $expect);

    return is( $got, $expect, $label );
}

#----------------------------------------------------------------------

done_testing;
