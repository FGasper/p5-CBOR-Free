#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Data::Dumper;

use_ok('CBOR::Free');

my $plain_array = [];

my $string;
my $string_r = \$string;

my $out;

$out = CBOR::Free::encode( [ $plain_array, $plain_array ] );

use Text::Control;
print Text::Control::to_hex($out) . $/;
#$out = CBOR::Free::encode( [ $string = 'hello', $string_r ] );

done_testing;
