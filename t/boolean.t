#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Types::Serialiser;

use Data::Dumper;

use_ok('CBOR::Free');

my @tests = (
    [ Types::Serialiser::true() => "\xf5" ],
    [ Types::Serialiser::false() => "\xf4" ],
);

for my $t (@tests) {
    my ($in, $enc) = @$t;

    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Indent = 0;

    _cmpbin( CBOR::Free::encode($in), $enc, "Encode: " . Dumper($in) );
}

sub _cmpbin {
    my ($got, $expect, $label) = @_;

    $_ = sprintf('%v.02x', $_) for ($got, $expect);

    return is( $got, $expect, $label );
}

done_testing;
