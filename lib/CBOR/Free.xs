#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

#define TYPE_UINT   0
#define TYPE_NEGINT 0x20
#define TYPE_BINARY 0x40
#define TYPE_UTF8   0x60
#define TYPE_ARRAY  0x80
#define TYPE_MAP    0xa0
#define TYPE_TAG    0xc0
#define TYPE_OTHER  0xe0

#define TYPE_NEGINT_SMALL  (0x18 + TYPE_NEGINT)
#define TYPE_NEGINT_MEDIUM (0x19 + TYPE_NEGINT)
#define TYPE_NEGINT_LARGE  (0x1a + TYPE_NEGINT)
#define TYPE_NEGINT_HUGE   (0x1b + TYPE_NEGINT)

#define CBOR_HALF_FLOAT 0xf9
#define CBOR_FLOAT      0xfa
#define CBOR_DOUBLE     0xfb

#define CBOR_FALSE      0xf4
#define CBOR_TRUE       0xf5
#define CBOR_NULL       0xf6
#define CBOR_UNDEFINED  0xf7

#define BOOLEAN_CLASS   "Types::Serialiser::Boolean"
#define TAGGED_CLASS    "CBOR::Free::Tagged"

#define MAX_ENCODE_RECURSE 98

#define IS_LITTLE_ENDIAN (BYTEORDER == 0x1234 || BYTEORDER == 0x12345678)
#define IS_64_BIT        (BYTEORDER > 0x10000)

//----------------------------------------------------------------------
// Definitions

typedef struct {
    char *buffer;
    STRLEN len;
    uint8_t recurse_count;
    uint8_t scratch[9];
    bool is_canonical;
} encode_ctx;

typedef struct {
    char* start;
    STRLEN size;
    char* curbyte;
    char* end;
    bool is_map_key;

    union {
        uint8_t bytes[8];
        float as_float;
        double as_double;
    } float_bytes;
} decode_ctx;

enum enum_sizetype {
    //tiny = 0,
    small = 1,
    medium = 2,
    large = 4,
    huge = 8,
    indefinite = 255,
};

union anyint {
    uint8_t u8;
    uint16_t u16;
    uint32_t u32;
    uint64_t u64;
};

typedef struct {
    enum enum_sizetype sizetype;
    union anyint size;
} struct_sizeparse;

//----------------------------------------------------------------------
// Prototypes
// TODO: Be C99-compliant.

SV *_decode( pTHX_ decode_ctx* decstate );

//----------------------------------------------------------------------

void _void_uint_to_str(STRLEN num, char *numstr, const char strlen) {
    my_snprintf(numstr, strlen, "%lu", num);
}

#define _croak croak

void _die( pTHX_ I32 flags, char **argv ) {
    call_argv( "CBOR::Free::_die", G_EVAL | flags, argv );

    _croak(NULL);
}

