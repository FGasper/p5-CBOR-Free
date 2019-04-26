#!/usr/bin/env perl

# These are the examples provided in RFC 7049.

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Config;

my $long_double_yn = $Config::Config{'uselongdouble'};

use Types::Serialiser ();

use CBOR::Free;

my $is_64bit = eval { pack 'q' };

my @examples = (
    [ 0 => '00' ],
    [ 1 => '01' ],
    [ 10 => '0a' ],
    [ 23 => '17' ],
    [ 24 => '1818' ],
    [ 25 => '1819' ],
    [ 100 => '1864' ],
    [ 1000 => '1903e8' ],
    [ 1000000 => '1a000f4240' ],
    ($is_64bit ?
        (
            [ 1000000000000 => '1b000000e8d4a51000' ],
            [ 1000000000000 => '1b000000e8d4a51000' ],
            [ 18446744073709551615 => '1bffffffffffffffff' ],
            #[ -18446744073709551616 => '3bffffffffffffffff' ],
        ) : ()
    ),
    [ Types::Serialiser::false() => 'f4' ],
    [ Types::Serialiser::true() => 'f5' ],
    [ undef, 'f6' ],
    # “undefined” isn’t represented
    [ q<> => '40' ],
    [ pack('U', 0xfc) => '62c3bc' ],
    [ "\x{6c34}" => '63e6b0b4' ],
    [ [] => '80' ],
    [ [1,2,3] => '83010203' ],
    [ [1, [2, 3], [4, 5]] => '8301820203820405' ],
    [
        [ 1, 2, 3, 4, 5, 6, 7, 8, 9,
          10, 11, 12, 13, 14, 15, 16,
          17, 18, 19, 20, 21, 22, 23,
          24, 25 ],
        '98190102030405060708090a0b0c0d0e0f101112131415161718181819',
    ],
    [ {} => 'a0' ],
);

for my $t (@examples) {
    is(
        unpack( 'H*', CBOR::Free::encode( $t->[0] ) ),
        $t->[1],
        sprintf('Encode to %s', $t->[1]),
    );

    use Devel::Peek;

    my $decoded = CBOR::Free::decode( pack( 'H*', $t->[1] ) );

    is_deeply(
        $decoded,
        $t->[0],
        sprintf('Decode %s', $t->[1])
    ) or Devel::Peek::Dump($decoded);

    my $got = CBOR::Free::decode( CBOR::Free::encode( $t->[0] ) );
    is_deeply(
        $got,
        $t->[0],
        sprintf("Round-trip: $t->[1]"),
    ) or Devel::Peek::Dump($got);
}

diag '----------';

sub _pre_522_lc {
    return( $^V ge v5.22.0 ? $_[0] : lc $_[0] );
}

my @decode = (
    [ -1 => '20' ],
    [ -10 => '29' ],
    [ -100 => '3863' ],
    [ -1000 => '3903e7' ],
    [ 1.5 => 'f93e00' ],
    [ 100000 => 'fa47c35000' ],
);

if (!$long_double_yn) {
    push @decode, (
        [ 1.1 => 'fb3ff199999999999a' ],
        [ _pre_522_lc('Inf') => 'fa7f800000' ],
        [ _pre_522_lc('NaN') => 'fa7fc00000' ],
        [ _pre_522_lc('-Inf') => 'faff800000' ],
    );

    if ($is_64bit) {
        push @decode, (
           [ -4.1 => 'fbc010666666666666' ],
            [ _pre_522_lc('Inf') => 'fb7ff0000000000000' ],
            [ _pre_522_lc('NaN') => 'fb7ff8000000000000' ],
            [ _pre_522_lc('-Inf') => 'fbfff0000000000000' ],
        );
    }
}

push @decode, (
    [ '2013-03-21T20:04:00Z' => 'c074323031332d30332d32315432303a30343a30305a' ],
    [ 1363896240 => 'c11a514b67b0' ],
    [ 1363896240.5 => 'c1fb41d452d9ec200000' ],
    [ "\1\2\3\4" => "4401020304" ],
    [ "\1\2\3\4" => 'd74401020304' ],
    [ 'dIETF' => 'd818456449455446' ],
    [ 'http://www.example.com' => 'd82076687474703a2f2f7777772e6578616d706c652e636f6d' ],
    [ '' => '60' ],
    [ 'a' => '6161' ],
    [ 'IETF' => '6449455446' ],
    [ q<"\\> => '62225c' ],
    [ "\x{10151}" => '64f0908591' ],
    [ { 1 => 2, 3 => 4 } => 'a201020304' ],
    [["a", {"b" => "c"}] => '826161a161626163' ],
    [ {a => 1, b => [2, 3]} => 'a26161016162820203' ],
    [ { qw( a A b B c C d D e E ) } => 'a56161614161626142616361436164614461656145' ],
    [ "\1\2\3\4\5" => '5f42010243030405ff' ],
    [ 'streaming' => '7f657374726561646d696e67ff' ],
    [ [] => '9fff' ],
    [ [ 1, [2, 3], [4, 5]] => '9f018202039f0405ffff' ],
    [ [ 1, [2, 3], [4, 5]] => '9f01820203820405ff' ],
    [ [1, [2, 3], [4, 5]] => '83018202039f0405ff' ],
    [ [1, [2, 3], [4, 5]] => '83019f0203ff820405' ],
    [ [ 1 .. 25 ] => '9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff' ],
    [ { a => 1, b => [2,3] } => 'bf61610161629f0203ffff' ],
    [ ['a', { b => 'c' }] => '826161bf61626163ff' ],
    [ { Fun => Types::Serialiser::true(), Amt => -2 } => 'bf6346756ef563416d7421ff' ],
);

for my $t (@decode) {
    my $decoded = CBOR::Free::decode( pack( 'H*', $t->[1] ) );
    is_deeply(
        $decoded,
        $t->[0],
        sprintf('Decode %s', $t->[1])
    ) or diag explain $decoded;

    my $encoded = CBOR::Free::encode( $t->[0] );

    is_deeply(
        scalar( CBOR::Free::decode( $encoded ) ),
        $t->[0],
        sprintf("Round-trip: $t->[1]"),
    );
}

done_testing;
