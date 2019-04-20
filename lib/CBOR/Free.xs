#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <stdlib.h>

#include <arpa/inet.h>  // for byte order conversions
#include <string.h>

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

SV *
encode( SV * value )
    CODE:
        if (!SvROK(value)) {

            if (SVt_NULL == SvTYPE(value)) {
                RETVAL = newSVpv("\xf6", 1);
            }
            //else if (0 == SvCUR(value)) {
            //    RETVAL = newSVpv("\x40", 1);
            //}
            else if (SvIOK(value)) {
                IV val = SvIV(value);

                // negative int
                if (val < 0) {
                }

                // unsigned int
                else if ( val < 0x18 ) {
                    RETVAL = newSVpv(&val, 1);
                }
                else if ( val < 256 ) {
                    char bytes[2] = { 0x18, (char) val };
                    RETVAL = newSVpv( bytes, 2);
                }
                else if ( val < 65536 ) {
                    char bytes[3] = { 0x19 };
                    uint16_t native = htons(val);

                    memcpy( 1 + bytes, &native, 2 );

                    RETVAL = newSVpv( bytes, 3);
                }
                else if ( val <= 0xffffffff ) {
                    char bytes[5] = { 0x1a };
                    uint32_t native = htonl(val);

                    memcpy( 1 + bytes, &native, 4 );

                    RETVAL = newSVpv( bytes, 5);
                }
                else {
                    // TODO: 64-bit
                }
            }
            else if (SvNOK(value)) {

                // All Perl floats are stored as doubles … apparently?
                NV val = SvNV(value);

                char *valptr = (char *) &val;

                char bytes[9] = { 0xfb, valptr[7], valptr[6], valptr[5], valptr[4], valptr[3], valptr[2], valptr[1], valptr[0] };

                RETVAL = newSVpv( bytes, 9 );
            }
            else if (SvPOK(value)) {
                STRLEN len = SvCUR(value);

                SV *retval;

                char *val = SvPV_nolen(value);

                bool encode_as_text = SvUTF8(value);
                if (!encode_as_text) {
                    STRLEN i;
                    for (i=0; i<len; i++) {
                        if (val[i] & 0x80) break;
                    }

                    // Encode as text if there were no high-bit octets.
                    encode_as_text = (i == len);
                }

                char hdrlen;

                char *bytes;

                if ( len < 0x18 ) {
                    retval = newSVpv( "", 1 + len );
                    hdrlen = 1;
                    bytes = SvPV_nolen(retval);

                    bytes[0] = (char) len;
                }
                else if ( len < 256 ) {
                    retval = newSVpv( "\x18", 2 + len );
                    hdrlen = 2;
                    bytes = SvPV_nolen(retval);

                    bytes[1] = (char) len;
                }
                else if ( len < 65536 ) {
                    retval = newSVpv( "\x19", 3 + len );
                    hdrlen = 3;
                    bytes = SvPV_nolen(retval);

                    uint16_t native = htons(val);

                    memcpy( 1 + bytes, &native, 2 );
                }
                else if ( len <= 0xffffffff ) {
                    retval = newSVpv( "\x1a", 5 + len );
                    hdrlen = 5;
                    bytes = SvPV_nolen(retval);

                    uint32_t native = htonl(val);

                    memcpy( 1 + bytes, &native, 4 );
                }
                else {
                    // TODO: 64-bit
                }

                bytes[0] = bytes[0] | (encode_as_text ? 0x60 : 0x40);

                memcpy( bytes + hdrlen, val, len );

                RETVAL = retval;
            }
            else if (SvROK(value) && SvTYPE(SvRV(value)) == SVt_PVAV) {
            }
        }
    OUTPUT:
        RETVAL