void _croak_unrecognized(pTHX_ SV *value) {
    char * words[3] = { "Unrecognized", SvPV_nolen(value), NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_incomplete( pTHX_ STRLEN lack ) {
    char lackstr[24];
    _void_uint_to_str( lack, lackstr, 24 );

    char * words[3] = { "Incomplete", lackstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_invalid_control( pTHX_ decode_ctx* decstate ) {
    const uint8_t ord = (uint8_t) *(decstate->curbyte);
    STRLEN offset = decstate->curbyte - decstate->start;

    char ordstr[24];
    char offsetstr[24];

    _void_uint_to_str(ord, ordstr, 24);
    _void_uint_to_str(offset, offsetstr, 24);

    char * words[] = { "InvalidControl", ordstr, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_invalid_utf8( pTHX_ char *string ) {
    char * words[3] = { "InvalidUTF8", string, NULL };

    _die( aTHX_ G_DISCARD, words);
}

void _croak_invalid_map_key( pTHX_ const char *key, STRLEN offset ) {


    char offsetstr[20];
    my_snprintf( offsetstr, 20, "%lu", offset );

    char * words[] = { "InvalidMapKey", (char *) key, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words);
}

void _croak_cannot_decode_64bit( pTHX_ const uint8_t *u64bytes, STRLEN offset ) {
    char numhex[20];
    numhex[19] = 0;

    my_snprintf( numhex, 20, "%02x%02x_%02x%02x_%02x%02x_%02x%02x", u64bytes[0], u64bytes[1], u64bytes[2], u64bytes[3], u64bytes[4], u64bytes[5], u64bytes[6], u64bytes[7] );

    char offsetstr[20];
    my_snprintf( offsetstr, 20, "%lu", offset );

    char * words[] = { "CannotDecode64Bit", numhex, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_cannot_decode_negative( pTHX_ UV abs, STRLEN offset ) {
    char absstr[40];
    my_snprintf(absstr, 40, sizeof(abs) == 4 ? "%lu" : "%llu", abs);

    char offsetstr[20];
    my_snprintf( offsetstr, 20, "%lu", offset );

    char * words[] = { "NegativeIntTooLow", absstr, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

#define _DECODE_CHECK_FOR_OVERAGE( decstate, len) \
    if ((len + decstate->curbyte) > decstate->end) { \
        _croak_incomplete( aTHX_ (len + decstate->curbyte) - decstate->end ); \
    }


//----------------------------------------------------------------------

static inline void _COPY_INTO_ENCODE( encode_ctx *encode_state, void *hdr, STRLEN len) {
    Renew( encode_state->buffer, len + encode_state->len, char );
    Copy( hdr, encode_state->buffer + encode_state->len, len, char );
    encode_state->len += len;
}

//----------------------------------------------------------------------

// These encode num as big-endian into buffer.
// Importantly, on big-endian systems this is just a memcpy.

static inline void _u16_to_buffer( UV num, uint8_t *buffer ) {
    buffer[0] = num >> 8;
    buffer[1] = num;
}

static inline void _u32_to_buffer( UV num, unsigned char *buffer ) {
    buffer[0]       = num >> 24;
    buffer[1] = num >> 16;
    buffer[2] = num >> 8;
    buffer[3] = num;
}

static inline void _u64_to_buffer( UV num, unsigned char *buffer ) {
    buffer[0] = num >> 56;
    buffer[1] = num >> 48;
    buffer[2] = num >> 40;
    buffer[3] = num >> 32;
    buffer[4] = num >> 24;
    buffer[5] = num >> 16;
    buffer[6] = num >> 8;
    buffer[7] = num;
}

//----------------------------------------------------------------------

// NOTE: Contrary to what we’d ordinarily expect, for canonical CBOR
// keys are only byte-sorted if their lengths are identical. Thus,
// “z” sorts EARLIER than “aa”. (cf. section 3.9 of the RFC)
I32 sortstring( pTHX_ SV *a, SV *b ) {
    return (SvCUR(a) < SvCUR(b)) ? -1 : (SvCUR(a) > SvCUR(b)) ? 1 : memcmp( SvPV_nolen(a), SvPV_nolen(b), SvCUR(a) );
}

//----------------------------------------------------------------------

// TODO? This could be a macro … it’d just be kind of unwieldy as such.
static inline void _init_length_buffer( pTHX_ UV num, const uint8_t type, encode_ctx *encode_state ) {
    if ( num < 0x18 ) {
        encode_state->scratch[0] = type + (uint8_t) num;

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 1);
    }
    else if ( num <= 0xff ) {
        encode_state->scratch[0] = type + 0x18;
        encode_state->scratch[1] = (uint8_t) num;

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 2);
    }
    else if ( num <= 0xffff ) {
        encode_state->scratch[0] = type + 0x19;

        _u16_to_buffer( num, 1 + encode_state->scratch );

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 3);
    }
    else if ( num <= 0xffffffff ) {
        encode_state->scratch[0] = type + 0x1a;

        _u32_to_buffer( num, 1 + encode_state->scratch );

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 5);
    }
    else {
        encode_state->scratch[0] = type + 0x1b;

        _u64_to_buffer( num, 1 + encode_state->scratch );

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 9);
    }
}

static inline void _init_length_buffer_negint( pTHX_ IV num, encode_ctx *encode_state ) {
    if ( (UV) -num <= 0x18 ) {
        encode_state->scratch[0] = TYPE_NEGINT + (uint8_t) -num - 1;

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 1);
    }
    else {
        num++;
        num = -num;

        if ( num <= 0xff ) {
            encode_state->scratch[0] = TYPE_NEGINT_SMALL;
            encode_state->scratch[1] = (uint8_t) num;

            _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 2);
        }
        else if ( num <= 0xffff ) {
            encode_state->scratch[0] = TYPE_NEGINT_MEDIUM;

            _u16_to_buffer( num, 1 + encode_state->scratch );

            _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 3);
        }
        else if ( num <= 0xffffffff ) {
            encode_state->scratch[0] = TYPE_NEGINT_LARGE;

            _u32_to_buffer( num, 1 + encode_state->scratch );

            _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 5);
        }
        else {
            encode_state->scratch[0] = TYPE_NEGINT_HUGE;

            _u64_to_buffer( num, 1 + encode_state->scratch );

            _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 9);
        }
    }
}

