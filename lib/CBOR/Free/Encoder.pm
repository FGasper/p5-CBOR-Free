package CBOR::Free::Encoder;

use strict;
use warnings;

#----------------------------------------------------------------------

use CBOR::Free ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Creates a new CBOR encoder object.

=cut

sub new { bless {} }    # TODO: implement in XS, and store a context.

#----------------------------------------------------------------------

=head2 I<OBJ>->preserve_references( [$ENABLE] )

Tells CBOR::Free to use L<CBOR’s “shared value” tags|https://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml> to encode references. This preserves data
structures at the reference level so that you can serialize structures like:

    my $hr = { foo => 1 };
    my $struct = [ $hr, $hr ];

… and allow a compatible CBOR decoder to create a structure that preserves
referential relationships—e.g., in the above case, the two elements of the
array are the B<same> hash.

Perhaps more significantly, this allows self-referential structures, like:

    my $struct = [];
    push @$struct, $struct;

… which CBOR ordinarily cannot encode.

This method follows the same pattern as L<IO::Handle>’s C<autoflush()>:
if given no arguments, the option is enabled; otherwise, the given
argument is interpreted as a boolean to enable or disable the option.

=cut

sub preserve_references {
    return $_[0]{'_preserve_references'} = (@_ > 1 ? !!$_[1] : 1);
}

1;
