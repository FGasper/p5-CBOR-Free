package CBOR::Free::SequenceDecoder;

use strict;
use warnings;

use CBOR::Free;

=encoding utf-8

=head1 NAME

CBOR::Free::SequenceDecoder

=head1 SYNOPSIS

    my $decoder = CBOR::Free::SequenceDecoder->new();

    if ( my $got_sr = $decoder->give( $some_cbor ) ) {

        # Do something with your decoded CBOR.
    }

    while (my $got_sr = $decoder->get()) {
        # Do something with your decoded CBOR.
    }

=head1 DESCRIPTION

This module implements a parser for CBOR Sequences
(L<RFC 8742|https://tools.ietf.org/html/rfc8742>).

=head1 METHODS

=head2 $obj = I<CLASS>->new();

Initializes a decoder.

=cut

sub new {
    my $cbor = q<>;
    my $decoder = _create_seqdecode($cbor);

    return bless [ $decoder, \$cbor ], shift;
}

=head2 $got_sr = I<CLASS>->give( $CBOR );

Adds some bytes ($CBOR) to the decoder’s internal CBOR buffer.
Returns either:

=over

=item * a B<scalar reference> to the (parsed) first CBOR document in the
internal buffer

=item * undef, if there is no such document

=back

Note that if your decoded CBOR document’s root element is already a reference
(e.g., an array or hash reference), then the return value is a reference
B<to> that reference. So, for example, if you expect all documents in your
stream to be array references, you could do:

    if ( my $got_sr = $decoder->give( $some_cbor ) ) {
        my @decoded_array = @{ $$got_sr };

        # …
    }

=cut

sub give {
    _give( $_[0][0], $_[1] );

    return $_[0]->_parse_one_wrap();
}

=head2 $got_sr = I<CLASS>->get();

Like C<give()> but doesn’t append onto the internal CBOR buffer.

=cut

sub get {
    return $_[0]->_parse_one_wrap();
}

#----------------------------------------------------------------------

sub _parse_one_wrap {
    my $got;

    my $ok = eval {
        $got = _parse_one( $_[0][0] );
        1;
    };

    if (!$ok) {
        my $err = $@;

        return undef if eval { $err->isa('CBOR::Free::X::Incomplete') };

        local $@ = $err;
        die;
    }

    return \$got;
}

sub DESTROY {
    my ($self) = @_;

    _free_seqdecode($self->[0]);
}

1;