void _encode( pTHX_ SV *value, encode_ctx *encode_state ) {
    ++encode_state->recurse_count;
    if (encode_state->recurse_count > MAX_ENCODE_RECURSE) {

        // call_pv() killed the process in Win32; this seems to fix that.
        static char * words[] = { NULL };
        call_argv("CBOR::Free::_die_recursion", G_EVAL|G_DISCARD, words);

        _croak(NULL);
    }

    if (!SvROK(value)) {

        if (!SvOK(value)) {
            char null = CBOR_NULL;
            _COPY_INTO_ENCODE(encode_state, &null, 1);
        }
        else if (SvIOK(value)) {
            IV val = SvIVX(value);

            // In testing, Perl’s (0 + ~0) evaluated as < 0 here,
            // but the SvUOK() check fixes that.
            if (val < 0 && !SvUOK(value)) {
                _init_length_buffer_negint( aTHX_ val, encode_state );
            }
            else {
                // NB: SvUOK doesn’t work to identify nonnegatives … ?
                _init_length_buffer( aTHX_ val, TYPE_UINT, encode_state );
            }
        }
        else if (SvNOK(value)) {

            // Typecast to a double to accommodate long-double perls.
            double val = (double) SvNV(value);

            char *valptr = (char *) &val;

#if IS_LITTLE_ENDIAN
            encode_state->scratch[0] = CBOR_DOUBLE;
            encode_state->scratch[1] = valptr[7];
            encode_state->scratch[2] = valptr[6];
            encode_state->scratch[3] = valptr[5];
            encode_state->scratch[4] = valptr[4];
            encode_state->scratch[5] = valptr[3];
            encode_state->scratch[6] = valptr[2];
            encode_state->scratch[7] = valptr[1];
            encode_state->scratch[8] = valptr[0];

            _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 9);
#else
            char bytes[9] = { CBOR_DOUBLE, valptr[0], valptr[1], valptr[2], valptr[3], valptr[4], valptr[5], valptr[6], valptr[7] };
            _COPY_INTO_ENCODE(encode_state, bytes, 9);
#endif
        }
        else {
            STRLEN len = SvCUR(value);

            char *val = SvPV_nolen(value);

            bool encode_as_text = !!SvUTF8(value);

            /*
            if (!encode_as_text) {
                STRLEN i;
                for (i=0; i<len; i++) {
                    if (val[i] & 0x80) break;
                }

                // Encode as text if there were no high-bit octets.
                encode_as_text = (i == len);
            }
            */

            _init_length_buffer( aTHX_
                len,
                (encode_as_text ? TYPE_UTF8 : TYPE_BINARY),
                encode_state
            );

            _COPY_INTO_ENCODE( encode_state, val, len );
        }
    }
    else if (sv_isobject(value)) {
        if (sv_derived_from(value, BOOLEAN_CLASS)) {
            char newbyte = SvIV(SvRV(value)) ? CBOR_TRUE : CBOR_FALSE;

            _COPY_INTO_ENCODE( encode_state, &newbyte, 1 );
        }
        else if (sv_derived_from(value, TAGGED_CLASS)) {
            AV *array = (AV *)SvRV(value);
            SV **tag = av_fetch(array, 0, 0);
            IV tagnum = SvIV(*tag);

            _init_length_buffer( aTHX_ tagnum, TYPE_TAG, encode_state );
            _encode( aTHX_ *(av_fetch(array, 1, 0)), encode_state );
        }

        // TODO: Support TO_JSON() method?

        else {
            _croak_unrecognized(aTHX_ value);
        }
    }
    else {
        if (SVt_PVAV == SvTYPE(SvRV(value))) {
            AV *array = (AV *)SvRV(value);
            SSize_t len;
            len = 1 + av_len(array);

            _init_length_buffer( aTHX_ len, TYPE_ARRAY, encode_state );

            SSize_t i;

            SV **cur;
            for (i=0; i<len; i++) {
                cur = av_fetch(array, i, 0);
                _encode( aTHX_ *cur, encode_state );
            }
        }
        else if (SVt_PVHV == SvTYPE(SvRV(value))) {
            HV *hash = (HV *)SvRV(value);

            char *key;
            I32 key_length;
            SV *cur;

            I32 keyscount = hv_iterinit(hash);

            _init_length_buffer( aTHX_ keyscount, TYPE_MAP, encode_state );

            if (encode_state->is_canonical) {
                SV *keys[keyscount];

                I32 curkey = 0;

                while (hv_iternextsv(hash, &key, &key_length)) {
                    keys[curkey] = newSVpvn(key, key_length);
                    ++curkey;
                }

                sortsv(keys, keyscount, sortstring);

                for (curkey=0; curkey < keyscount; ++curkey) {
                    cur = keys[curkey];
                    key = SvPV_nolen(cur);
                    key_length = SvCUR(cur);

                    // Store the key.
                    _init_length_buffer( aTHX_ key_length, TYPE_BINARY, encode_state );
                    _COPY_INTO_ENCODE( encode_state, key, key_length );

                    cur = *( hv_fetch(hash, key, key_length, 0) );

                    _encode( aTHX_ cur, encode_state );
                }
            }
            else {
                while ((cur = hv_iternextsv(hash, &key, &key_length))) {

                    // Store the key.
                    _init_length_buffer( aTHX_ key_length, TYPE_BINARY, encode_state );

                    _COPY_INTO_ENCODE( encode_state, key, key_length );

                    _encode( aTHX_ cur, encode_state );
                }
            }
        }
        else {
            _croak_unrecognized(aTHX_ value);
        }
    }

    --encode_state->recurse_count;
}

