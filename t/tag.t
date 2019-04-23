#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

use Data::Dumper;

use_ok('CBOR::Free');

my @tests = (
    [ CBOR::Free::tag( 12, 12 ) => "\xcc\x0c" ],
    [ CBOR::Free::tag( 24, "\0\1\2" ) => "\xd8\x18\x43\0\1\2"],
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
