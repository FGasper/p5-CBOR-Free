#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;
use Test::Deep;

use parent 'Test::Class::Tiny';

use Data::Dumper;

use CBOR::Free;
use CBOR::Free::Decoder;
use CBOR::Free::SequenceDecoder;

__PACKAGE__->new()->runtests() if !caller;

sub T2_test_decoder {
    my $dec = CBOR::Free::Decoder->new();
    my $decode_cr = sub { $dec->decode($_[0]) };

    _test_shared($dec, $decode_cr);
}

sub T2_test_sequence_decoder {
    my $dec = CBOR::Free::SequenceDecoder->new();
    my $decode_cr = sub { ${ $dec->give($_[0]) } };

    _test_shared($dec, $decode_cr);
}

sub _test_shared {
    my ($dec, $decode_cr) = @_;

    my $plain_array = [];
    my $plain_hash = {};

    my $string = undef;
    my $string_r = \$string;

    my $out;

    $out = CBOR::Free::encode(
        [ $plain_array, $plain_hash, $plain_array, $plain_hash, $string_r, $string_r ],
        preserve_references => 1,
        scalar_references => 1,
    );

    $dec->preserve_references();
    my $rt = $decode_cr->($out);

    cmp_deeply(
        $rt,
        [
            [],
            {},
            shallow( $rt->[0] ),
            shallow( $rt->[1] ),
            \undef,
            shallow( $rt->[4] ),
        ],
        ref($dec) . ": references are preserved",
    );

    my $rt2 = $decode_cr->($out);

    cmp_deeply(
        $rt2,
        [
            [],
            {},
            shallow( $rt2->[0] ),
            shallow( $rt2->[1] ),
            \undef,
            shallow( $rt2->[4] ),
        ],
        ref($dec) . 'references are preserved (again with the same object)',
    );
}
