#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use Data::Dumper;

use_ok('CBOR::Free');

my @tests = (
    [ q<> => "\x60" ],
    [ "\xff" => "\x41\xff" ],
    [ 'abc' => "\x63\x61\x62\x63" ],
    [ ('a' x 23) => "\x77" . ('a' x 23) ],
    [ ('a' x 24) => "\x78\x18" . ('a' x 24) ],
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
