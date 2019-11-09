#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Data::Dumper;

use_ok('CBOR::Free');

use CBOR::Free::Decoder;

my $plain_array = [];
my $plain_hash = {};

my $string = undef;
my $string_r = \$string;

my $out;

$out = CBOR::Free::encode(
    [ $plain_array, $plain_hash, $plain_array, $plain_hash, $string_r, $string_r ],
    preserve_references => 1,
);

use Text::Control;
#print Text::Control::to_hex($out) . $/;
printf "%v.02x\n", $out;
#$out = CBOR::Free::encode( [ $string = 'hello', $string_r ] );

my $dec = CBOR::Free::Decoder->new();
$dec->preserve_references();
my $rt = $dec->decode($out);

use Devel::Peek;
Dump($rt);

use Data::Dumper;
$Data::Dumper::Useqq = 1;
print Dumper($rt);

done_testing;
