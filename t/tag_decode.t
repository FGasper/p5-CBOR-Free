#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;
use Test::FailWarnings;

use CBOR::Free::Decoder;

my $decoder = CBOR::Free::Decoder->new()->set_tag_handlers(
    1 => sub { 42 + shift() },
);

my $decoded = $decoder->decode( "\xc1\1" );
is( $decoded, 43, 'single callback OK' );

my @w;
$decoded = do {
    local $SIG{'__WARN__'} = sub { push @w, @_ };
    $decoder->decode( "\xcb\x80" );
};

cmp_deeply(
    \@w,
    [ all(
        re(qr<11>),         # tag number
        re(qr<4>),          # major type
        re( qr<array> ),    # major type label
    ) ],
    'warning about unrecognized tag',
);

is_deeply($decoded, [], '… and the value is correct' );

done_testing();
