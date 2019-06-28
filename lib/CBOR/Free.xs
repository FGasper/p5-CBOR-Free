#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

//#include <stdio.h>
#include <stdbool.h>

#include "cbor_free_common.h"

#include "cbor_free_boolean.h"
#include "cbor_free_encode.h"
#include "cbor_free_decode.h"

//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    HV *stash = gv_stashpv("CBOR::Free", FALSE);
    newCONSTSUB(stash, "_MAX_RECURSION", newSVuv( MAX_ENCODE_RECURSE ));

SV *
encode( SV * value, ... )
    CODE:
        encode_ctx encode_state[1];

        encode_state->buffer = NULL;
        Newx( encode_state->buffer, ENCODE_ALLOC_CHUNK_SIZE, char );

        encode_state->buflen = ENCODE_ALLOC_CHUNK_SIZE;
        encode_state->len = 0;
        encode_state->recurse_count = 0;

        encode_state->is_canonical = false;

        U8 i;
        for (i=1; i<items; i++) {
            if (!(i % 2)) break;

            if ((SvCUR(ST(i)) == 9) && !memcmp( SvPV_nolen(ST(i)), "canonical", 9)) {
                ++i;
                if (i<items) encode_state->is_canonical = SvTRUE(ST(i));
                break;
            }
        }

        RETVAL = newSV(0);

        cbf_encode(aTHX_ value, encode_state, RETVAL);

        // Don’t use newSVpvn here because that will copy the string.
        // Instead, create a new SV and manually assign its pieces.
        // This follows the example from ext/POSIX/POSIX.xs:

        SvUPGRADE(RETVAL, SVt_PV);
        SvPV_set(RETVAL, encode_state->buffer);
        SvPOK_on(RETVAL);
        SvCUR_set(RETVAL, encode_state->len - 1);
        SvLEN_set(RETVAL, encode_state->buflen);

    OUTPUT:
        RETVAL


SV *
decode( SV *cbor )
    CODE:
        char *cborstr;
        STRLEN cborlen;

        cborstr = SvPV(cbor, cborlen);

        decode_ctx decode_state = {
            cborstr,
            cborlen,
            cborstr,
            cborstr + cborlen,
        };

        RETVAL = cbf_decode( aTHX_ &decode_state );

    OUTPUT:
        RETVAL
