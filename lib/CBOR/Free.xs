#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

//#include <stdio.h>
#include <stdbool.h>
#include <string.h>

#include "cbor_free_common.h"

#include "cbor_free_boolean.h"
#include "cbor_free_encode.h"
#include "cbor_free_decode.h"

#define _PACKAGE "CBOR::Free"

HV *cbf_stash = NULL;

//SV *
//new( const char *class )
//    CODE:
//        HV * rh = newHV();
//
//        SV * rhref = newRV_noinc( (SV *) rh );
//
//        HV *bless_into;
//
//        if (strcmp(class, _PACKAGE)) {
//            HV *bless_into = gv_stashpv(_PACKAGE, TRUE);
//        }
//        else {
//            bless_into = cbf_stash;
//        }
//
//        RETVAL = sv_bless( rhref, bless_into );
//    OUTPUT:
//       RETVAL
//

//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    cbf_stash = gv_stashpv(_PACKAGE, FALSE);
    newCONSTSUB(cbf_stash, "_MAX_RECURSION", newSVuv( MAX_ENCODE_RECURSE ));


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
            NULL,
        };

        RETVAL = cbf_decode( aTHX_ &decode_state );

    OUTPUT:
        RETVAL

MODULE = CBOR::Free     PACKAGE = CBOR::Free::Decoder

PROTOTYPES: DISABLE

SV *
decode( SV *selfref, SV *cbor )
    CODE:
//sv_dump(selfref);
        HV *self = (HV *)SvRV(selfref);
fprintf(stderr, "one\n");

        SV **tag_handler_hr = hv_fetchs(self, "_tag_handler", 0);
fprintf(stderr, "one %llu\n", tag_handler_hr);

        SV *tag_handler = tag_handler_hr ? *tag_handler_hr : NULL;
fprintf(stderr, "one %llu\n", tag_handler);

        if (tag_handler && !SvOK(tag_handler)) {
fprintf(stderr, "null\n");
            tag_handler = NULL;
        }
//sv_dump(tag_handler);
fprintf(stderr, "SVt_PVHV %u\n", SVt_PVHV);
fprintf(stderr, "type: %llu\n", SvTYPE(SvRV(tag_handler)));

        STRLEN cborlen;

        char *cborstr = SvPV(cbor, cborlen);

        decode_ctx decode_state = {
            cborstr,
            cborlen,
            cborstr,
            cborstr + cborlen,
            tag_handler ? (HV *)SvRV(tag_handler) : NULL,
        };

    //fprintf(stderr, "tag handler hv %llu\n", tag_handler_hv);
    //fprintf(stderr, "tag handler in struct %llu\n", decode_state.tag_handler);

        RETVAL = cbf_decode( aTHX_ &decode_state );

    OUTPUT:
        RETVAL