//----------------------------------------------------------------------

// NB: We already checked that curbyte is safe to read!
struct_sizeparse _parse_for_uint_len( pTHX_ decode_ctx* decstate ) {
    struct_sizeparse ret;

    switch (*(decstate->curbyte) & 0x1f) {  // 0x1f == 0b00011111
        case 0x18:

            _DECODE_CHECK_FOR_OVERAGE( decstate, 2);

            ++decstate->curbyte;

            ret.sizetype = small;
            ret.size.u8 = *decstate->curbyte;

            ++decstate->curbyte;

            break;

        case 0x19:
            _DECODE_CHECK_FOR_OVERAGE( decstate, 3);

            ++decstate->curbyte;

            ret.sizetype = medium;
            _u16_to_buffer( *((uint16_t *) decstate->curbyte), (uint8_t *) &(ret.size.u16) );

            decstate->curbyte += 2;

            break;

        case 0x1a:
            _DECODE_CHECK_FOR_OVERAGE( decstate, 5);

            ++decstate->curbyte;

            ret.sizetype = large;
            _u32_to_buffer( *((uint32_t *) decstate->curbyte), (uint8_t *) &(ret.size.u32) );

            decstate->curbyte += 4;

            break;

        case 0x1b:
            _DECODE_CHECK_FOR_OVERAGE( decstate, 9);

            ++decstate->curbyte;

#if IS_64_BIT
            ret.sizetype = huge;
            _u64_to_buffer( *((uint64_t *) decstate->curbyte), (uint8_t *) &(ret.size.u64) );
#else
            if (!decstate->curbyte[0] && !decstate->curbyte[1] && !decstate->curbyte[2] && !decstate->curbyte[3]) {
                ret.sizetype = large;
                _u32_to_buffer( *((uint32_t *) (4 + decstate->curbyte)), (uint8_t *) &(ret.size.u32) );
            }
            else {
                _croak_cannot_decode_64bit( aTHX_ (const uint8_t *) decstate->curbyte, decstate->curbyte - decstate->start );
            }
#endif

            decstate->curbyte += 8;

            break;

        case 0x1c:
        case 0x1d:
        case 0x1e:
            _croak_invalid_control( aTHX_ decstate );
            break;

        case 0x1f:
            // ++decstate->curbyte;
            // NOTE: We do NOT increment the pointer here
            // because callers need to distinguish for themselves
            // whether indefinite is a valid case.

            ret.sizetype = indefinite;

            break;

        default:
            ret.sizetype = small;
            ret.size.u8 = (uint8_t) (*(decstate->curbyte) & 0x1f);

            decstate->curbyte++;

            break;
    }

    return ret;
}

