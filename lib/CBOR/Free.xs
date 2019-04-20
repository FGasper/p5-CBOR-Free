#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <stdio.h>
#include <stdlib.h>

#include <arpa/inet.h>  // for byte order conversions
#include <string.h>

 // TODO: Define as a macro
void _grow_sv( SV *sv, STRLEN delta ) {
    SvGROW( sv, delta + SvCUR(sv) );
}

SV *_encode( SV *value, SV *buffer ) {
    SV *RETVAL;

    if (buffer) RETVAL = buffer;

    if (!SvROK(value)) {
printf("encoding nonref\n");

        if (SVt_NULL == SvTYPE(value)) {
printf("it’s a null\n");
            if (buffer) {
                sv_catpvn( buffer, "\xf6", 1 );
            }
            else {
                RETVAL = newSVpv("\xf6", 1);
            }
        }
        //else if (0 == SvCUR(value)) {
        //    RETVAL = newSVpv("\x40", 1);
        //}
        else if (SvIOK(value)) {
            IV val = SvIV(value);

            // TODO: negative int
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
                RETVAL = newSVpv( "", 1 + len );
                hdrlen = 1;
                bytes = SvPV_nolen(RETVAL);

                bytes[0] = (char) len;
            }
            else if ( len < 256 ) {
                RETVAL = newSVpv( "\x18", 2 + len );
                hdrlen = 2;
                bytes = SvPV_nolen(RETVAL);

                bytes[1] = (char) len;
            }
            else if ( len < 65536 ) {
                RETVAL = newSVpv( "\x19", 3 + len );
                hdrlen = 3;
                bytes = SvPV_nolen(RETVAL);

                uint16_t native = htons(val);

                memcpy( 1 + bytes, &native, 2 );
            }
            else if ( len <= 0xffffffff ) {
                RETVAL = newSVpv( "\x1a", 5 + len );
                hdrlen = 5;
                bytes = SvPV_nolen(RETVAL);

                uint32_t native = htonl(val);

                memcpy( 1 + bytes, &native, 4 );
            }
            else {
                // TODO: 64-bit
            }

            bytes[0] = bytes[0] | (encode_as_text ? 0x60 : 0x40);

            memcpy( bytes + hdrlen, val, len );
        }
    }
    else {
        if (SVt_PVAV == SvTYPE(SvRV(value))) {
            SSize_t len;
            len = 1 + av_top_index(SvRV(value));

            STRLEN bufoffset = buffer ? SvCUR(buffer) : 0;

            char *bytes;

            if ( len < 0x18 ) {
                if (buffer) {
                    _grow_sv( buffer, 1 );
                }
                else {
                    RETVAL = newSVpv( "", 1 );
                }

                bytes = bufoffset + SvPV_nolen(RETVAL);

                bytes[0] = (char) len;
            }
            else if ( len < 256 ) {
                if (buffer) {
                    _grow_sv( buffer, 2 );
                }
                else {
                    RETVAL = newSVpv( "", 2 );
                }

                bytes = bufoffset + SvPV_nolen(RETVAL);

                bytes[0] = 0x18;
                bytes[1] = (char) len;
            }
            else if ( len < 65536 ) {
                if (buffer) {
                    _grow_sv( buffer, 3 );
                }
                else {
                    RETVAL = newSVpv( "", 3 );
                }

                bytes = bufoffset + SvPV_nolen(RETVAL);

                bytes[0] = 0x19;

                uint16_t native = htons(len);

                memcpy( 1 + bytes, &native, 2 );
            }
            else if ( len <= 0xffffffff ) {
                if (buffer) {
                    _grow_sv( buffer, 5 );
                }
                else {
                    RETVAL = newSVpv( "", 5 );
                }

                bytes = bufoffset + SvPV_nolen(RETVAL);

                bytes[0] = 0x1a;

                uint32_t native = htonl(len);

                memcpy( 1 + bytes, &native, 4 );
            }

            bytes[0] = bytes[0] | 0x80;

            SSize_t i;

printf("array len: %d\n", len);
            for (i=0; i<len; i++) {
                _encode( *av_fetch(value, i, 0), RETVAL );
            }
        }
        else {
            // TODO: fail unrecognized
        }
    }

    return RETVAL;
}

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

SV *
encode( SV * value )
    CODE:
        RETVAL = _encode(value, NULL);
    OUTPUT:
        RETVAL
