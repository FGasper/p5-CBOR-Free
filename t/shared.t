#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Data::Dumper;

use_ok('CBOR::Free');

my $plain_array = [];
my $plain_hash = {};

my $string = undef;
my $string_r = \$string;

my $out;

$out = CBOR::Free::encode( [ $plain_array, $plain_hash, $plain_array, $plain_hash, $string_r, $string_r ] );

use Text::Control;
#print Text::Control::to_hex($out) . $/;
printf "%v.02x\n", $out;
#$out = CBOR::Free::encode( [ $string = 'hello', $string_r ] );

done_testing;