//----------------------------------------------------------------------

SV *_decode_array( pTHX_ decode_ctx* decstate ) {
    SSize_t array_length;

    AV *array = NULL;
    SV *cur = NULL;

    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            array_length = sizeparse.size.u8;
            break;

        case medium:
            array_length = sizeparse.size.u16;
            break;

        case large:
            array_length = sizeparse.size.u32;
            break;

        case huge:
            array_length = sizeparse.size.u64;
            break;

        case indefinite:
            ++decstate->curbyte;

            array = newAV();

            while (*(decstate->curbyte) != '\xff') {

                cur = _decode( aTHX_ decstate );
                av_push(array, cur);
                //sv_2mortal(cur);
            }

            _DECODE_CHECK_FOR_OVERAGE( decstate, 1 );

            ++decstate->curbyte;
    }

    if (!array) {
        array = newAV();

        if (array_length) {
            av_fill(array, array_length - 1);

            SSize_t i;
            for (i=0; i<array_length; i++) {
                cur = _decode( aTHX_ decstate );

                if (!av_store(array, i, cur)) {
                    _croak("Failed to store item in array!");
                }
            }
        }
    }

    return newRV_noinc( (SV *) array);
}

//----------------------------------------------------------------------

void _decode_to_hash( pTHX_ decode_ctx* decstate, HV *hash ) {
    decstate->is_map_key = true;
    SV *curkey = _decode( aTHX_ decstate );
    decstate->is_map_key = false;

    SV *curval = _decode( aTHX_ decstate );

    // This is going to be a hash key, so it can’t usefully be
    // anything but a string/PV.
    STRLEN keylen;
    char *keystr = SvPV_force(curkey, keylen);

    hv_store(hash, keystr, keylen, curval, 0);
    sv_2mortal(curkey);
}

SV *_decode_map( pTHX_ decode_ctx* decstate ) {
    SSize_t keycount = 0;

    HV *hash = newHV();

    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            keycount = sizeparse.size.u8;
            break;

        case medium:
            keycount = sizeparse.size.u16;
            break;

        case large:
            keycount = sizeparse.size.u32;
            break;

        case huge:
            keycount = sizeparse.size.u64;
            break;

        case indefinite:
            ++decstate->curbyte;

            while (*(decstate->curbyte) != '\xff') {
                _decode_to_hash( aTHX_ decstate, hash );
            }

            _DECODE_CHECK_FOR_OVERAGE( decstate, 1 );

            ++decstate->curbyte;
    }

    if (keycount) {
        while (keycount > 0) {
            _decode_to_hash( aTHX_ decstate, hash );
            --keycount;
        }
    }

    return newRV_noinc( (SV *) hash);
}

//----------------------------------------------------------------------

// Taken from RFC 7049:
double decode_half_float(uint8_t *halfp) {
    int half = (halfp[0] << 8) + halfp[1];
    int exp = (half >> 10) & 0x1f;
    int mant = half & 0x3ff;
    double val;
    if (exp == 0) val = ldexp(mant, -24);
    else if (exp != 31) val = ldexp(mant + 1024, exp - 25);
    else val = mant == 0 ? INFINITY : NAN;
    return half & 0x8000 ? -val : val;
}

static inline float _decode_float_to_le( decode_ctx* decstate, uint8_t *ptr ) {
    decstate->float_bytes.bytes[0] = ptr[3];
    decstate->float_bytes.bytes[1] = ptr[2];
    decstate->float_bytes.bytes[2] = ptr[1];
    decstate->float_bytes.bytes[3] = ptr[0];

    return decstate->float_bytes.as_float;
}

static inline double _decode_double_to_le( decode_ctx* decstate, uint8_t *ptr ) {
    decstate->float_bytes.bytes[0] = ptr[7];
    decstate->float_bytes.bytes[1] = ptr[6];
    decstate->float_bytes.bytes[2] = ptr[5];
    decstate->float_bytes.bytes[3] = ptr[4];
    decstate->float_bytes.bytes[4] = ptr[3];
    decstate->float_bytes.bytes[5] = ptr[2];
    decstate->float_bytes.bytes[6] = ptr[1];
    decstate->float_bytes.bytes[7] = ptr[0];

    return decstate->float_bytes.as_double;
}

//----------------------------------------------------------------------

SV *_decode( pTHX_ decode_ctx* decstate ) {
    SV *ret = NULL;

    _DECODE_CHECK_FOR_OVERAGE( decstate, 1);

    struct_sizeparse sizeparse;

    uint8_t major_type = *(decstate->curbyte) & 0xe0;

    switch (major_type) {
        case TYPE_UINT:
            sizeparse = _parse_for_uint_len( aTHX_ decstate );
            switch (sizeparse.sizetype) {
                //case tiny:
                case small:
                    ret = newSVuv( sizeparse.size.u8 );
                    break;

                case medium:
                    ret = newSVuv( sizeparse.size.u16 );
                    break;

                case large:
                    ret = newSVuv( sizeparse.size.u32 );
                    break;

                case huge:
                    ret = newSVuv( sizeparse.size.u64 );
                    break;

                default:
                    _croak_invalid_control( aTHX_ decstate );
                    break;

            }

            break;
        case TYPE_NEGINT:
            sizeparse = _parse_for_uint_len( aTHX_ decstate );

            switch (sizeparse.sizetype) {
                //case tiny:
                case small:
                    ret = newSViv( -1 - sizeparse.size.u8 );
                    break;

                case medium:
                    ret = newSViv( -1 - sizeparse.size.u16 );
                    break;

                case large:
#if !IS_64_BIT
                    if (sizeparse.size.u32 >= 0x80000000U) {
                        _croak_cannot_decode_negative( aTHX_ 1 + sizeparse.size.u32, decstate->curbyte - decstate->start - 4 );
                    }
#endif

                    ret = newSViv( ( (int64_t) sizeparse.size.u32 ) * -1 - 1 );
                    break;

                case huge:
                    if (sizeparse.size.u64 >= 0x8000000000000000U) {
                        _croak_cannot_decode_negative( aTHX_ 1 + sizeparse.size.u64, decstate->curbyte - decstate->start - 8 );
                    }

                    ret = newSViv( ( (int64_t) sizeparse.size.u64 ) * -1 - 1 );
                    break;

                default:
                    _croak_invalid_control( aTHX_ decstate );
                    break;

            }

            break;
        case TYPE_BINARY:
        case TYPE_UTF8:
            sizeparse = _parse_for_uint_len( aTHX_ decstate );

            switch (sizeparse.sizetype) {
                //case tiny:
                case small:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, sizeparse.size.u8);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u8 );
                    decstate->curbyte += sizeparse.size.u8;

                    break;

                case medium:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, sizeparse.size.u16);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u16 );
                    decstate->curbyte += sizeparse.size.u16;

                    break;

                case large:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, sizeparse.size.u32);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u32 );
                    decstate->curbyte += sizeparse.size.u32;

                    break;

                case huge:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, sizeparse.size.u64);
                    ret = newSVpvn( decstate->curbyte, sizeparse.size.u64 );
                    decstate->curbyte += sizeparse.size.u64;
                    break;

                case indefinite:
                    ++decstate->curbyte;

                    ret = newSVpvs("");

                    while (*(decstate->curbyte) != '\xff') {
                        //TODO: Require the same major type.

                        SV *cur = _decode( aTHX_ decstate );

                        sv_catsv(ret, cur);
                    }

                    _DECODE_CHECK_FOR_OVERAGE( decstate, 1 );

                    ++decstate->curbyte;

                    break;

                default:

                    // This shouldn’t happen, but just in case.
                    _croak("Unknown string length descriptor!");
            }

            // XXX: “perldoc perlapi” says this function is experimental.
            // Its use here is a calculated risk; the alternatives are
            // to invoke utf8::decode() via call_pv(), which is ugly,
            // or just to assume the UTF-8 is valid, which is wrong.
            //
            if (TYPE_UTF8 == major_type) {
                if ( !sv_utf8_decode(ret) ) {
                    _croak_invalid_utf8( aTHX_ SvPV_nolen(ret) );
                }
            }

            break;
        case TYPE_ARRAY:
            ret = _decode_array( aTHX_ decstate );

            break;
        case TYPE_MAP:
            ret = _decode_map( aTHX_ decstate );

            break;
        case TYPE_TAG:

            // For now, just throw this tag value away.
            sizeparse = _parse_for_uint_len( aTHX_ decstate );
            if (sizeparse.sizetype == indefinite) {
                _croak_invalid_control( aTHX_ decstate );
            }

            ret = _decode( aTHX_ decstate );

            break;
        case TYPE_OTHER:
            switch ((uint8_t) *(decstate->curbyte)) {
                case CBOR_FALSE:
                    if (decstate->is_map_key) {
                        _croak_invalid_map_key( aTHX_ "false", decstate->curbyte- decstate->start );
                    }

                    ret = newSVsv( get_sv("CBOR::Free::false", 0) );
                    ++decstate->curbyte;
                    break;

                case CBOR_TRUE:
                    if (decstate->is_map_key) {
                        _croak_invalid_map_key( aTHX_ "true", decstate->curbyte - decstate->start );
                    }

                    ret = newSVsv( get_sv("CBOR::Free::true", 0) );
                    ++decstate->curbyte;
                    break;

                case CBOR_NULL:
                    if (decstate->is_map_key) {
                        _croak_invalid_map_key( aTHX_ "null", decstate->curbyte - decstate->start );
                    }

                case CBOR_UNDEFINED:
                    if (decstate->is_map_key) {
                        _croak_invalid_map_key( aTHX_ "undefined", decstate->curbyte - decstate->start );
                    }

                    ret = newSVsv( &PL_sv_undef );
                    ++decstate->curbyte;
                    break;

                case CBOR_HALF_FLOAT:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, 3 );

                    ret = newSVnv( decode_half_float( (uint8_t *) (1 + decstate->curbyte) ) );

                    decstate->curbyte += 3;
                    break;

                case CBOR_FLOAT:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, 5 );

                    float decoded_flt;

#if IS_LITTLE_ENDIAN
                    decoded_flt = _decode_float_to_le( decstate, (uint8_t *) (1 + decstate->curbyte ) );
#else
                    decoded_flt = *( (float *) (1 + decstate->curbyte) );
#endif

                    ret = newSVnv( (NV) decoded_flt );

                    decstate->curbyte += 5;
                    break;

                case CBOR_DOUBLE:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, 9 );

                    double decoded_dbl;

#if IS_LITTLE_ENDIAN
                    decoded_dbl = _decode_double_to_le( decstate, (uint8_t *) (1 + decstate->curbyte ) );
#else
                    decoded_dbl = *( (double *) (1 + decstate->curbyte) );
#endif

                    ret = newSVnv( (NV) decoded_dbl );

                    decstate->curbyte += 9;
                    break;

                default:
                    _croak_invalid_control( aTHX_ decstate );
            }

            break;

        default:
            _croak("Unknown type!");
    }

    return ret;
}

//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    HV *stash = gv_stashpvn("CBOR::Free", 10, FALSE);
    newCONSTSUB(stash, "_MAX_RECURSION", newSVuv( MAX_ENCODE_RECURSE ));

SV *
_c_encode( SV * value )
    CODE:
        encode_ctx encode_state;
        encode_state.buffer = NULL;
        encode_state.len = 0;
        encode_state.recurse_count = 0;
        encode_state.is_canonical = false;

        _encode(aTHX_ value, &encode_state);

        RETVAL = newSVpvn( encode_state.buffer, encode_state.len );
    OUTPUT:
        RETVAL

SV *
_c_encode_canonical( SV * value )
    CODE:
        encode_ctx encode_state;
        encode_state.buffer = NULL;
        encode_state.len = 0;
        encode_state.recurse_count = 0;
        encode_state.is_canonical = true;

        _encode(aTHX_ value, &encode_state);

        RETVAL = newSVpvn( encode_state.buffer, encode_state.len );
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
            false,
        };

        RETVAL = _decode( aTHX_ &decode_state );

        if (decode_state.curbyte != decode_state.end) {
            STRLEN bytes_count = decode_state.end - decode_state.curbyte;

            char numstr[24];
            _void_uint_to_str(bytes_count, numstr, 24);

            char * words[2] = { numstr, NULL };

            call_argv("CBOR::Free::_warn_decode_leftover", G_DISCARD, words);
        }

    OUTPUT:
        RETVAL
